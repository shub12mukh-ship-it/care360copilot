-- =============================================================================
-- Care360 Copilot - Clinical Document Ingestion Pipeline (Cortex Search)
-- Target: CARE360_DB.DOCUMENTS
-- Region tested: AWS_AP_SOUTH_1 | Role: SYSADMIN | Warehouse: CARE360_WH
--
-- Flow:  local PDFs --(PUT)--> internal stage --(AI_PARSE_DOCUMENT)--> metadata
--        --(section split + recursive chunk)--> DOCUMENT_CHUNKS --> Cortex Search
-- =============================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE CARE360_WH;

-- -----------------------------------------------------------------------------
-- 1. Database + schema
-- -----------------------------------------------------------------------------
CREATE DATABASE IF NOT EXISTS CARE360_DB;
CREATE SCHEMA   IF NOT EXISTS CARE360_DB.DOCUMENTS;
USE SCHEMA CARE360_DB.DOCUMENTS;

-- -----------------------------------------------------------------------------
-- 2 + 3 + 4. Internal named stage with a directory table.
--   SNOWFLAKE_SSE encryption is REQUIRED for AI_PARSE_DOCUMENT to read files.
--   Folder structure (clinical_notes / guidelines / regulatory_documents) is
--   created implicitly by the path prefixes used in the PUT commands below.
-- -----------------------------------------------------------------------------
CREATE STAGE IF NOT EXISTS CARE360_DB.DOCUMENTS.CLINICAL_DOCUMENT_STAGE
  DIRECTORY  = (ENABLE = TRUE)
  ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE')
  COMMENT    = 'Internal stage for Care360 synthetic clinical PDFs (Cortex Search source)';

-- -----------------------------------------------------------------------------
-- 5. Upload local PDFs.  PUT is a client-side command (SnowSQL / Snowsight
--    "Upload" / VS Code Snowflake ext / Cortex Code). Adjust the file:// root
--    to your machine. AUTO_COMPRESS=FALSE keeps them readable as .pdf.
-- -----------------------------------------------------------------------------
PUT 'file://c:/Users/SREEJAP/Downloads/personal/care360-copilot/documents/clinical_notes/*.pdf'
    @CARE360_DB.DOCUMENTS.CLINICAL_DOCUMENT_STAGE/clinical_notes/
    AUTO_COMPRESS = FALSE OVERWRITE = TRUE;

PUT 'file://c:/Users/SREEJAP/Downloads/personal/care360-copilot/documents/guidelines/*.pdf'
    @CARE360_DB.DOCUMENTS.CLINICAL_DOCUMENT_STAGE/guidelines/
    AUTO_COMPRESS = FALSE OVERWRITE = TRUE;

-- NOTE: local folder is "regulatory", stage prefix is "regulatory_documents"
PUT 'file://c:/Users/SREEJAP/Downloads/personal/care360-copilot/documents/regulatory/*.pdf'
    @CARE360_DB.DOCUMENTS.CLINICAL_DOCUMENT_STAGE/regulatory_documents/
    AUTO_COMPRESS = FALSE OVERWRITE = TRUE;

-- Make files visible to the directory table
ALTER STAGE CARE360_DB.DOCUMENTS.CLINICAL_DOCUMENT_STAGE REFRESH;

-- -----------------------------------------------------------------------------
-- 6. Metadata extraction.
--    (a) PARSED_DOCUMENTS : run AI_PARSE_DOCUMENT once per file (materialized so
--        the LLM parse is not re-billed on every downstream query).
--    (b) DOCUMENT_METADATA: one row per page with the requested fields:
--        document_name, document_date, patient_id, document_type,
--        page_number, text_content.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE CARE360_DB.DOCUMENTS.PARSED_DOCUMENTS AS
SELECT
    d.RELATIVE_PATH                                    AS relative_path,
    REGEXP_SUBSTR(d.RELATIVE_PATH, '[^/]+$')           AS document_name,
    SPLIT_PART(d.RELATIVE_PATH, '/', 1)                AS document_type,
    d.SIZE                                             AS file_size_bytes,
    d.LAST_MODIFIED                                    AS file_last_modified,
    AI_PARSE_DOCUMENT(
        TO_FILE('@CARE360_DB.DOCUMENTS.CLINICAL_DOCUMENT_STAGE', d.RELATIVE_PATH),
        {'mode':'LAYOUT','page_split':true}
    )                                                  AS parsed_json,
    CURRENT_TIMESTAMP()                                AS parsed_at
FROM DIRECTORY(@CARE360_DB.DOCUMENTS.CLINICAL_DOCUMENT_STAGE) d;

CREATE OR REPLACE TABLE CARE360_DB.DOCUMENTS.DOCUMENT_METADATA AS
SELECT
    pd.document_name,
    TRY_TO_DATE(REGEXP_SUBSTR(pg.value:content::string, '[0-9]{4}-[0-9]{2}-[0-9]{2}')) AS document_date,
    COALESCE(REGEXP_SUBSTR(pg.value:content::string, 'P[0-9]{3,}'), 'N/A')             AS patient_id,
    pd.document_type,
    pg.index + 1                                                                       AS page_number,
    pg.value:content::string                                                           AS text_content,
    pd.relative_path
FROM CARE360_DB.DOCUMENTS.PARSED_DOCUMENTS pd,
     LATERAL FLATTEN(input => pd.parsed_json:pages) pg;

