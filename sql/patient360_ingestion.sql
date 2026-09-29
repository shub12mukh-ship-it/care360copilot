-- PATIENT360 Ingestion Logic
-- Deterministic, table-backed ingestion pipeline for staged PDFs and images.
-- This version intentionally avoids live parse-backed views for execution.

USE DATABASE PATIENT360;
USE SCHEMA DOCUMENTS;

-- -----------------------------------------------------------------------------
-- Canonical inventory and deterministic storage tables
-- -----------------------------------------------------------------------------

CREATE OR REPLACE TABLE PATIENT360.DOCUMENTS.DOCUMENT_ASSET_INVENTORY (
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
    asset_loaded_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE OR REPLACE TABLE PATIENT360.DOCUMENTS.DOCUMENT_EXTRACTED_TEXT_TABLE (
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

CREATE OR REPLACE TABLE PATIENT360.DOCUMENTS.DOCUMENT_SEARCH_CHUNKS_TABLE (
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

CREATE OR REPLACE TABLE PATIENT360.DOCUMENTS.DOCUMENT_INGESTION_QUALITY_FINDINGS_TABLE (
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

-- -----------------------------------------------------------------------------
-- Rebuild canonical inventory deterministically from raw metadata
-- -----------------------------------------------------------------------------

TRUNCATE TABLE PATIENT360.DOCUMENTS.DOCUMENT_ASSET_INVENTORY;

INSERT INTO PATIENT360.DOCUMENTS.DOCUMENT_ASSET_INVENTORY (
    ingestion_asset_id,
    asset_family,
    document_category,
    source_stage_name,
    canonical_stage_path,
    original_file_name,
    source_record_id,
    patient_id,
    visit_id,
    report_id,
    source_record_type,
    matching_basis_summary,
    match_status,
    match_confidence,
    processing_status,
    extraction_method,
    source_event_date,
    duplicate_candidate_count,
    duplicate_candidate_rank
)
WITH note_assets AS (
    SELECT
        'CLINICAL_NOTE_PDF:' || note_id AS ingestion_asset_id,
        'CLINICAL_NOTE_PDF' AS asset_family,
        'CLINICAL_NOTE' AS document_category,
        'PATIENT360.RAW.CLINICAL_NOTE_PDFS' AS source_stage_name,
        '@PATIENT360.RAW.CLINICAL_NOTE_PDFS/' || pdf_filename AS canonical_stage_path,
        pdf_filename AS original_file_name,
        note_id AS source_record_id,
        patient_id,
        visit_id,
        CAST(NULL AS STRING) AS report_id,
        'RAW.CLINICAL_NOTES' AS source_record_type,
        'Filename matched from clinical note metadata' AS matching_basis_summary,
        'MATCHED' AS match_status,
        1.0 AS match_confidence,
        CASE
            WHEN LOWER(pdf_filename) LIKE '%.pdf' THEN 'READY_FOR_EXTRACTION'
            ELSE 'UNPARSEABLE'
        END AS processing_status,
        'PDF_LAYOUT' AS extraction_method,
        note_date AS source_event_date
    FROM PATIENT360.RAW.CLINICAL_NOTES
    WHERE COALESCE(pdf_filename, '') <> ''
),
lab_assets AS (
    SELECT
        'LAB_RESULT_PDF:' || lab_result_id AS ingestion_asset_id,
        'LAB_RESULT_PDF' AS asset_family,
        'LAB_DOCUMENT' AS document_category,
        'PATIENT360.RAW.LAB_RESULT_PDFS' AS source_stage_name,
        '@PATIENT360.RAW.LAB_RESULT_PDFS/' || pdf_filename AS canonical_stage_path,
        pdf_filename AS original_file_name,
        lab_result_id AS source_record_id,
        patient_id,
        visit_id,
        CAST(NULL AS STRING) AS report_id,
        'RAW.LAB_RESULTS' AS source_record_type,
        'Filename matched from lab metadata' AS matching_basis_summary,
        'MATCHED' AS match_status,
        1.0 AS match_confidence,
        CASE
            WHEN LOWER(pdf_filename) LIKE '%.pdf' THEN 'READY_FOR_EXTRACTION'
            ELSE 'UNPARSEABLE'
        END AS processing_status,
        'PDF_LAYOUT' AS extraction_method,
        test_date AS source_event_date
    FROM PATIENT360.RAW.LAB_RESULTS
    WHERE COALESCE(pdf_filename, '') <> ''
),
prescription_assets AS (
    SELECT
        'PRESCRIPTION_PDF:' || prescription_id AS ingestion_asset_id,
        'PRESCRIPTION_PDF' AS asset_family,
        'PRESCRIPTION' AS document_category,
        'PATIENT360.RAW.PRESCRIPTION_PDFS' AS source_stage_name,
        '@PATIENT360.RAW.PRESCRIPTION_PDFS/' || pdf_filename AS canonical_stage_path,
        pdf_filename AS original_file_name,
        prescription_id AS source_record_id,
        patient_id,
        visit_id,
        CAST(NULL AS STRING) AS report_id,
        'RAW.PRESCRIPTIONS' AS source_record_type,
        'Filename matched from prescription metadata' AS matching_basis_summary,
        'MATCHED' AS match_status,
        1.0 AS match_confidence,
        CASE
            WHEN LOWER(pdf_filename) LIKE '%.pdf' THEN 'READY_FOR_EXTRACTION'
            ELSE 'UNPARSEABLE'
        END AS processing_status,
        'PDF_LAYOUT' AS extraction_method,
        prescription_date AS source_event_date
    FROM PATIENT360.RAW.PRESCRIPTIONS
    WHERE COALESCE(pdf_filename, '') <> ''
),
diagnostic_assets AS (
    SELECT
        'DIAGNOSTIC_IMAGE:' || report_id AS ingestion_asset_id,
        'DIAGNOSTIC_IMAGE' AS asset_family,
        'DIAGNOSTIC_IMAGE' AS document_category,
        'PATIENT360.RAW.DIAGNOSTIC_IMAGES' AS source_stage_name,
        '@PATIENT360.RAW.DIAGNOSTIC_IMAGES/' || image_filename AS canonical_stage_path,
        image_filename AS original_file_name,
        report_id AS source_record_id,
        patient_id,
        visit_id,
        report_id,
        'RAW.DIAGNOSTIC_REPORTS' AS source_record_type,
        'Filename matched from diagnostic report metadata' AS matching_basis_summary,
        IFF(COALESCE(patient_id, '') = '', 'UNMATCHED', 'MATCHED') AS match_status,
        IFF(COALESCE(patient_id, '') = '', 0.0, 1.0) AS match_confidence,
        CASE
            WHEN COALESCE(patient_id, '') = '' THEN 'UNMATCHED'
            WHEN LOWER(image_filename) LIKE '%.png'
              OR LOWER(image_filename) LIKE '%.jpg'
              OR LOWER(image_filename) LIKE '%.jpeg'
              OR LOWER(image_filename) LIKE '%.tif'
              OR LOWER(image_filename) LIKE '%.tiff' THEN 'READY_FOR_EXTRACTION'
            ELSE 'UNPARSEABLE'
        END AS processing_status,
        'IMAGE_OCR' AS extraction_method,
        exam_date AS source_event_date
    FROM PATIENT360.RAW.DIAGNOSTIC_REPORTS
    WHERE COALESCE(image_filename, '') <> ''
),
unioned_assets AS (
    SELECT * FROM note_assets
    UNION ALL
    SELECT * FROM lab_assets
    UNION ALL
    SELECT * FROM prescription_assets
    UNION ALL
    SELECT * FROM diagnostic_assets
),
ranked_assets AS (
    SELECT
        *,
        COUNT(*) OVER (PARTITION BY source_stage_name, original_file_name) AS duplicate_candidate_count,
        ROW_NUMBER() OVER (
            PARTITION BY source_stage_name, original_file_name
            ORDER BY source_event_date DESC, source_record_id DESC
        ) AS duplicate_candidate_rank
    FROM unioned_assets
)
SELECT
    ingestion_asset_id,
    asset_family,
    document_category,
    source_stage_name,
    canonical_stage_path,
    original_file_name,
    source_record_id,
    patient_id,
    visit_id,
    report_id,
    source_record_type,
    matching_basis_summary,
    match_status,
    match_confidence,
    CASE
        WHEN duplicate_candidate_count > 1 THEN 'DUPLICATE_SUSPECT'
        ELSE processing_status
    END AS processing_status,
    extraction_method,
    source_event_date,
    duplicate_candidate_count,
    duplicate_candidate_rank
FROM ranked_assets;

-- -----------------------------------------------------------------------------
-- Asset-family batch parsing
-- Only parse rows whose files are confirmed present by family allowlists.
-- -----------------------------------------------------------------------------

TRUNCATE TABLE PATIENT360.DOCUMENTS.DOCUMENT_EXTRACTED_TEXT_TABLE;

-- Clinical note PDFs
INSERT INTO PATIENT360.DOCUMENTS.DOCUMENT_EXTRACTED_TEXT_TABLE (
    extraction_record_id, ingestion_asset_id, extraction_mode, extraction_outcome_status,
    extracted_text_body, extracted_text_length, extraction_detail, parsed_page_count,
    canonical_stage_path, original_file_name, patient_id, visit_id, report_id,
    document_category, source_event_date
)
WITH candidate_assets AS (
    SELECT *
    FROM PATIENT360.DOCUMENTS.DOCUMENT_ASSET_INVENTORY
    WHERE asset_family = 'CLINICAL_NOTE_PDF'
      AND processing_status IN ('READY_FOR_EXTRACTION', 'DUPLICATE_SUSPECT')
      AND original_file_name IN (
          'CN000001_Discharge_Summary.pdf',
          'CN000002_Emergency_Visit.pdf',
          'CN000003_Progress_Note.pdf',
          'CN000004_Initial_Consultation.pdf',
          'CN000005_Discharge_Summary.pdf'
      )
),
parsed_docs AS (
    SELECT
        ingestion_asset_id,
        canonical_stage_path,
        original_file_name,
        patient_id,
        visit_id,
        report_id,
        document_category,
        source_event_date,
        AI_PARSE_DOCUMENT(TO_FILE(canonical_stage_path), OBJECT_CONSTRUCT('mode', 'LAYOUT', 'page_split', TRUE), TRUE) AS parse_result
    FROM candidate_assets
),
parsed_pages AS (
    SELECT
        ingestion_asset_id,
        canonical_stage_path,
        original_file_name,
        patient_id,
        visit_id,
        report_id,
        document_category,
        source_event_date,
        parse_result:error::STRING AS parse_error,
        parse_result:metadata:pageCount::INTEGER AS parsed_page_count,
        COALESCE(
            LISTAGG(page.value:content::STRING, '\n\n') WITHIN GROUP (ORDER BY page.value:index::INTEGER),
            parse_result:value:content::STRING,
            parse_result:content::STRING
        ) AS extracted_text_body
    FROM parsed_docs,
    LATERAL FLATTEN(input => parse_result:pages, outer => TRUE) page
    GROUP BY ingestion_asset_id, canonical_stage_path, original_file_name, patient_id, visit_id, report_id,
             document_category, source_event_date, parse_result:error, parse_result:metadata:pageCount,
             parse_result:value:content, parse_result:content
)
SELECT
    ingestion_asset_id || ':EXTRACT' AS extraction_record_id,
    ingestion_asset_id,
    'PDF_LAYOUT' AS extraction_mode,
    CASE
        WHEN parse_error IS NOT NULL THEN 'FAILED_EXTRACTION'
        WHEN extracted_text_body IS NOT NULL AND LENGTH(TRIM(extracted_text_body)) > 0 THEN 'SEARCHABLE_TEXT_READY'
        ELSE 'FAILED_EXTRACTION'
    END AS extraction_outcome_status,
    extracted_text_body,
    LENGTH(COALESCE(extracted_text_body, '')) AS extracted_text_length,
    COALESCE(parse_error, IFF(extracted_text_body IS NULL, 'No trustworthy text extracted', NULL)) AS extraction_detail,
    parsed_page_count,
    canonical_stage_path,
    original_file_name,
    patient_id,
    visit_id,
    report_id,
    document_category,
    source_event_date
FROM parsed_pages;

-- Lab PDFs
INSERT INTO PATIENT360.DOCUMENTS.DOCUMENT_EXTRACTED_TEXT_TABLE (
    extraction_record_id, ingestion_asset_id, extraction_mode, extraction_outcome_status,
    extracted_text_body, extracted_text_length, extraction_detail, parsed_page_count,
    canonical_stage_path, original_file_name, patient_id, visit_id, report_id,
    document_category, source_event_date
)
WITH candidate_assets AS (
    SELECT *
    FROM PATIENT360.DOCUMENTS.DOCUMENT_ASSET_INVENTORY
    WHERE asset_family = 'LAB_RESULT_PDF'
      AND processing_status IN ('READY_FOR_EXTRACTION', 'DUPLICATE_SUSPECT')
      AND original_file_name IN (
          'LR000001_CBC.pdf',
          'LR000003_CMP.pdf',
          'LR000004_Lipid_Panel.pdf',
          'LR000005_Glucose.pdf'
      )
),
parsed_docs AS (
    SELECT
        ingestion_asset_id,
        canonical_stage_path,
        original_file_name,
        patient_id,
        visit_id,
        report_id,
        document_category,
        source_event_date,
        AI_PARSE_DOCUMENT(TO_FILE(canonical_stage_path), OBJECT_CONSTRUCT('mode', 'LAYOUT', 'page_split', TRUE), TRUE) AS parse_result
    FROM candidate_assets
),
parsed_pages AS (
    SELECT
        ingestion_asset_id,
        canonical_stage_path,
        original_file_name,
        patient_id,
        visit_id,
        report_id,
        document_category,
        source_event_date,
        parse_result:error::STRING AS parse_error,
        parse_result:metadata:pageCount::INTEGER AS parsed_page_count,
        COALESCE(
            LISTAGG(page.value:content::STRING, '\n\n') WITHIN GROUP (ORDER BY page.value:index::INTEGER),
            parse_result:value:content::STRING,
            parse_result:content::STRING
        ) AS extracted_text_body
    FROM parsed_docs,
    LATERAL FLATTEN(input => parse_result:pages, outer => TRUE) page
    GROUP BY ingestion_asset_id, canonical_stage_path, original_file_name, patient_id, visit_id, report_id,
             document_category, source_event_date, parse_result:error, parse_result:metadata:pageCount,
             parse_result:value:content, parse_result:content
)
SELECT
    ingestion_asset_id || ':EXTRACT' AS extraction_record_id,
    ingestion_asset_id,
    'PDF_LAYOUT' AS extraction_mode,
    CASE
        WHEN parse_error IS NOT NULL THEN 'FAILED_EXTRACTION'
        WHEN extracted_text_body IS NOT NULL AND LENGTH(TRIM(extracted_text_body)) > 0 THEN 'SEARCHABLE_TEXT_READY'
        ELSE 'FAILED_EXTRACTION'
    END AS extraction_outcome_status,
    extracted_text_body,
    LENGTH(COALESCE(extracted_text_body, '')) AS extracted_text_length,
    COALESCE(parse_error, IFF(extracted_text_body IS NULL, 'No trustworthy text extracted', NULL)) AS extraction_detail,
    parsed_page_count,
    canonical_stage_path,
    original_file_name,
    patient_id,
    visit_id,
    report_id,
    document_category,
    source_event_date
FROM parsed_pages;

-- Prescription PDFs
INSERT INTO PATIENT360.DOCUMENTS.DOCUMENT_EXTRACTED_TEXT_TABLE (
    extraction_record_id, ingestion_asset_id, extraction_mode, extraction_outcome_status,
    extracted_text_body, extracted_text_length, extraction_detail, parsed_page_count,
    canonical_stage_path, original_file_name, patient_id, visit_id, report_id,
    document_category, source_event_date
)
WITH candidate_assets AS (
    SELECT *
    FROM PATIENT360.DOCUMENTS.DOCUMENT_ASSET_INVENTORY
    WHERE asset_family = 'PRESCRIPTION_PDF'
      AND processing_status IN ('READY_FOR_EXTRACTION', 'DUPLICATE_SUSPECT')
      AND original_file_name IN (
          'RX000001_Lisinopril.pdf',
          'RX000002_Metformin.pdf',
          'RX000003_Atorvastatin.pdf',
          'RX000004_Amoxicillin.pdf'
      )
),
parsed_docs AS (
    SELECT
        ingestion_asset_id,
        canonical_stage_path,
        original_file_name,
        patient_id,
        visit_id,
        report_id,
        document_category,
        source_event_date,
        AI_PARSE_DOCUMENT(TO_FILE(canonical_stage_path), OBJECT_CONSTRUCT('mode', 'LAYOUT', 'page_split', TRUE), TRUE) AS parse_result
    FROM candidate_assets
),
parsed_pages AS (
    SELECT
        ingestion_asset_id,
        canonical_stage_path,
        original_file_name,
        patient_id,
        visit_id,
        report_id,
        document_category,
        source_event_date,
        parse_result:error::STRING AS parse_error,
        parse_result:metadata:pageCount::INTEGER AS parsed_page_count,
        COALESCE(
            LISTAGG(page.value:content::STRING, '\n\n') WITHIN GROUP (ORDER BY page.value:index::INTEGER),
            parse_result:value:content::STRING,
            parse_result:content::STRING
        ) AS extracted_text_body
    FROM parsed_docs,
    LATERAL FLATTEN(input => parse_result:pages, outer => TRUE) page
    GROUP BY ingestion_asset_id, canonical_stage_path, original_file_name, patient_id, visit_id, report_id,
             document_category, source_event_date, parse_result:error, parse_result:metadata:pageCount,
             parse_result:value:content, parse_result:content
)
SELECT
    ingestion_asset_id || ':EXTRACT' AS extraction_record_id,
    ingestion_asset_id,
    'PDF_LAYOUT' AS extraction_mode,
    CASE
        WHEN parse_error IS NOT NULL THEN 'FAILED_EXTRACTION'
        WHEN extracted_text_body IS NOT NULL AND LENGTH(TRIM(extracted_text_body)) > 0 THEN 'SEARCHABLE_TEXT_READY'
        ELSE 'FAILED_EXTRACTION'
    END AS extraction_outcome_status,
    extracted_text_body,
    LENGTH(COALESCE(extracted_text_body, '')) AS extracted_text_length,
    COALESCE(parse_error, IFF(extracted_text_body IS NULL, 'No trustworthy text extracted', NULL)) AS extraction_detail,
    parsed_page_count,
    canonical_stage_path,
    original_file_name,
    patient_id,
    visit_id,
    report_id,
    document_category,
    source_event_date
FROM parsed_pages;

-- Diagnostic images
INSERT INTO PATIENT360.DOCUMENTS.DOCUMENT_EXTRACTED_TEXT_TABLE (
    extraction_record_id, ingestion_asset_id, extraction_mode, extraction_outcome_status,
    extracted_text_body, extracted_text_length, extraction_detail, parsed_page_count,
    canonical_stage_path, original_file_name, patient_id, visit_id, report_id,
    document_category, source_event_date
)
WITH candidate_assets AS (
    SELECT *
    FROM PATIENT360.DOCUMENTS.DOCUMENT_ASSET_INVENTORY
    WHERE asset_family = 'DIAGNOSTIC_IMAGE'
      AND processing_status IN ('READY_FOR_EXTRACTION', 'DUPLICATE_SUSPECT')
      AND original_file_name IN (
          'IMG000001_Chest_Xray.png',
          'IMG000002_Knee_MRI.jpg',
          'IMG000003_Abdominal_CT.png'
      )
),
parsed_docs AS (
    SELECT
        ingestion_asset_id,
        canonical_stage_path,
        original_file_name,
        patient_id,
        visit_id,
        report_id,
        document_category,
        source_event_date,
        AI_PARSE_DOCUMENT(TO_FILE(canonical_stage_path), OBJECT_CONSTRUCT('mode', 'OCR'), TRUE) AS parse_result
    FROM candidate_assets
),
parsed_pages AS (
    SELECT
        ingestion_asset_id,
        canonical_stage_path,
        original_file_name,
        patient_id,
        visit_id,
        report_id,
        document_category,
        source_event_date,
        parse_result:error::STRING AS parse_error,
        parse_result:metadata:pageCount::INTEGER AS parsed_page_count,
        COALESCE(
            LISTAGG(page.value:content::STRING, '\n\n') WITHIN GROUP (ORDER BY page.value:index::INTEGER),
            parse_result:value:content::STRING,
            parse_result:content::STRING
        ) AS extracted_text_body
    FROM parsed_docs,
    LATERAL FLATTEN(input => parse_result:pages, outer => TRUE) page
    GROUP BY ingestion_asset_id, canonical_stage_path, original_file_name, patient_id, visit_id, report_id,
             document_category, source_event_date, parse_result:error, parse_result:metadata:pageCount,
             parse_result:value:content, parse_result:content
)
SELECT
    ingestion_asset_id || ':EXTRACT' AS extraction_record_id,
    ingestion_asset_id,
    'IMAGE_OCR' AS extraction_mode,
    CASE
        WHEN parse_error IS NOT NULL THEN 'FAILED_EXTRACTION'
        WHEN extracted_text_body IS NOT NULL AND LENGTH(TRIM(extracted_text_body)) > 0 THEN 'SEARCHABLE_TEXT_READY'
        ELSE 'METADATA_ONLY'
    END AS extraction_outcome_status,
    extracted_text_body,
    LENGTH(COALESCE(extracted_text_body, '')) AS extracted_text_length,
    COALESCE(parse_error, IFF(extracted_text_body IS NULL, 'No trustworthy text extracted from image OCR', NULL)) AS extraction_detail,
    parsed_page_count,
    canonical_stage_path,
    original_file_name,
    patient_id,
    visit_id,
    report_id,
    document_category,
    source_event_date
FROM parsed_pages;

-- Add explicit rows for non-parsed / unmatched / unsupported assets
INSERT INTO PATIENT360.DOCUMENTS.DOCUMENT_EXTRACTED_TEXT_TABLE (
    extraction_record_id, ingestion_asset_id, extraction_mode, extraction_outcome_status,
    extracted_text_body, extracted_text_length, extraction_detail, parsed_page_count,
    canonical_stage_path, original_file_name, patient_id, visit_id, report_id,
    document_category, source_event_date
)
SELECT
    ingestion_asset_id || ':EXTRACT' AS extraction_record_id,
    ingestion_asset_id,
    extraction_method AS extraction_mode,
    CASE
        WHEN processing_status = 'UNMATCHED' THEN 'METADATA_ONLY'
        WHEN processing_status = 'UNPARSEABLE' THEN 'FAILED_EXTRACTION'
        ELSE 'FAILED_EXTRACTION'
    END AS extraction_outcome_status,
    NULL AS extracted_text_body,
    0 AS extracted_text_length,
    CASE
        WHEN processing_status = 'UNMATCHED' THEN 'Asset remains metadata-only because no confident patient/report assignment was derived'
        WHEN processing_status = 'UNPARSEABLE' THEN 'Asset file extension is unsupported for the configured parsing flow'
        WHEN processing_status = 'DUPLICATE_SUSPECT' THEN 'Duplicate-suspect asset was not included in the confirmed-present allowlist'
        ELSE 'Asset was not included in the confirmed-present family batches'
    END AS extraction_detail,
    NULL AS parsed_page_count,
    canonical_stage_path,
    original_file_name,
    patient_id,
    visit_id,
    report_id,
    document_category,
    source_event_date
FROM PATIENT360.DOCUMENTS.DOCUMENT_ASSET_INVENTORY inventory
WHERE NOT EXISTS (
    SELECT 1
    FROM PATIENT360.DOCUMENTS.DOCUMENT_EXTRACTED_TEXT_TABLE extracted
    WHERE extracted.ingestion_asset_id = inventory.ingestion_asset_id
);

-- -----------------------------------------------------------------------------
-- Build deterministic chunk table from materialized extracted text
-- -----------------------------------------------------------------------------

TRUNCATE TABLE PATIENT360.DOCUMENTS.DOCUMENT_SEARCH_CHUNKS_TABLE;

INSERT INTO PATIENT360.DOCUMENTS.DOCUMENT_SEARCH_CHUNKS_TABLE (
    chunk_id, ingestion_asset_id, extraction_record_id, chunk_order, chunk_text,
    patient_id, visit_id, report_id, document_category, source_event_date,
    canonical_stage_path, original_file_name, chunk_eligibility_status,
    target_chunk_size, target_chunk_overlap
)
WITH chunk_arrays AS (
    SELECT
        extraction_record_id,
        ingestion_asset_id,
        patient_id,
        visit_id,
        report_id,
        document_category,
        source_event_date,
        canonical_stage_path,
        original_file_name,
        SNOWFLAKE.CORTEX.SPLIT_TEXT_RECURSIVE_CHARACTER(
            extracted_text_body,
            'markdown',
            800,
            100
        ) AS chunk_array
    FROM PATIENT360.DOCUMENTS.DOCUMENT_EXTRACTED_TEXT_TABLE
    WHERE extraction_outcome_status = 'SEARCHABLE_TEXT_READY'
      AND extracted_text_body IS NOT NULL
)
SELECT
    extraction_record_id || ':CHUNK:' || (chunk.index + 1) AS chunk_id,
    ingestion_asset_id,
    extraction_record_id,
    chunk.index + 1 AS chunk_order,
    chunk.value::STRING AS chunk_text,
    patient_id,
    visit_id,
    report_id,
    document_category,
    source_event_date,
    canonical_stage_path,
    original_file_name,
    'INDEX_READY' AS chunk_eligibility_status,
    800 AS target_chunk_size,
    100 AS target_chunk_overlap
FROM chunk_arrays,
LATERAL FLATTEN(input => chunk_array) chunk;

-- -----------------------------------------------------------------------------
-- Build deterministic quality findings table
-- -----------------------------------------------------------------------------

TRUNCATE TABLE PATIENT360.DOCUMENTS.DOCUMENT_INGESTION_QUALITY_FINDINGS_TABLE;

INSERT INTO PATIENT360.DOCUMENTS.DOCUMENT_INGESTION_QUALITY_FINDINGS_TABLE (
    quality_finding_id,
    ingestion_asset_id,
    issue_grouping_key,
    issue_category,
    review_priority,
    issue_description,
    remediation_hint,
    first_detected_timestamp,
    review_status
)
WITH inventory_findings AS (
    SELECT
        ingestion_asset_id || ':QUALITY:' || processing_status AS quality_finding_id,
        ingestion_asset_id,
        source_stage_name || ':' || COALESCE(original_file_name, '<missing-file-name>') AS issue_grouping_key,
        CASE
            WHEN processing_status = 'DUPLICATE_SUSPECT' THEN 'DUPLICATE_ASSET'
            WHEN processing_status = 'UNMATCHED' THEN 'UNMATCHED_ASSET'
            WHEN processing_status = 'UNPARSEABLE' THEN 'UNPARSEABLE_ASSET'
            ELSE NULL
        END AS issue_category,
        CASE
            WHEN processing_status IN ('UNMATCHED', 'UNPARSEABLE') THEN 'HIGH'
            WHEN processing_status = 'DUPLICATE_SUSPECT' THEN 'MEDIUM'
            ELSE NULL
        END AS review_priority,
        CASE
            WHEN processing_status = 'DUPLICATE_SUSPECT' THEN 'More than one asset row shares the same source stage and original file name'
            WHEN processing_status = 'UNMATCHED' THEN 'Asset could not be assigned confidently to patient/report context'
            WHEN processing_status = 'UNPARSEABLE' THEN 'Asset uses an unsupported extension or parse was skipped because the file was not confirmed present'
            ELSE NULL
        END AS issue_description,
        CASE
            WHEN processing_status = 'DUPLICATE_SUSPECT' THEN 'Review duplicate business identity and keep one canonical asset path'
            WHEN processing_status = 'UNMATCHED' THEN 'Review filename and raw metadata to recover patient/report linkage'
            WHEN processing_status = 'UNPARSEABLE' THEN 'Review file format support or verify the staged file exists before re-running extraction'
            ELSE NULL
        END AS remediation_hint,
        CURRENT_TIMESTAMP() AS first_detected_timestamp,
        'OPEN' AS review_status
    FROM PATIENT360.DOCUMENTS.DOCUMENT_ASSET_INVENTORY
),
extraction_findings AS (
    SELECT
        extraction_record_id || ':QUALITY:FAILED_EXTRACTION' AS quality_finding_id,
        ingestion_asset_id,
        canonical_stage_path AS issue_grouping_key,
        'UNPARSEABLE_ASSET' AS issue_category,
        'HIGH' AS review_priority,
        extraction_detail AS issue_description,
        'Inspect AI_PARSE_DOCUMENT output or source file quality before re-running the batch' AS remediation_hint,
        CURRENT_TIMESTAMP() AS first_detected_timestamp,
        'OPEN' AS review_status
    FROM PATIENT360.DOCUMENTS.DOCUMENT_EXTRACTED_TEXT_TABLE
    WHERE extraction_outcome_status = 'FAILED_EXTRACTION'
),
missing_file_candidates AS (
    SELECT
        asset_family || ':QUALITY:MISSING_FILE:' || source_record_id AS quality_finding_id,
        asset_family || ':' || source_record_id AS ingestion_asset_id,
        source_stage_name || ':<missing-file-name>' AS issue_grouping_key,
        'MISSING_FILE' AS issue_category,
        'HIGH' AS review_priority,
        'Raw metadata row lacks a usable staged file name for the expected source stage' AS issue_description,
        'Populate or correct the staged file name in the raw metadata source' AS remediation_hint,
        CURRENT_TIMESTAMP() AS first_detected_timestamp,
        'OPEN' AS review_status
    FROM (
        SELECT 'CLINICAL_NOTE_PDF' AS asset_family, note_id AS source_record_id, 'PATIENT360.RAW.CLINICAL_NOTE_PDFS' AS source_stage_name
        FROM PATIENT360.RAW.CLINICAL_NOTES
        WHERE COALESCE(pdf_filename, '') = ''
        UNION ALL
        SELECT 'LAB_RESULT_PDF', lab_result_id, 'PATIENT360.RAW.LAB_RESULT_PDFS'
        FROM PATIENT360.RAW.LAB_RESULTS
        WHERE COALESCE(pdf_filename, '') = ''
        UNION ALL
        SELECT 'PRESCRIPTION_PDF', prescription_id, 'PATIENT360.RAW.PRESCRIPTION_PDFS'
        FROM PATIENT360.RAW.PRESCRIPTIONS
        WHERE COALESCE(pdf_filename, '') = ''
        UNION ALL
        SELECT 'DIAGNOSTIC_IMAGE', report_id, 'PATIENT360.RAW.DIAGNOSTIC_IMAGES'
        FROM PATIENT360.RAW.DIAGNOSTIC_REPORTS
        WHERE COALESCE(image_filename, '') = ''
    ) missing_assets
)
SELECT * FROM inventory_findings WHERE issue_category IS NOT NULL
UNION ALL
SELECT * FROM extraction_findings
UNION ALL
SELECT * FROM missing_file_candidates;

-- -----------------------------------------------------------------------------
-- Deterministic views on top of tables for stable downstream consumption
-- -----------------------------------------------------------------------------

CREATE OR REPLACE VIEW PATIENT360.DOCUMENTS.DOCUMENT_ASSET_MATCH_CONTEXT AS
SELECT
    ingestion_asset_id,
    patient_id,
    visit_id,
    report_id,
    source_record_type,
    matching_basis_summary,
    match_confidence,
    match_status AS decision_status,
    IFF(match_status = 'UNMATCHED', 'No confident patient/report assignment was derived', NULL) AS unmatched_reason
FROM PATIENT360.DOCUMENTS.DOCUMENT_ASSET_INVENTORY;

CREATE OR REPLACE VIEW PATIENT360.DOCUMENTS.DOCUMENT_EXTRACTED_TEXT AS
SELECT * FROM PATIENT360.DOCUMENTS.DOCUMENT_EXTRACTED_TEXT_TABLE;

CREATE OR REPLACE VIEW PATIENT360.DOCUMENTS.DOCUMENT_SEARCH_CHUNKS AS
SELECT * FROM PATIENT360.DOCUMENTS.DOCUMENT_SEARCH_CHUNKS_TABLE;

CREATE OR REPLACE VIEW PATIENT360.DOCUMENTS.DOCUMENT_INGESTION_QUALITY_FINDINGS AS
SELECT * FROM PATIENT360.DOCUMENTS.DOCUMENT_INGESTION_QUALITY_FINDINGS_TABLE;

-- -----------------------------------------------------------------------------
-- Deterministic Cortex Search service on chunk table
-- -----------------------------------------------------------------------------

CREATE OR REPLACE CORTEX SEARCH SERVICE PATIENT360.DOCUMENTS.DOCUMENT_SEARCH_SERVICE
ON chunk_text
ATTRIBUTES patient_id, visit_id, report_id, document_category, source_event_date, canonical_stage_path, original_file_name, ingestion_asset_id
WAREHOUSE = CARE360_WH
TARGET_LAG = '1 hour'
EMBEDDING_MODEL = 'snowflake-arctic-embed-l-v2.0'
AS (
    SELECT
        chunk_id,
        chunk_text,
        patient_id,
        visit_id,
        report_id,
        document_category,
        source_event_date,
        canonical_stage_path,
        original_file_name,
        ingestion_asset_id
    FROM PATIENT360.DOCUMENTS.DOCUMENT_SEARCH_CHUNKS_TABLE
);

-- -----------------------------------------------------------------------------
-- Validation notes
-- -----------------------------------------------------------------------------
-- 1. This pipeline is deterministic at the chunk/search layer because AI parsing is
--    materialized into tables before chunking and search indexing.
-- 2. Asset-family extraction is intentionally batched through confirmed-present allowlists
--    to avoid all-or-nothing failures from missing stage files.
-- 3. Remaining assets are preserved with explicit extraction outcomes and quality findings.