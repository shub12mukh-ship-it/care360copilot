-- PATIENT360 Ingestion Layer
-- Canonical database target: PATIENT360
--
-- Deterministic, table-backed ingestion pipeline for staged PDFs and diagnostic
-- images that already live in the PATIENT360.RAW stages.
--
-- Design rules learned during implementation:
--   * AI_PARSE_DOCUMENT must NOT be called from a view. Cortex Search requires
--     change tracking, which is unsupported over non-deterministic functions.
--   * AI_PARSE_DOCUMENT raises a hard error (not NULL) when a staged file is
--     missing, so file presence must be confirmed BEFORE parsing.
--   * Parsing is therefore materialized into tables in per-family batches.
--
-- Layer boundary:
--   RAW stages        -> source of truth for binary assets
--   DOCUMENTS tables  -> inventory, extracted text, chunks, quality findings
--   CURATED/ANALYTICS -> consume standardized DOCUMENTS outputs only
--
-- No new CARE360_DB references may be introduced in forward-looking artifacts.

USE DATABASE PATIENT360;
USE SCHEMA DOCUMENTS;

-- =============================================================================
-- 1. Storage objects
-- =============================================================================

CREATE TABLE IF NOT EXISTS PATIENT360.DOCUMENTS.DOCUMENT_ASSET_INVENTORY (
    ingestion_asset_id STRING,
    asset_family STRING,
    document_category STRING,
    source_stage_name STRING,
    canonical_stage_path STRING,
    original_file_name STRING,
    source_record_id STRING,
    patient_id STRING,
    visit_id STRING,
    report_id STRING,
    source_record_type STRING,
    matching_basis_summary STRING,
    match_status STRING,
    match_confidence FLOAT,
    processing_status STRING,
    extraction_method STRING,
    source_event_date DATE,
    duplicate_candidate_count NUMBER,
    duplicate_candidate_rank NUMBER,
    asset_loaded_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    stage_file_present BOOLEAN,
    file_size_bytes NUMBER
);