-- -----------------------------------------------------------------------------
-- 7. DOCUMENT_CHUNKS - one row per retrievable chunk.
--    Each page is split into markdown sections (# headers) and then
--    recursively chunked (<=800 chars, 100 overlap) as a safety net for long
--    sections. section_name is derived from the section header.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE CARE360_DB.DOCUMENTS.DOCUMENT_CHUNKS AS
WITH sections AS (
    SELECT
        m.document_name, m.patient_id, m.document_date, m.document_type,
        m.page_number, m.relative_path,
        s.index         AS section_seq,
        s.value::string AS section_text
    FROM CARE360_DB.DOCUMENTS.DOCUMENT_METADATA m,
         LATERAL FLATTEN(input => SPLIT(
             REGEXP_REPLACE(m.text_content, '(^|\\n)(#{1,6} )', '\\1~~~SPLIT~~~\\2'),
             '~~~SPLIT~~~')) s
    WHERE TRIM(s.value::string) <> ''
),
chunked AS (
    SELECT
        sec.*,
        c.index         AS chunk_seq,
        c.value::string AS chunk_text
    FROM sections sec,
         LATERAL FLATTEN(input =>
             SNOWFLAKE.CORTEX.SPLIT_TEXT_RECURSIVE_CHARACTER(sec.section_text, 'markdown', 800, 100)) c
    WHERE TRIM(c.value::string) <> ''
)
SELECT
    MD5(relative_path || '|' || page_number || '|' || section_seq || '|' || chunk_seq) AS chunk_id,
    document_name,
    patient_id,
    document_date,
    document_type,
    page_number,
    COALESCE(NULLIF(TRIM(REGEXP_SUBSTR(section_text, '#{1,6}\\s+([^\\n]+)', 1, 1, 'e', 1)), ''),
             'Document Header')                                                        AS section_name,
    TRIM(chunk_text)                                                                   AS text_content
FROM chunked;

-- -----------------------------------------------------------------------------
-- 8. Cortex Search service (consumes DOCUMENT_CHUNKS).
--    text_content is the searched body; the rest are filterable attributes.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE CORTEX SEARCH SERVICE CARE360_DB.DOCUMENTS.CLINICAL_DOCUMENT_SEARCH
  ON text_content
  ATTRIBUTES document_name, patient_id, document_date, document_type, page_number, section_name, chunk_id
  WAREHOUSE = CARE360_WH
  TARGET_LAG = '1 hour'
  AS
    SELECT chunk_id, text_content, document_name, patient_id,
           document_date, document_type, page_number, section_name
    FROM CARE360_DB.DOCUMENTS.DOCUMENT_CHUNKS;

-- =============================================================================
-- 9. VALIDATION
-- =============================================================================

-- 9a. Files uploaded successfully (expect 7 across 3 prefixes)
ALTER STAGE CARE360_DB.DOCUMENTS.CLINICAL_DOCUMENT_STAGE REFRESH;
SELECT SPLIT_PART(RELATIVE_PATH,'/',1) AS folder, COUNT(*) AS files, SUM(SIZE) AS bytes
FROM DIRECTORY(@CARE360_DB.DOCUMENTS.CLINICAL_DOCUMENT_STAGE)
GROUP BY 1 ORDER BY 1;

SELECT RELATIVE_PATH, SIZE, LAST_MODIFIED
FROM DIRECTORY(@CARE360_DB.DOCUMENTS.CLINICAL_DOCUMENT_STAGE)
ORDER BY RELATIVE_PATH;

-- 9b. Metadata extracted (expect 7 rows; P1007 on clinical notes, dates parsed)
SELECT document_name, document_type, patient_id, document_date, page_number,
       LENGTH(text_content) AS chars
FROM CARE360_DB.DOCUMENTS.DOCUMENT_METADATA
ORDER BY relative_path, page_number;

-- data-quality guard: no missing parses / dates
SELECT
  COUNT(*)                                             AS rows_total,
  COUNT_IF(text_content IS NULL OR text_content = '')  AS missing_text,
  COUNT_IF(document_date IS NULL)                      AS missing_date
FROM CARE360_DB.DOCUMENTS.DOCUMENT_METADATA;

-- 9c. Chunks created (expect >0, all chunk_ids unique, no empty bodies)
SELECT COUNT(*)                    AS total_chunks,
       COUNT(DISTINCT document_name) AS docs,
       COUNT(DISTINCT chunk_id)    AS distinct_chunk_ids,
       COUNT_IF(text_content IS NULL OR TRIM(text_content)='') AS empty_chunks
FROM CARE360_DB.DOCUMENTS.DOCUMENT_CHUNKS;

SELECT document_type, document_name, COUNT(*) AS chunks
FROM CARE360_DB.DOCUMENTS.DOCUMENT_CHUNKS
GROUP BY 1,2 ORDER BY 1,2;

-- 9d. Search service is live and returns results
SHOW CORTEX SEARCH SERVICES LIKE 'CLINICAL_DOCUMENT_SEARCH' IN SCHEMA CARE360_DB.DOCUMENTS;

WITH r AS (
  SELECT PARSE_JSON(SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
    'CARE360_DB.DOCUMENTS.CLINICAL_DOCUMENT_SEARCH',
    '{"query":"adverse event reporting timeline",
      "columns":["document_name","document_type","section_name","text_content"],
      "limit":3}')):results AS results
)
SELECT f.value:document_name::string AS document_name,
       f.value:document_type::string AS document_type,
       f.value:section_name::string  AS section_name,
       LEFT(f.value:text_content::string,90) AS preview
FROM r, LATERAL FLATTEN(input => r.results) f;
