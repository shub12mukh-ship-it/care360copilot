-- ============================================================================
-- PATIENT360 DATA LOAD VERIFICATION SCRIPT
-- ============================================================================
-- Run this script after completing all three data load steps to verify
-- that all data has been loaded correctly.
-- ============================================================================

USE DATABASE PATIENT360;
USE SCHEMA RAW;

-- ============================================================================
-- PART 1: Verify CSV Data Loads (Table Row Counts)
-- ============================================================================

SELECT 'CSV Data Verification' AS verification_section;

SELECT 
    'DOCTORS' AS table_name,
    COUNT(*) AS actual_count,
    50 AS expected_count,
    CASE WHEN COUNT(*) = 50 THEN '✓ PASS' ELSE '✗ FAIL' END AS status
FROM DOCTORS

UNION ALL

SELECT 
    'DIAGNOSTIC_CENTERS' AS table_name,
    COUNT(*) AS actual_count,
    10 AS expected_count,
    CASE WHEN COUNT(*) = 10 THEN '✓ PASS' ELSE '✗ FAIL' END AS status
FROM DIAGNOSTIC_CENTERS

UNION ALL

SELECT 
    'PATIENTS' AS table_name,
    COUNT(*) AS actual_count,
    100 AS expected_count,
    CASE WHEN COUNT(*) = 100 THEN '✓ PASS' ELSE '✗ FAIL' END AS status
FROM PATIENTS

UNION ALL

SELECT 
    'VISITS' AS table_name,
    COUNT(*) AS actual_count,
    150 AS expected_count,
    CASE WHEN COUNT(*) = 150 THEN '✓ PASS' ELSE '✗ FAIL' END AS status
FROM VISITS

UNION ALL

SELECT 
    'LAB_RESULTS' AS table_name,
    COUNT(*) AS actual_count,
    150 AS expected_count,
    CASE WHEN COUNT(*) = 150 THEN '✓ PASS' ELSE '✗ FAIL' END AS status
FROM LAB_RESULTS

UNION ALL

SELECT 
    'DIAGNOSTIC_REPORTS' AS table_name,
    COUNT(*) AS actual_count,
    150 AS expected_count,
    CASE WHEN COUNT(*) = 150 THEN '✓ PASS' ELSE '✗ FAIL' END AS status
FROM DIAGNOSTIC_REPORTS

UNION ALL

SELECT 
    'INSURANCE_CLAIMS' AS table_name,
    COUNT(*) AS actual_count,
    150 AS expected_count,
    CASE WHEN COUNT(*) = 150 THEN '✓ PASS' ELSE '✗ FAIL' END AS status
FROM INSURANCE_CLAIMS

UNION ALL

SELECT 
    'PRESCRIPTIONS' AS table_name,
    COUNT(*) AS actual_count,
    150 AS expected_count,
    CASE WHEN COUNT(*) = 150 THEN '✓ PASS' ELSE '✗ FAIL' END AS status
FROM PRESCRIPTIONS

UNION ALL

SELECT 
    'CLINICAL_NOTES' AS table_name,
    COUNT(*) AS actual_count,
    150 AS expected_count,
    CASE WHEN COUNT(*) = 150 THEN '✓ PASS' ELSE '✗ FAIL' END AS status
FROM CLINICAL_NOTES

UNION ALL

SELECT 
    'TOTAL' AS table_name,
    (SELECT COUNT(*) FROM DOCTORS) +
    (SELECT COUNT(*) FROM DIAGNOSTIC_CENTERS) +
    (SELECT COUNT(*) FROM PATIENTS) +
    (SELECT COUNT(*) FROM VISITS) +
    (SELECT COUNT(*) FROM LAB_RESULTS) +
    (SELECT COUNT(*) FROM DIAGNOSTIC_REPORTS) +
    (SELECT COUNT(*) FROM INSURANCE_CLAIMS) +
    (SELECT COUNT(*) FROM PRESCRIPTIONS) +
    (SELECT COUNT(*) FROM CLINICAL_NOTES) AS actual_count,
    1060 AS expected_count,
    CASE WHEN (
        (SELECT COUNT(*) FROM DOCTORS) +
        (SELECT COUNT(*) FROM DIAGNOSTIC_CENTERS) +
        (SELECT COUNT(*) FROM PATIENTS) +
        (SELECT COUNT(*) FROM VISITS) +
        (SELECT COUNT(*) FROM LAB_RESULTS) +
        (SELECT COUNT(*) FROM DIAGNOSTIC_REPORTS) +
        (SELECT COUNT(*) FROM INSURANCE_CLAIMS) +
        (SELECT COUNT(*) FROM PRESCRIPTIONS) +
        (SELECT COUNT(*) FROM CLINICAL_NOTES)
    ) = 1060 THEN '✓ PASS' ELSE '✗ FAIL' END AS status;

-- ============================================================================
-- PART 2: Verify File Uploads (Stage File Counts)
-- ============================================================================

SELECT 'File Upload Verification' AS verification_section;

-- Note: This query counts files in each stage
-- Expected counts: 150 images, 450 PDFs (150 per category)

SELECT 
    'DIAGNOSTIC_IMAGES' AS stage_name,
    COUNT(*) AS file_count,
    150 AS expected_count,
    CASE WHEN COUNT(*) = 150 THEN '✓ PASS' ELSE '✗ FAIL' END AS status
FROM DIRECTORY(@DIAGNOSTIC_IMAGES)

UNION ALL

SELECT 
    'LAB_RESULT_PDFS' AS stage_name,
    COUNT(*) AS file_count,
    150 AS expected_count,
    CASE WHEN COUNT(*) = 150 THEN '✓ PASS' ELSE '✗ FAIL' END AS status