CREATE TABLE IF NOT EXISTS PATIENT360.DOCUMENTS.DOCUMENT_EXTRACTED_TEXT_TABLE (
    extraction_record_id STRING,
    ingestion_asset_id STRING,
    extraction_mode STRING,
    extraction_outcome_status STRING,
    extracted_text_body STRING,
    extracted_text_length NUMBER,
    extraction_detail STRING,
    parsed_page_count NUMBER,
    canonical_stage_path STRING,
    original_file_name STRING,
    patient_id STRING,
    visit_id STRING,
    report_id STRING,
    document_category STRING,
    source_event_date DATE,
    loaded_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE TABLE IF NOT EXISTS PATIENT360.DOCUMENTS.DOCUMENT_SEARCH_CHUNKS_TABLE (
    chunk_id STRING,
    ingestion_asset_id STRING,
    extraction_record_id STRING,
    chunk_order NUMBER,
    chunk_text STRING,
    patient_id STRING,
    visit_id STRING,
    report_id STRING,
    document_category STRING,
    source_event_date DATE,
    canonical_stage_path STRING,
    original_file_name STRING,
    chunk_eligibility_status STRING,
    target_chunk_size NUMBER,
    target_chunk_overlap NUMBER,
    loaded_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE TABLE IF NOT EXISTS PATIENT360.DOCUMENTS.DOCUMENT_INGESTION_QUALITY_FINDINGS_TABLE (
    quality_finding_id STRING,
    ingestion_asset_id STRING,
    issue_grouping_key STRING,
    issue_category STRING,
    review_priority STRING,
    issue_description STRING,
    remediation_hint STRING,
    first_detected_timestamp TIMESTAMP_NTZ,
    review_status STRING,
    loaded_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- =============================================================================
-- 2. Stage file registry (file-existence source of truth)
-- =============================================================================
-- Built from DIRECTORY() so parsing can be gated on files that actually exist.

CREATE OR REPLACE TABLE PATIENT360.DOCUMENTS.STAGE_FILE_REGISTRY AS
SELECT 'PATIENT360.RAW.CLINICAL_NOTE_PDFS' AS source_stage_name, RELATIVE_PATH AS original_file_name,
       SIZE AS file_size_bytes, LAST_MODIFIED AS stage_last_modified
FROM DIRECTORY(@PATIENT360.RAW.CLINICAL_NOTE_PDFS)
UNION ALL
SELECT 'PATIENT360.RAW.LAB_RESULT_PDFS', RELATIVE_PATH, SIZE, LAST_MODIFIED
FROM DIRECTORY(@PATIENT360.RAW.LAB_RESULT_PDFS)
UNION ALL
SELECT 'PATIENT360.RAW.PRESCRIPTION_PDFS', RELATIVE_PATH, SIZE, LAST_MODIFIED
FROM DIRECTORY(@PATIENT360.RAW.PRESCRIPTION_PDFS)
UNION ALL
SELECT 'PATIENT360.RAW.DIAGNOSTIC_IMAGES', RELATIVE_PATH, SIZE, LAST_MODIFIED
FROM DIRECTORY(@PATIENT360.RAW.DIAGNOSTIC_IMAGES);

-- =============================================================================
-- 3. Canonical asset inventory
-- =============================================================================
-- processing_status vocabulary:
--   READY_FOR_EXTRACTION  file present and eligible for parsing
--   DUPLICATE_SUSPECT     same stage + file name appears more than once
--   BROKEN_REFERENCE      metadata points at a file absent from the stage
--   UNMATCHED             no confident patient/report assignment
--   UNPARSEABLE           unsupported extension for the configured flow
-- extraction_method: PDF_LAYOUT | IMAGE_OCR

INSERT OVERWRITE INTO PATIENT360.DOCUMENTS.DOCUMENT_ASSET_INVENTORY (
    ingestion_asset_id, asset_family, document_category, source_stage_name, canonical_stage_path,
    original_file_name, source_record_id, patient_id, visit_id, report_id, source_record_type,
    matching_basis_summary, match_status, match_confidence, processing_status, extraction_method,
    source_event_date, duplicate_candidate_count, duplicate_candidate_rank, stage_file_present, file_size_bytes
)
WITH note_assets AS (
    SELECT 'CLINICAL_NOTE_PDF:' || note_id AS ingestion_asset_id,
           'CLINICAL_NOTE_PDF' AS asset_family,
           'CLINICAL_NOTE' AS document_category,
           'PATIENT360.RAW.CLINICAL_NOTE_PDFS' AS source_stage_name,
           '@PATIENT360.RAW.CLINICAL_NOTE_PDFS/' || pdf_filename AS canonical_stage_path,
           pdf_filename AS original_file_name,
           note_id AS source_record_id, patient_id, visit_id, CAST(NULL AS STRING) AS report_id,
           'RAW.CLINICAL_NOTES' AS source_record_type,
           'Filename matched from clinical note metadata' AS matching_basis_summary,
           'MATCHED' AS match_status, 1.0 AS match_confidence,
           IFF(LOWER(pdf_filename) LIKE '%.pdf', 'READY_FOR_EXTRACTION', 'UNPARSEABLE') AS processing_status,
           'PDF_LAYOUT' AS extraction_method, note_date AS source_event_date
    FROM PATIENT360.RAW.CLINICAL_NOTES WHERE COALESCE(pdf_filename, '') <> ''
),
lab_assets AS (
    SELECT 'LAB_RESULT_PDF:' || lab_result_id, 'LAB_RESULT_PDF', 'LAB_DOCUMENT',
           'PATIENT360.RAW.LAB_RESULT_PDFS',
           '@PATIENT360.RAW.LAB_RESULT_PDFS/' || pdf_filename, pdf_filename,
           lab_result_id, patient_id, visit_id, CAST(NULL AS STRING),
           'RAW.LAB_RESULTS', 'Filename matched from lab metadata', 'MATCHED', 1.0,
           IFF(LOWER(pdf_filename) LIKE '%.pdf', 'READY_FOR_EXTRACTION', 'UNPARSEABLE'),
           'PDF_LAYOUT', test_date
    FROM PATIENT360.RAW.LAB_RESULTS WHERE COALESCE(pdf_filename, '') <> ''
),
prescription_assets AS (
    SELECT 'PRESCRIPTION_PDF:' || prescription_id, 'PRESCRIPTION_PDF', 'PRESCRIPTION',
           'PATIENT360.RAW.PRESCRIPTION_PDFS',
           '@PATIENT360.RAW.PRESCRIPTION_PDFS/' || pdf_filename, pdf_filename,
           prescription_id, patient_id, visit_id, CAST(NULL AS STRING),
           'RAW.PRESCRIPTIONS', 'Filename matched from prescription metadata', 'MATCHED', 1.0,
           IFF(LOWER(pdf_filename) LIKE '%.pdf', 'READY_FOR_EXTRACTION', 'UNPARSEABLE'),
           'PDF_LAYOUT', prescription_date
    FROM PATIENT360.RAW.PRESCRIPTIONS WHERE COALESCE(pdf_filename, '') <> ''
),
diagnostic_assets AS (
    SELECT 'DIAGNOSTIC_IMAGE:' || report_id, 'DIAGNOSTIC_IMAGE', 'DIAGNOSTIC_IMAGE',
           'PATIENT360.RAW.DIAGNOSTIC_IMAGES',
           '@PATIENT360.RAW.DIAGNOSTIC_IMAGES/' || image_filename, image_filename,
           report_id, patient_id, visit_id, report_id,
           'RAW.DIAGNOSTIC_REPORTS', 'Filename matched from diagnostic report metadata',
           IFF(COALESCE(patient_id, '') = '', 'UNMATCHED', 'MATCHED'),
           IFF(COALESCE(patient_id, '') = '', 0.0, 1.0),
           CASE
               WHEN COALESCE(patient_id, '') = '' THEN 'UNMATCHED'
               WHEN LOWER(image_filename) LIKE '%.png' OR LOWER(image_filename) LIKE '%.jpg'
                 OR LOWER(image_filename) LIKE '%.jpeg' OR LOWER(image_filename) LIKE '%.tif'
                 OR LOWER(image_filename) LIKE '%.tiff' THEN 'READY_FOR_EXTRACTION'
               ELSE 'UNPARSEABLE'
           END,
           'IMAGE_OCR', exam_date
    FROM PATIENT360.RAW.DIAGNOSTIC_REPORTS WHERE COALESCE(image_filename, '') <> ''
),
unioned_assets AS (
    SELECT * FROM note_assets
    UNION ALL SELECT * FROM lab_assets
    UNION ALL SELECT * FROM prescription_assets
    UNION ALL SELECT * FROM diagnostic_assets
),
ranked_assets AS (
    SELECT *,
           COUNT(*) OVER (PARTITION BY source_stage_name, original_file_name) AS duplicate_candidate_count,
           ROW_NUMBER() OVER (PARTITION BY source_stage_name, original_file_name
                              ORDER BY source_event_date DESC, source_record_id DESC) AS duplicate_candidate_rank
    FROM unioned_assets
)
SELECT a.ingestion_asset_id, a.asset_family, a.document_category, a.source_stage_name, a.canonical_stage_path,
       a.original_file_name, a.source_record_id, a.patient_id, a.visit_id, a.report_id, a.source_record_type,
       a.matching_basis_summary, a.match_status, a.match_confidence,
       CASE
           WHEN r.original_file_name IS NULL THEN 'BROKEN_REFERENCE'
           WHEN a.duplicate_candidate_count > 1 THEN 'DUPLICATE_SUSPECT'
           ELSE a.processing_status
       END AS processing_status,
       a.extraction_method, a.source_event_date, a.duplicate_candidate_count, a.duplicate_candidate_rank,
       (r.original_file_name IS NOT NULL) AS stage_file_present, r.file_size_bytes
FROM ranked_assets a
LEFT JOIN PATIENT360.DOCUMENTS.STAGE_FILE_REGISTRY r
       ON r.source_stage_name = a.source_stage_name AND r.original_file_name = a.original_file_name;

-- =============================================================================
-- 4. Batch extraction (re-runnable)
-- =============================================================================
-- Each statement below picks up only assets that are (a) present in the stage and
-- (b) not already extracted. Re-run each statement until 0 rows are inserted.
-- Batch sizes keep individual statements well inside statement timeouts.

-- 4a. PDF families (clinical notes, lab results, prescriptions) -- LAYOUT mode
INSERT INTO PATIENT360.DOCUMENTS.DOCUMENT_EXTRACTED_TEXT_TABLE (
    extraction_record_id, ingestion_asset_id, extraction_mode, extraction_outcome_status,
    extracted_text_body, extracted_text_length, extraction_detail, parsed_page_count,
    canonical_stage_path, original_file_name, patient_id, visit_id, report_id,
    document_category, source_event_date
)
WITH candidate_assets AS (
    SELECT i.* FROM PATIENT360.DOCUMENTS.DOCUMENT_ASSET_INVENTORY i
    WHERE i.stage_file_present = TRUE
      AND i.extraction_method = 'PDF_LAYOUT'
      AND i.processing_status IN ('READY_FOR_EXTRACTION', 'DUPLICATE_SUSPECT')
      AND NOT EXISTS (SELECT 1 FROM PATIENT360.DOCUMENTS.DOCUMENT_EXTRACTED_TEXT_TABLE e
                      WHERE e.ingestion_asset_id = i.ingestion_asset_id)
    QUALIFY ROW_NUMBER() OVER (ORDER BY i.ingestion_asset_id) <= 90
),
parsed_docs AS (
    SELECT ingestion_asset_id, canonical_stage_path, original_file_name, patient_id, visit_id, report_id,
           document_category, source_event_date,
           AI_PARSE_DOCUMENT(TO_FILE(canonical_stage_path),
                             OBJECT_CONSTRUCT('mode', 'LAYOUT', 'page_split', TRUE), TRUE) AS parse_result
    FROM candidate_assets
),
parsed_pages AS (
    SELECT ingestion_asset_id, canonical_stage_path, original_file_name, patient_id, visit_id, report_id,
           document_category, source_event_date,
           parse_result:error::STRING AS parse_error,
           parse_result:metadata:pageCount::INTEGER AS parsed_page_count,
           COALESCE(
               LISTAGG(page.value:content::STRING, '\n\n') WITHIN GROUP (ORDER BY page.value:index::INTEGER),
               parse_result:value:content::STRING
           ) AS extracted_text_body
    FROM parsed_docs, LATERAL FLATTEN(input => parse_result:value:pages, outer => TRUE) page
    GROUP BY ingestion_asset_id, canonical_stage_path, original_file_name, patient_id, visit_id, report_id,
             document_category, source_event_date, parse_result:error, parse_result:metadata:pageCount,
             parse_result:value:content
)
SELECT ingestion_asset_id || ':EXTRACT', ingestion_asset_id, 'PDF_LAYOUT',
       CASE WHEN parse_error IS NOT NULL THEN 'FAILED_EXTRACTION'
            WHEN extracted_text_body IS NOT NULL AND LENGTH(TRIM(extracted_text_body)) > 0 THEN 'SEARCHABLE_TEXT_READY'
            ELSE 'FAILED_EXTRACTION' END,
       extracted_text_body, LENGTH(COALESCE(extracted_text_body, '')),
       COALESCE(parse_error, IFF(extracted_text_body IS NULL, 'No trustworthy text extracted', NULL)),
       parsed_page_count, canonical_stage_path, original_file_name, patient_id, visit_id, report_id,
       document_category, source_event_date
FROM parsed_pages;

-- 4b. Diagnostic images -- OCR mode
INSERT INTO PATIENT360.DOCUMENTS.DOCUMENT_EXTRACTED_TEXT_TABLE (
    extraction_record_id, ingestion_asset_id, extraction_mode, extraction_outcome_status,
    extracted_text_body, extracted_text_length, extraction_detail, parsed_page_count,
    canonical_stage_path, original_file_name, patient_id, visit_id, report_id,
    document_category, source_event_date
)
WITH candidate_assets AS (
    SELECT i.* FROM PATIENT360.DOCUMENTS.DOCUMENT_ASSET_INVENTORY i
    WHERE i.stage_file_present = TRUE
      AND i.extraction_method = 'IMAGE_OCR'
      AND i.processing_status IN ('READY_FOR_EXTRACTION', 'DUPLICATE_SUSPECT')
      AND NOT EXISTS (SELECT 1 FROM PATIENT360.DOCUMENTS.DOCUMENT_EXTRACTED_TEXT_TABLE e
                      WHERE e.ingestion_asset_id = i.ingestion_asset_id)
    QUALIFY ROW_NUMBER() OVER (ORDER BY i.ingestion_asset_id) <= 90
),
parsed_docs AS (
    SELECT ingestion_asset_id, canonical_stage_path, original_file_name, patient_id, visit_id, report_id,
           document_category, source_event_date,
           AI_PARSE_DOCUMENT(TO_FILE(canonical_stage_path), OBJECT_CONSTRUCT('mode', 'OCR'), TRUE) AS parse_result
    FROM candidate_assets
)
SELECT ingestion_asset_id || ':EXTRACT', ingestion_asset_id, 'IMAGE_OCR',
       CASE WHEN parse_result:error::STRING IS NOT NULL THEN 'FAILED_EXTRACTION'
            WHEN parse_result:value:content::STRING IS NOT NULL
             AND LENGTH(TRIM(parse_result:value:content::STRING)) > 0 THEN 'SEARCHABLE_TEXT_READY'
            ELSE 'METADATA_ONLY' END,
       parse_result:value:content::STRING,
       LENGTH(COALESCE(parse_result:value:content::STRING, '')),
       COALESCE(parse_result:error::STRING,
                IFF(parse_result:value:content::STRING IS NULL, 'No trustworthy text recovered by image OCR', NULL)),
       parse_result:metadata:pageCount::INTEGER,
       canonical_stage_path, original_file_name, patient_id, visit_id, report_id,
       document_category, source_event_date
FROM parsed_docs;

-- 4c. Preserve non-parsed assets explicitly so nothing disappears silently
INSERT INTO PATIENT360.DOCUMENTS.DOCUMENT_EXTRACTED_TEXT_TABLE (
    extraction_record_id, ingestion_asset_id, extraction_mode, extraction_outcome_status,
    extracted_text_body, extracted_text_length, extraction_detail, parsed_page_count,
    canonical_stage_path, original_file_name, patient_id, visit_id, report_id,
    document_category, source_event_date
)
SELECT i.ingestion_asset_id || ':EXTRACT', i.ingestion_asset_id, i.extraction_method,
       CASE WHEN i.processing_status = 'UNMATCHED' THEN 'METADATA_ONLY' ELSE 'FAILED_EXTRACTION' END,
       NULL, 0,
       CASE WHEN i.processing_status = 'BROKEN_REFERENCE' THEN 'Referenced file is not present in the source stage'
            WHEN i.processing_status = 'UNMATCHED' THEN 'Asset remains metadata-only because no confident patient/report assignment was derived'
            WHEN i.processing_status = 'UNPARSEABLE' THEN 'Asset file extension is unsupported for the configured parsing flow'
            ELSE 'Asset was not eligible for parsing' END,
       NULL, i.canonical_stage_path, i.original_file_name, i.patient_id, i.visit_id, i.report_id,
       i.document_category, i.source_event_date
FROM PATIENT360.DOCUMENTS.DOCUMENT_ASSET_INVENTORY i
WHERE NOT EXISTS (SELECT 1 FROM PATIENT360.DOCUMENTS.DOCUMENT_EXTRACTED_TEXT_TABLE e
                  WHERE e.ingestion_asset_id = i.ingestion_asset_id);

-- =============================================================================
-- 5. Chunking (deterministic, table to table)
-- =============================================================================
-- Chunk size 800 chars / overlap 100 chars per the project constitution.

INSERT OVERWRITE INTO PATIENT360.DOCUMENTS.DOCUMENT_SEARCH_CHUNKS_TABLE (
    chunk_id, ingestion_asset_id, extraction_record_id, chunk_order, chunk_text,
    patient_id, visit_id, report_id, document_category, source_event_date,
    canonical_stage_path, original_file_name, chunk_eligibility_status,
    target_chunk_size, target_chunk_overlap
)
WITH chunk_arrays AS (
    SELECT extraction_record_id, ingestion_asset_id, patient_id, visit_id, report_id,
           document_category, source_event_date, canonical_stage_path, original_file_name,
           SNOWFLAKE.CORTEX.SPLIT_TEXT_RECURSIVE_CHARACTER(extracted_text_body, 'markdown', 800, 100) AS chunk_array
    FROM PATIENT360.DOCUMENTS.DOCUMENT_EXTRACTED_TEXT_TABLE
    WHERE extraction_outcome_status = 'SEARCHABLE_TEXT_READY'
      AND extracted_text_body IS NOT NULL
)
SELECT extraction_record_id || ':CHUNK:' || (chunk.index + 1), ingestion_asset_id, extraction_record_id,
       chunk.index + 1, chunk.value::STRING, patient_id, visit_id, report_id, document_category,
       source_event_date, canonical_stage_path, original_file_name, 'INDEX_READY', 800, 100
FROM chunk_arrays, LATERAL FLATTEN(input => chunk_array) chunk;

-- =============================================================================
-- 6. Ingestion quality findings
-- =============================================================================

INSERT OVERWRITE INTO PATIENT360.DOCUMENTS.DOCUMENT_INGESTION_QUALITY_FINDINGS_TABLE (
    quality_finding_id, ingestion_asset_id, issue_grouping_key, issue_category, review_priority,
    issue_description, remediation_hint, first_detected_timestamp, review_status
)
WITH inventory_findings AS (
    SELECT ingestion_asset_id || ':QUALITY:' || processing_status,
           ingestion_asset_id,
           source_stage_name || ':' || COALESCE(original_file_name, '<missing-file-name>'),
           CASE WHEN processing_status = 'BROKEN_REFERENCE' THEN 'BROKEN_STAGE_REFERENCE'
                WHEN processing_status = 'DUPLICATE_SUSPECT' THEN 'DUPLICATE_ASSET'
                WHEN processing_status = 'UNMATCHED' THEN 'UNMATCHED_ASSET'
                WHEN processing_status = 'UNPARSEABLE' THEN 'UNPARSEABLE_ASSET' ELSE NULL END,
           CASE WHEN processing_status IN ('BROKEN_REFERENCE','UNMATCHED','UNPARSEABLE') THEN 'HIGH'
                WHEN processing_status = 'DUPLICATE_SUSPECT' THEN 'MEDIUM' ELSE NULL END,
           CASE WHEN processing_status = 'BROKEN_REFERENCE' THEN 'Metadata references a staged file that does not exist in the source stage'
                WHEN processing_status = 'DUPLICATE_SUSPECT' THEN 'More than one asset row shares the same source stage and original file name'
                WHEN processing_status = 'UNMATCHED' THEN 'Asset could not be assigned confidently to patient/report context'
                WHEN processing_status = 'UNPARSEABLE' THEN 'Asset uses an unsupported extension for the configured parsing flow' ELSE NULL END,
           CASE WHEN processing_status = 'BROKEN_REFERENCE' THEN 'Upload the missing file to the stage or correct the file name in raw metadata'
                WHEN processing_status = 'DUPLICATE_SUSPECT' THEN 'Review duplicate business identity and keep one canonical asset path'
                WHEN processing_status = 'UNMATCHED' THEN 'Review filename and raw metadata to recover patient/report linkage'
                WHEN processing_status = 'UNPARSEABLE' THEN 'Convert the asset to a supported format or extend the parsing flow' ELSE NULL END,
           CURRENT_TIMESTAMP(), 'OPEN'
    FROM PATIENT360.DOCUMENTS.DOCUMENT_ASSET_INVENTORY
),
extraction_findings AS (
    SELECT extraction_record_id || ':QUALITY:FAILED_EXTRACTION', ingestion_asset_id, canonical_stage_path,
           'UNPARSEABLE_ASSET', 'HIGH', extraction_detail,
           'Inspect AI_PARSE_DOCUMENT output or confirm the source file is readable, then re-run the family batch',
           CURRENT_TIMESTAMP(), 'OPEN'
    FROM PATIENT360.DOCUMENTS.DOCUMENT_EXTRACTED_TEXT_TABLE
    WHERE extraction_outcome_status = 'FAILED_EXTRACTION'
),
metadata_only_findings AS (
    SELECT extraction_record_id || ':QUALITY:METADATA_ONLY', ingestion_asset_id, canonical_stage_path,
           'METADATA_ONLY_ASSET', 'LOW', COALESCE(extraction_detail, 'Asset carries metadata but no searchable text'),
           'Confirm whether this asset should ever be searchable; otherwise keep as evidence metadata only',
           CURRENT_TIMESTAMP(), 'OPEN'
    FROM PATIENT360.DOCUMENTS.DOCUMENT_EXTRACTED_TEXT_TABLE
    WHERE extraction_outcome_status = 'METADATA_ONLY'
),
missing_file_candidates AS (
    SELECT asset_family || ':QUALITY:MISSING_FILE:' || source_record_id,
           asset_family || ':' || source_record_id,
           source_stage_name || ':<missing-file-name>',
           'MISSING_FILE', 'HIGH',
           'Raw metadata row lacks a usable staged file name for the expected source stage',
           'Populate or correct the staged file name in the raw metadata source',
           CURRENT_TIMESTAMP(), 'OPEN'
    FROM (
        SELECT 'CLINICAL_NOTE_PDF' AS asset_family, note_id AS source_record_id,
               'PATIENT360.RAW.CLINICAL_NOTE_PDFS' AS source_stage_name
        FROM PATIENT360.RAW.CLINICAL_NOTES WHERE COALESCE(pdf_filename, '') = ''
        UNION ALL SELECT 'LAB_RESULT_PDF', lab_result_id, 'PATIENT360.RAW.LAB_RESULT_PDFS'
        FROM PATIENT360.RAW.LAB_RESULTS WHERE COALESCE(pdf_filename, '') = ''
        UNION ALL SELECT 'PRESCRIPTION_PDF', prescription_id, 'PATIENT360.RAW.PRESCRIPTION_PDFS'
        FROM PATIENT360.RAW.PRESCRIPTIONS WHERE COALESCE(pdf_filename, '') = ''
        UNION ALL SELECT 'DIAGNOSTIC_IMAGE', report_id, 'PATIENT360.RAW.DIAGNOSTIC_IMAGES'
        FROM PATIENT360.RAW.DIAGNOSTIC_REPORTS WHERE COALESCE(image_filename, '') = ''
    ) missing_assets
)
SELECT * FROM inventory_findings WHERE issue_category IS NOT NULL
UNION ALL SELECT * FROM extraction_findings
UNION ALL SELECT * FROM metadata_only_findings
UNION ALL SELECT * FROM missing_file_candidates;

-- =============================================================================
-- 7. Stable consumption views
-- =============================================================================

CREATE OR REPLACE VIEW PATIENT360.DOCUMENTS.DOCUMENT_ASSET_MATCH_CONTEXT AS
SELECT ingestion_asset_id, patient_id, visit_id, report_id, source_record_type,
       matching_basis_summary, match_confidence, match_status AS decision_status,
       IFF(match_status = 'UNMATCHED', 'No confident patient/report assignment was derived', NULL) AS unmatched_reason
FROM PATIENT360.DOCUMENTS.DOCUMENT_ASSET_INVENTORY;

CREATE OR REPLACE VIEW PATIENT360.DOCUMENTS.DOCUMENT_EXTRACTED_TEXT AS
SELECT * FROM PATIENT360.DOCUMENTS.DOCUMENT_EXTRACTED_TEXT_TABLE;

CREATE OR REPLACE VIEW PATIENT360.DOCUMENTS.DOCUMENT_SEARCH_CHUNKS AS
SELECT * FROM PATIENT360.DOCUMENTS.DOCUMENT_SEARCH_CHUNKS_TABLE;

CREATE OR REPLACE VIEW PATIENT360.DOCUMENTS.DOCUMENT_INGESTION_QUALITY_FINDINGS AS
SELECT * FROM PATIENT360.DOCUMENTS.DOCUMENT_INGESTION_QUALITY_FINDINGS_TABLE;

-- =============================================================================
-- 8. Cortex Search service (deterministic source table)
-- =============================================================================

CREATE OR REPLACE CORTEX SEARCH SERVICE PATIENT360.DOCUMENTS.DOCUMENT_SEARCH_SERVICE
ON chunk_text
ATTRIBUTES patient_id, visit_id, report_id, document_category, source_event_date,
           canonical_stage_path, original_file_name, ingestion_asset_id
WAREHOUSE = CARE360_WH
TARGET_LAG = '1 hour'
EMBEDDING_MODEL = 'snowflake-arctic-embed-l-v2.0'
AS (
    SELECT chunk_id, chunk_text, patient_id, visit_id, report_id, document_category,
           source_event_date, canonical_stage_path, original_file_name, ingestion_asset_id
    FROM PATIENT360.DOCUMENTS.DOCUMENT_SEARCH_CHUNKS_TABLE
);

-- After a chunk rebuild, force the index forward instead of waiting for target lag:
--   ALTER CORTEX SEARCH SERVICE PATIENT360.DOCUMENTS.DOCUMENT_SEARCH_SERVICE REFRESH;
-- If serving was auto-suspended by inactivity:
--   ALTER CORTEX SEARCH SERVICE PATIENT360.DOCUMENTS.DOCUMENT_SEARCH_SERVICE RESUME;