FROM DIRECTORY(@LAB_RESULT_PDFS)

UNION ALL

SELECT 
    'PRESCRIPTION_PDFS' AS stage_name,
    COUNT(*) AS file_count,
    150 AS expected_count,
    CASE WHEN COUNT(*) = 150 THEN '✓ PASS' ELSE '✗ FAIL' END AS status
FROM DIRECTORY(@PRESCRIPTION_PDFS)

UNION ALL

SELECT 
    'CLINICAL_NOTE_PDFS' AS stage_name,
    COUNT(*) AS file_count,
    150 AS expected_count,
    CASE WHEN COUNT(*) = 150 THEN '✓ PASS' ELSE '✗ FAIL' END AS status
FROM DIRECTORY(@CLINICAL_NOTE_PDFS)

UNION ALL

SELECT 
    'TOTAL FILES' AS stage_name,
    (SELECT COUNT(*) FROM DIRECTORY(@DIAGNOSTIC_IMAGES)) +
    (SELECT COUNT(*) FROM DIRECTORY(@LAB_RESULT_PDFS)) +
    (SELECT COUNT(*) FROM DIRECTORY(@PRESCRIPTION_PDFS)) +
    (SELECT COUNT(*) FROM DIRECTORY(@CLINICAL_NOTE_PDFS)) AS file_count,
    600 AS expected_count,
    CASE WHEN (
        (SELECT COUNT(*) FROM DIRECTORY(@DIAGNOSTIC_IMAGES)) +
        (SELECT COUNT(*) FROM DIRECTORY(@LAB_RESULT_PDFS)) +
        (SELECT COUNT(*) FROM DIRECTORY(@PRESCRIPTION_PDFS)) +
        (SELECT COUNT(*) FROM DIRECTORY(@CLINICAL_NOTE_PDFS))
    ) = 600 THEN '✓ PASS' ELSE '✗ FAIL' END AS status;

-- ============================================================================
-- PART 3: Sample Data Preview
-- ============================================================================

SELECT 'Sample Data Preview - Doctors' AS section;
SELECT * FROM DOCTORS LIMIT 5;

SELECT 'Sample Data Preview - Patients' AS section;
SELECT * FROM PATIENTS LIMIT 5;

SELECT 'Sample Data Preview - Visits' AS section;
SELECT * FROM VISITS LIMIT 5;

SELECT 'Sample Data Preview - Lab Results' AS section;
SELECT * FROM LAB_RESULTS LIMIT 5;

-- ============================================================================
-- PART 4: Data Integrity Checks
-- ============================================================================

SELECT 'Data Integrity Checks' AS section;

-- Check for NULL primary keys
SELECT 
    'Doctors with NULL DOCTOR_ID' AS check_name,
    COUNT(*) AS count,
    CASE WHEN COUNT(*) = 0 THEN '✓ PASS' ELSE '✗ FAIL' END AS status
FROM DOCTORS 
WHERE DOCTOR_ID IS NULL

UNION ALL

SELECT 
    'Patients with NULL PATIENT_ID' AS check_name,
    COUNT(*) AS count,
    CASE WHEN COUNT(*) = 0 THEN '✓ PASS' ELSE '✗ FAIL' END AS status
FROM PATIENTS 
WHERE PATIENT_ID IS NULL

UNION ALL

-- Check foreign key relationships
SELECT 
    'Visits with invalid PATIENT_ID' AS check_name,
    COUNT(*) AS count,
    CASE WHEN COUNT(*) = 0 THEN '✓ PASS' ELSE '✗ FAIL' END AS status
FROM VISITS v
LEFT JOIN PATIENTS p ON v.PATIENT_ID = p.PATIENT_ID
WHERE p.PATIENT_ID IS NULL

UNION ALL

SELECT 
    'Visits with invalid DOCTOR_ID' AS check_name,
    COUNT(*) AS count,
    CASE WHEN COUNT(*) = 0 THEN '✓ PASS' ELSE '✗ FAIL' END AS status
FROM VISITS v
LEFT JOIN DOCTORS d ON v.DOCTOR_ID = d.DOCTOR_ID
WHERE d.DOCTOR_ID IS NULL;

-- ============================================================================
-- PART 5: Summary Report
-- ============================================================================

SELECT '==================== VERIFICATION SUMMARY ====================' AS summary;

SELECT 
    'Total Tables' AS metric,
    9 AS value
UNION ALL
SELECT 
    'Total Records Loaded' AS metric,
    (SELECT COUNT(*) FROM DOCTORS) +
    (SELECT COUNT(*) FROM DIAGNOSTIC_CENTERS) +
    (SELECT COUNT(*) FROM PATIENTS) +
    (SELECT COUNT(*) FROM VISITS) +
    (SELECT COUNT(*) FROM LAB_RESULTS) +
    (SELECT COUNT(*) FROM DIAGNOSTIC_REPORTS) +
    (SELECT COUNT(*) FROM INSURANCE_CLAIMS) +
    (SELECT COUNT(*) FROM PRESCRIPTIONS) +
    (SELECT COUNT(*) FROM CLINICAL_NOTES) AS value
UNION ALL
SELECT 
    'Total Stages' AS metric,
    4 AS value
UNION ALL
SELECT 
    'Total Files Uploaded' AS metric,
    (SELECT COUNT(*) FROM DIRECTORY(@DIAGNOSTIC_IMAGES)) +
    (SELECT COUNT(*) FROM DIRECTORY(@LAB_RESULT_PDFS)) +
    (SELECT COUNT(*) FROM DIRECTORY(@PRESCRIPTION_PDFS)) +
    (SELECT COUNT(*) FROM DIRECTORY(@CLINICAL_NOTE_PDFS)) AS value;

-- ============================================================================
