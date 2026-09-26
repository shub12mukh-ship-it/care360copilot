# Implementation Plan: Patient360 Database Setup and Data Population

## Context

### Current State
- **Existing synthetic healthcare dataset** located in `synthetic-healthcare-data/` directory:
  - **CSV files (9)**: doctors.csv, diagnostic_centers.csv, patients.csv, visits.csv, lab_results.csv, diagnostic_reports.csv, insurance_claims.csv, prescriptions.csv, clinical_notes.csv
  - **PDF files (1,694)**: Split across three subdirectories:
    - `pdfs/lab_results/`: Lab result reports (e.g., LR000001_CBC.pdf)
    - `pdfs/prescriptions/`: Prescription documents (e.g., RX000001_Prescription.pdf)
    - `pdfs/clinical_notes/`: Clinical documentation (e.g., CN000001_Clinical_Note.pdf)
  - **Image files (178)**: Diagnostic imaging in `images/` (e.g., DR000001_Angiogram_Heart.png)

- **Dataset characteristics**:
  - 100 patients (P00001-P00100)
  - 50 doctors (D00001-D00050)
  - 10 diagnostic centers (DC001-DC010)
  - 572 visits across patients
  - Production-quality synthetic data with proper referential integrity

### Objective
Create a **new Snowflake database named PATIENT360** with four schemas (RAW, CURATED, ANALYTICS, DOCUMENTS) and populate the RAW schema tables with all structured CSV data, plus store unstructured PDFs and images with proper metadata tracking in the DOCUMENTS schema.

### Key Requirements
1. **New database**: PATIENT360 (separate from existing CARE360_DB)
2. **Four schemas**: RAW (structured tables), CURATED (future transformations), ANALYTICS (future analytics), DOCUMENTS (unstructured data)
3. **Complete data load**: All CSVs, PDFs, and images must be loaded
4. **Referential integrity**: Maintain FK relationships during load (doctors/centers/patients → visits → dependent entities)
5. **File management**: Snowflake stages for CSV, PDF, and image file storage

### Snowflake Connection Context
- **Account**: JRMWQMS-PA19066
- **User**: sreejaprabakar
- **Current Role**: CARE360_RW_ROLE
- **Note**: Will need appropriate privileges (CREATE DATABASE, CREATE SCHEMA, CREATE TABLE, CREATE STAGE, CREATE FILE FORMAT) to execute this plan

---

## Implementation Steps

### Phase 1: Database and Schema Infrastructure

#### Task 1: Create Patient360 Database and Schemas

**SQL to execute**:
```sql
-- Create the new database
CREATE DATABASE IF NOT EXISTS PATIENT360
  COMMENT = 'Patient360 healthcare data repository';

-- Use the new database
USE DATABASE PATIENT360;

-- Create four schemas
CREATE SCHEMA IF NOT EXISTS RAW
  COMMENT = 'Raw data layer - unprocessed source data';

CREATE SCHEMA IF NOT EXISTS CURATED
  COMMENT = 'Curated data layer - cleaned and validated data';

CREATE SCHEMA IF NOT EXISTS ANALYTICS
  COMMENT = 'Analytics layer - aggregated and derived metrics';

CREATE SCHEMA IF NOT EXISTS DOCUMENTS
  COMMENT = 'Unstructured document storage - PDFs and images with metadata';
```

**Expected outcome**: Database PATIENT360 created with 4 schemas

---

#### Task 2: Create File Format and Staging Infrastructure

**SQL to execute**:
```sql
USE SCHEMA PATIENT360.RAW;

-- Create CSV file format
CREATE OR REPLACE FILE FORMAT CSV_FORMAT
  TYPE = 'CSV'
  FIELD_DELIMITER = ','
  SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  TRIM_SPACE = TRUE
  ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE
  EMPTY_FIELD_AS_NULL = TRUE
  NULL_IF = ('NULL', 'null', '')
  ESCAPE_UNENCLOSED_FIELD = NONE
  COMMENT = 'Standard CSV format for healthcare data';

-- Create internal stage for CSV files
CREATE OR REPLACE STAGE CSV_STAGE
  FILE_FORMAT = CSV_FORMAT
  COMMENT = 'Staging area for CSV healthcare data files';

-- Create stage for PDF documents
CREATE OR REPLACE STAGE PDF_STAGE
  DIRECTORY = (ENABLE = TRUE)
  COMMENT = 'Staging area for PDF clinical documents';

-- Create stage for diagnostic images
CREATE OR REPLACE STAGE IMAGE_STAGE
  DIRECTORY = (ENABLE = TRUE)
  COMMENT = 'Staging area for diagnostic imaging files';
```

**Expected outcome**: File format and 3 stages created for different file types

---

### Phase 2: RAW Schema Table Creation

#### Task 3: Create RAW Schema Tables for Structured Data

**Tables to create** (in dependency order):

**1. DOCTORS table**:
```sql
USE SCHEMA PATIENT360.RAW;

CREATE OR REPLACE TABLE DOCTORS (
  DOCTOR_ID VARCHAR(10) PRIMARY KEY,
  FIRST_NAME VARCHAR(100) NOT NULL,
  LAST_NAME VARCHAR(100) NOT NULL,
  SPECIALTY VARCHAR(100),
  SUB_SPECIALTY VARCHAR(100),
  YEARS_EXPERIENCE INTEGER,
  MEDICAL_SCHOOL VARCHAR(200),
  BOARD_CERTIFIED BOOLEAN,
  PHONE VARCHAR(50),
  EMAIL VARCHAR(100),
  LICENSE_NUMBER VARCHAR(50),
  LOADED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
) COMMENT = 'Doctor information and specializations';
```

**2. DIAGNOSTIC_CENTERS table**:
```sql
CREATE OR REPLACE TABLE DIAGNOSTIC_CENTERS (
  CENTER_ID VARCHAR(10) PRIMARY KEY,
  CENTER_NAME VARCHAR(200) NOT NULL,
  ADDRESS VARCHAR(200),
  CITY VARCHAR(100),
  STATE VARCHAR(2),
  ZIP_CODE VARCHAR(10),
  PHONE VARCHAR(50),
  SERVICES_OFFERED VARCHAR(500),
  ACCREDITATION VARCHAR(100),
  OPERATING_HOURS VARCHAR(100),
  LOADED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
) COMMENT = 'Diagnostic facility information';
```

**3. PATIENTS table**:
```sql
CREATE OR REPLACE TABLE PATIENTS (
  PATIENT_ID VARCHAR(10) PRIMARY KEY,
  FIRST_NAME VARCHAR(100) NOT NULL,
  LAST_NAME VARCHAR(100) NOT NULL,
  DATE_OF_BIRTH DATE NOT NULL,
  AGE INTEGER,
  GENDER VARCHAR(20),
  ETHNICITY VARCHAR(50),
  BLOOD_TYPE VARCHAR(5),
  ADDRESS VARCHAR(200),
  CITY VARCHAR(100),
  STATE VARCHAR(2),
  ZIP_CODE VARCHAR(10),
  PHONE VARCHAR(50),
  EMAIL VARCHAR(100),
  EMERGENCY_CONTACT_NAME VARCHAR(100),
  EMERGENCY_CONTACT_PHONE VARCHAR(50),
  INSURANCE_PROVIDER VARCHAR(100),
  INSURANCE_POLICY_NUMBER VARCHAR(50),
  LOADED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
) COMMENT = 'Patient demographic and contact information';
```

**4. VISITS table**:
```sql
CREATE OR REPLACE TABLE VISITS (
  VISIT_ID VARCHAR(10) PRIMARY KEY,
  PATIENT_ID VARCHAR(10) NOT NULL,
  DOCTOR_ID VARCHAR(10) NOT NULL,
  VISIT_DATE DATE NOT NULL,
  VISIT_TIME TIME,
  VISIT_TYPE VARCHAR(50),
  CHIEF_COMPLAINT VARCHAR(500),
  DIAGNOSIS_CODE VARCHAR(20),
  DIAGNOSIS_DESCRIPTION VARCHAR(500),
  TREATMENT_PLAN TEXT,
  FOLLOW_UP_REQUIRED BOOLEAN,
  FOLLOW_UP_DATE DATE,
  NOTES TEXT,
  LOADED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  FOREIGN KEY (PATIENT_ID) REFERENCES PATIENTS(PATIENT_ID),
  FOREIGN KEY (DOCTOR_ID) REFERENCES DOCTORS(DOCTOR_ID)
) COMMENT = 'Patient-doctor visit records';
```

**5. LAB_RESULTS table**:
```sql
CREATE OR REPLACE TABLE LAB_RESULTS (
  LAB_RESULT_ID VARCHAR(10) PRIMARY KEY,
  PATIENT_ID VARCHAR(10) NOT NULL,
  VISIT_ID VARCHAR(10) NOT NULL,
  CENTER_ID VARCHAR(10) NOT NULL,
  TEST_DATE DATE NOT NULL,
  TEST_TYPE VARCHAR(100),
  TEST_CODE VARCHAR(20),
  PDF_FILENAME VARCHAR(100),
  ORDERED_BY_DOCTOR_ID VARCHAR(10),
  STATUS VARCHAR(50),
  CRITICAL_FLAG BOOLEAN,
  LOADED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  FOREIGN KEY (PATIENT_ID) REFERENCES PATIENTS(PATIENT_ID),
  FOREIGN KEY (VISIT_ID) REFERENCES VISITS(VISIT_ID),
  FOREIGN KEY (CENTER_ID) REFERENCES DIAGNOSTIC_CENTERS(CENTER_ID),
  FOREIGN KEY (ORDERED_BY_DOCTOR_ID) REFERENCES DOCTORS(DOCTOR_ID)
) COMMENT = 'Laboratory test results metadata';
```

**6. DIAGNOSTIC_REPORTS table**:
```sql
CREATE OR REPLACE TABLE DIAGNOSTIC_REPORTS (
  REPORT_ID VARCHAR(10) PRIMARY KEY,
  PATIENT_ID VARCHAR(10) NOT NULL,
  VISIT_ID VARCHAR(10) NOT NULL,
  CENTER_ID VARCHAR(10) NOT NULL,
  EXAM_DATE DATE NOT NULL,
  EXAM_TYPE VARCHAR(50),
  MODALITY VARCHAR(50),
  BODY_PART VARCHAR(100),
  IMAGE_FILENAME VARCHAR(100),
  FINDINGS TEXT,
  IMPRESSION TEXT,
  RADIOLOGIST_NAME VARCHAR(100),
  CRITICAL_FINDING BOOLEAN,
  LOADED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  FOREIGN KEY (PATIENT_ID) REFERENCES PATIENTS(PATIENT_ID),
  FOREIGN KEY (VISIT_ID) REFERENCES VISITS(VISIT_ID),
  FOREIGN KEY (CENTER_ID) REFERENCES DIAGNOSTIC_CENTERS(CENTER_ID)
) COMMENT = 'Diagnostic imaging reports metadata';
```

**7. INSURANCE_CLAIMS table**:
```sql
CREATE OR REPLACE TABLE INSURANCE_CLAIMS (
  CLAIM_ID VARCHAR(10) PRIMARY KEY,
  PATIENT_ID VARCHAR(10) NOT NULL,
  VISIT_ID VARCHAR(10) NOT NULL,
  CLAIM_DATE DATE NOT NULL,
  INSURANCE_PROVIDER VARCHAR(100),
  POLICY_NUMBER VARCHAR(50),
  PROCEDURE_CODE VARCHAR(20),
  PROCEDURE_DESCRIPTION VARCHAR(500),
  DIAGNOSIS_CODE VARCHAR(20),
  BILLED_AMOUNT DECIMAL(10,2),
  ALLOWED_AMOUNT DECIMAL(10,2),
  PATIENT_RESPONSIBILITY DECIMAL(10,2),
  INSURANCE_PAID DECIMAL(10,2),
  CLAIM_STATUS VARCHAR(50),
  CLAIM_STATUS_DATE DATE,
  DENIAL_REASON VARCHAR(500),
  LOADED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  FOREIGN KEY (PATIENT_ID) REFERENCES PATIENTS(PATIENT_ID),
  FOREIGN KEY (VISIT_ID) REFERENCES VISITS(VISIT_ID)
) COMMENT = 'Insurance claim records';
```

**8. PRESCRIPTIONS table**:
```sql
CREATE OR REPLACE TABLE PRESCRIPTIONS (
  PRESCRIPTION_ID VARCHAR(10) PRIMARY KEY,
  PATIENT_ID VARCHAR(10) NOT NULL,
  VISIT_ID VARCHAR(10) NOT NULL,
  DOCTOR_ID VARCHAR(10) NOT NULL,
  PRESCRIPTION_DATE DATE NOT NULL,
  MEDICATION_NAME VARCHAR(200),
  NDC_CODE VARCHAR(20),
  DOSAGE VARCHAR(100),
  FREQUENCY VARCHAR(100),
  DURATION VARCHAR(100),
  REFILLS INTEGER,
  PDF_FILENAME VARCHAR(100),
  LOADED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  FOREIGN KEY (PATIENT_ID) REFERENCES PATIENTS(PATIENT_ID),
  FOREIGN KEY (VISIT_ID) REFERENCES VISITS(VISIT_ID),
  FOREIGN KEY (DOCTOR_ID) REFERENCES DOCTORS(DOCTOR_ID)
) COMMENT = 'Prescription records metadata';
```

**9. CLINICAL_NOTES table**:
```sql
CREATE OR REPLACE TABLE CLINICAL_NOTES (
  NOTE_ID VARCHAR(10) PRIMARY KEY,
  PATIENT_ID VARCHAR(10) NOT NULL,
  VISIT_ID VARCHAR(10),
  DOCTOR_ID VARCHAR(10) NOT NULL,
  NOTE_DATE DATE NOT NULL,
  NOTE_TYPE VARCHAR(100),
  PDF_FILENAME VARCHAR(100),
  SUMMARY TEXT,
  LOADED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  FOREIGN KEY (PATIENT_ID) REFERENCES PATIENTS(PATIENT_ID),
  FOREIGN KEY (VISIT_ID) REFERENCES VISITS(VISIT_ID),
  FOREIGN KEY (DOCTOR_ID) REFERENCES DOCTORS(DOCTOR_ID)
) COMMENT = 'Clinical documentation metadata';
```

**Expected outcome**: 9 tables created in RAW schema with proper foreign key constraints

---

### Phase 3: CSV Data Upload and Loading

#### Task 4: Upload CSV Files to Snowflake Stage

**SnowSQL PUT commands** (execute from local directory):
```sql
-- Navigate to project directory first
USE SCHEMA PATIENT360.RAW;

-- Upload CSV files
PUT file://synthetic-healthcare-data/csv/doctors.csv @CSV_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
PUT file://synthetic-healthcare-data/csv/diagnostic_centers.csv @CSV_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
PUT file://synthetic-healthcare-data/csv/patients.csv @CSV_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
PUT file://synthetic-healthcare-data/csv/visits.csv @CSV_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
PUT file://synthetic-healthcare-data/csv/lab_results.csv @CSV_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
PUT file://synthetic-healthcare-data/csv/diagnostic_reports.csv @CSV_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
PUT file://synthetic-healthcare-data/csv/insurance_claims.csv @CSV_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
PUT file://synthetic-healthcare-data/csv/prescriptions.csv @CSV_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
PUT file://synthetic-healthcare-data/csv/clinical_notes.csv @CSV_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;

-- Verify upload
LIST @CSV_STAGE;
```

**Alternative approach** using Python if PUT command fails:
- Use Snowflake Python connector with `write_pandas()` to load DataFrames directly
- Bypass stage upload and use multi-value INSERT statements

**Expected outcome**: 9 CSV files uploaded to CSV_STAGE

---

#### Task 5: Load Core Entity Data

**Load order** (respecting FK dependencies):
```sql
USE SCHEMA PATIENT360.RAW;

-- 1. Load DOCTORS (no dependencies)
COPY INTO DOCTORS
FROM @CSV_STAGE/doctors.csv
FILE_FORMAT = CSV_FORMAT
ON_ERROR = 'ABORT_STATEMENT'
PURGE = FALSE;

SELECT COUNT(*) AS doctors_loaded FROM DOCTORS;  -- Expect 50

-- 2. Load DIAGNOSTIC_CENTERS (no dependencies)
COPY INTO DIAGNOSTIC_CENTERS
FROM @CSV_STAGE/diagnostic_centers.csv
FILE_FORMAT = CSV_FORMAT
ON_ERROR = 'ABORT_STATEMENT'
PURGE = FALSE;

SELECT COUNT(*) AS centers_loaded FROM DIAGNOSTIC_CENTERS;  -- Expect 10

-- 3. Load PATIENTS (no dependencies)
COPY INTO PATIENTS
FROM @CSV_STAGE/patients.csv
FILE_FORMAT = CSV_FORMAT
ON_ERROR = 'ABORT_STATEMENT'
PURGE = FALSE;

SELECT COUNT(*) AS patients_loaded FROM PATIENTS;  -- Expect 100
```

**Validation queries**:
```sql
-- Verify age distribution
SELECT 
  CASE 
    WHEN AGE < 18 THEN 'Pediatric (3-17)'
    WHEN AGE < 65 THEN 'Adult (18-64)'
    ELSE 'Elderly (65+)'
  END AS age_group,
  COUNT(*) AS patient_count,
  ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM PATIENTS), 1) AS percentage
FROM PATIENTS
GROUP BY age_group
ORDER BY MIN(AGE);

-- Verify specialist count
SELECT 
  CASE 
    WHEN SPECIALTY IN ('Family Medicine', 'General Practice') THEN 'General'
    ELSE 'Specialist'
  END AS doctor_type,
  COUNT(*) AS count
FROM DOCTORS
GROUP BY doctor_type;
```

**Expected outcome**: 50 doctors, 10 centers, 100 patients loaded with validation passing

---

#### Task 6: Load Visit and Clinical Data

**VISITS must load before dependent tables**:
```sql
-- 4. Load VISITS (depends on PATIENTS and DOCTORS)
COPY INTO VISITS
FROM @CSV_STAGE/visits.csv
FILE_FORMAT = CSV_FORMAT
ON_ERROR = 'ABORT_STATEMENT'
PURGE = FALSE;

SELECT COUNT(*) AS visits_loaded FROM VISITS;  -- Expect ~572

-- 5. Load LAB_RESULTS (depends on VISITS, PATIENTS, CENTERS, DOCTORS)
COPY INTO LAB_RESULTS
FROM @CSV_STAGE/lab_results.csv
FILE_FORMAT = CSV_FORMAT
ON_ERROR = 'ABORT_STATEMENT'
PURGE = FALSE;

SELECT COUNT(*) AS lab_results_loaded FROM LAB_RESULTS;

-- 6. Load DIAGNOSTIC_REPORTS (depends on VISITS, PATIENTS, CENTERS)
COPY INTO DIAGNOSTIC_REPORTS
FROM @CSV_STAGE/diagnostic_reports.csv
FILE_FORMAT = CSV_FORMAT
ON_ERROR = 'ABORT_STATEMENT'
PURGE = FALSE;

SELECT COUNT(*) AS diagnostic_reports_loaded FROM DIAGNOSTIC_REPORTS;
```

**Validation queries**:
```sql
-- Verify FK integrity for visits
SELECT 
  (SELECT COUNT(*) FROM VISITS WHERE PATIENT_ID NOT IN (SELECT PATIENT_ID FROM PATIENTS)) AS invalid_patient_fk,
  (SELECT COUNT(*) FROM VISITS WHERE DOCTOR_ID NOT IN (SELECT DOCTOR_ID FROM DOCTORS)) AS invalid_doctor_fk;

-- Check visit distribution per patient
SELECT 
  MIN(visit_count) AS min_visits,
  MAX(visit_count) AS max_visits,
  ROUND(AVG(visit_count), 2) AS avg_visits
FROM (
  SELECT PATIENT_ID, COUNT(*) AS visit_count
  FROM VISITS
  GROUP BY PATIENT_ID
);
```

**Expected outcome**: All visits and dependent clinical data loaded with FK integrity maintained

---

#### Task 7: Load Financial and Prescription Data

```sql
-- 7. Load INSURANCE_CLAIMS (depends on VISITS and PATIENTS)
COPY INTO INSURANCE_CLAIMS
FROM @CSV_STAGE/insurance_claims.csv
FILE_FORMAT = CSV_FORMAT
ON_ERROR = 'ABORT_STATEMENT'
PURGE = FALSE;

SELECT COUNT(*) AS claims_loaded FROM INSURANCE_CLAIMS;

-- 8. Load PRESCRIPTIONS (depends on VISITS, PATIENTS, DOCTORS)
COPY INTO PRESCRIPTIONS
FROM @CSV_STAGE/prescriptions.csv
FILE_FORMAT = CSV_FORMAT
ON_ERROR = 'ABORT_STATEMENT'
PURGE = FALSE;

SELECT COUNT(*) AS prescriptions_loaded FROM PRESCRIPTIONS;

-- 9. Load CLINICAL_NOTES (depends on VISITS, PATIENTS, DOCTORS)
COPY INTO CLINICAL_NOTES
FROM @CSV_STAGE/clinical_notes.csv
FILE_FORMAT = CSV_FORMAT
ON_ERROR = 'ABORT_STATEMENT'
PURGE = FALSE;

SELECT COUNT(*) AS clinical_notes_loaded FROM CLINICAL_NOTES;
```

**Validation queries**:
```sql
-- Check claim status distribution
SELECT CLAIM_STATUS, COUNT(*) AS count
FROM INSURANCE_CLAIMS
GROUP BY CLAIM_STATUS
ORDER BY count DESC;

-- Verify prescriptions per visit
SELECT 
  COUNT(DISTINCT VISIT_ID) AS visits_with_prescriptions,
  COUNT(*) AS total_prescriptions,
  ROUND(COUNT(*) * 1.0 / COUNT(DISTINCT VISIT_ID), 2) AS avg_prescriptions_per_visit
FROM PRESCRIPTIONS;
```

**Expected outcome**: All financial and prescription data loaded successfully

---

### Phase 4: Unstructured Document Storage

#### Task 8: Create DOCUMENTS Schema Tables

```sql
USE SCHEMA PATIENT360.DOCUMENTS;

-- Table to track PDF lab results
CREATE OR REPLACE TABLE PDF_LAB_RESULTS (
  PDF_ID VARCHAR(50) PRIMARY KEY,
  LAB_RESULT_ID VARCHAR(10) NOT NULL,
  PATIENT_ID VARCHAR(10) NOT NULL,
  FILE_NAME VARCHAR(200) NOT NULL,
  STAGE_PATH VARCHAR(500) NOT NULL,
  FILE_SIZE_BYTES INTEGER,
  UPLOAD_TIMESTAMP TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  FOREIGN KEY (LAB_RESULT_ID) REFERENCES RAW.LAB_RESULTS(LAB_RESULT_ID),
  FOREIGN KEY (PATIENT_ID) REFERENCES RAW.PATIENTS(PATIENT_ID)
) COMMENT = 'Lab result PDF documents storage metadata';

-- Table to track prescription PDFs
CREATE OR REPLACE TABLE PDF_PRESCRIPTIONS (
  PDF_ID VARCHAR(50) PRIMARY KEY,
  PRESCRIPTION_ID VARCHAR(10) NOT NULL,
  PATIENT_ID VARCHAR(10) NOT NULL,
  FILE_NAME VARCHAR(200) NOT NULL,
  STAGE_PATH VARCHAR(500) NOT NULL,
  FILE_SIZE_BYTES INTEGER,
  UPLOAD_TIMESTAMP TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  FOREIGN KEY (PRESCRIPTION_ID) REFERENCES RAW.PRESCRIPTIONS(PRESCRIPTION_ID),
  FOREIGN KEY (PATIENT_ID) REFERENCES RAW.PATIENTS(PATIENT_ID)
) COMMENT = 'Prescription PDF documents storage metadata';

-- Table to track clinical note PDFs
CREATE OR REPLACE TABLE PDF_CLINICAL_NOTES (
  PDF_ID VARCHAR(50) PRIMARY KEY,
  NOTE_ID VARCHAR(10) NOT NULL,
  PATIENT_ID VARCHAR(10) NOT NULL,
  FILE_NAME VARCHAR(200) NOT NULL,
  STAGE_PATH VARCHAR(500) NOT NULL,
  FILE_SIZE_BYTES INTEGER,
  UPLOAD_TIMESTAMP TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  FOREIGN KEY (NOTE_ID) REFERENCES RAW.CLINICAL_NOTES(NOTE_ID),
  FOREIGN KEY (PATIENT_ID) REFERENCES RAW.PATIENTS(PATIENT_ID)
) COMMENT = 'Clinical note PDF documents storage metadata';

-- Table to track diagnostic images
CREATE OR REPLACE TABLE DIAGNOSTIC_IMAGES (
  IMAGE_ID VARCHAR(50) PRIMARY KEY,
  REPORT_ID VARCHAR(10) NOT NULL,
  PATIENT_ID VARCHAR(10) NOT NULL,
  FILE_NAME VARCHAR(200) NOT NULL,
  STAGE_PATH VARCHAR(500) NOT NULL,
  FILE_SIZE_BYTES INTEGER,
  IMAGE_FORMAT VARCHAR(10),
  UPLOAD_TIMESTAMP TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  FOREIGN KEY (REPORT_ID) REFERENCES RAW.DIAGNOSTIC_REPORTS(REPORT_ID),
  FOREIGN KEY (PATIENT_ID) REFERENCES RAW.PATIENTS(PATIENT_ID)
) COMMENT = 'Diagnostic imaging files storage metadata';
```

**Expected outcome**: 4 document metadata tables created in DOCUMENTS schema

---

#### Task 9: Upload PDF Files to Snowflake Stage

**SnowSQL PUT commands**:
```sql
USE SCHEMA PATIENT360.RAW;

-- Upload lab result PDFs (bulk upload entire directory)
PUT file://synthetic-healthcare-data/pdfs/lab_results/* @PDF_STAGE/lab_results/ AUTO_COMPRESS=FALSE OVERWRITE=TRUE;

-- Upload prescription PDFs
PUT file://synthetic-healthcare-data/pdfs/prescriptions/* @PDF_STAGE/prescriptions/ AUTO_COMPRESS=FALSE OVERWRITE=TRUE;

-- Upload clinical note PDFs
PUT file://synthetic-healthcare-data/pdfs/clinical_notes/* @PDF_STAGE/clinical_notes/ AUTO_COMPRESS=FALSE OVERWRITE=TRUE;

-- Verify uploads
LIST @PDF_STAGE/lab_results/;
LIST @PDF_STAGE/prescriptions/;
LIST @PDF_STAGE/clinical_notes/;
```

**Validation**:
```sql
-- Count files in each subdirectory
SELECT 
  'lab_results' AS document_type,
  COUNT(*) AS file_count
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
WHERE METADATA$FILENAME LIKE '%lab_results%'

UNION ALL

SELECT 
  'prescriptions' AS document_type,
  COUNT(*) AS file_count
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID(-2)))
WHERE METADATA$FILENAME LIKE '%prescriptions%';
```

**Expected outcome**: 1,694 PDF files uploaded across 3 subdirectories

---

#### Task 10: Upload Image Files to Snowflake Stage

**SnowSQL PUT commands**:
```sql
USE SCHEMA PATIENT360.RAW;

-- Upload all diagnostic images
PUT file://synthetic-healthcare-data/images/* @IMAGE_STAGE/ AUTO_COMPRESS=FALSE OVERWRITE=TRUE;

-- Verify upload
LIST @IMAGE_STAGE/;
```

**Validation**:
```sql
-- Count total images
SELECT COUNT(*) AS image_count
FROM DIRECTORY(@IMAGE_STAGE);
```

**Expected outcome**: 178 PNG image files uploaded

---

#### Task 11: Load Unstructured Document Metadata

**Approach**: Use Snowflake's `DIRECTORY` table function to populate metadata tables

```sql
USE SCHEMA PATIENT360.DOCUMENTS;

-- Populate PDF_LAB_RESULTS from stage directory listing
INSERT INTO PDF_LAB_RESULTS (PDF_ID, LAB_RESULT_ID, PATIENT_ID, FILE_NAME, STAGE_PATH, FILE_SIZE_BYTES)
SELECT 
  SPLIT_PART(RELATIVE_PATH, '_', 1) AS PDF_ID,  -- Extract LR000001 from filename
  SPLIT_PART(RELATIVE_PATH, '_', 1) AS LAB_RESULT_ID,
  lr.PATIENT_ID,
  RELATIVE_PATH AS FILE_NAME,
  '@PDF_STAGE/lab_results/' || RELATIVE_PATH AS STAGE_PATH,
  SIZE AS FILE_SIZE_BYTES
FROM DIRECTORY(@PATIENT360.RAW.PDF_STAGE)
JOIN PATIENT360.RAW.LAB_RESULTS lr 
  ON lr.LAB_RESULT_ID = SPLIT_PART(RELATIVE_PATH, '_', 1)
WHERE RELATIVE_PATH LIKE 'lab_results/%';

-- Populate PDF_PRESCRIPTIONS
INSERT INTO PDF_PRESCRIPTIONS (PDF_ID, PRESCRIPTION_ID, PATIENT_ID, FILE_NAME, STAGE_PATH, FILE_SIZE_BYTES)
SELECT 
  SPLIT_PART(RELATIVE_PATH, '_', 1) AS PDF_ID,
  SPLIT_PART(RELATIVE_PATH, '_', 1) AS PRESCRIPTION_ID,
  p.PATIENT_ID,
  RELATIVE_PATH AS FILE_NAME,
  '@PDF_STAGE/prescriptions/' || RELATIVE_PATH AS STAGE_PATH,
  SIZE AS FILE_SIZE_BYTES
FROM DIRECTORY(@PATIENT360.RAW.PDF_STAGE)
JOIN PATIENT360.RAW.PRESCRIPTIONS p 
  ON p.PRESCRIPTION_ID = SPLIT_PART(RELATIVE_PATH, '_', 1)
WHERE RELATIVE_PATH LIKE 'prescriptions/%';

-- Populate PDF_CLINICAL_NOTES
INSERT INTO PDF_CLINICAL_NOTES (PDF_ID, NOTE_ID, PATIENT_ID, FILE_NAME, STAGE_PATH, FILE_SIZE_BYTES)
SELECT 
  SPLIT_PART(RELATIVE_PATH, '_', 1) AS PDF_ID,
  SPLIT_PART(RELATIVE_PATH, '_', 1) AS NOTE_ID,
  cn.PATIENT_ID,
  RELATIVE_PATH AS FILE_NAME,
  '@PDF_STAGE/clinical_notes/' || RELATIVE_PATH AS STAGE_PATH,
  SIZE AS FILE_SIZE_BYTES
FROM DIRECTORY(@PATIENT360.RAW.PDF_STAGE)
JOIN PATIENT360.RAW.CLINICAL_NOTES cn 
  ON cn.NOTE_ID = SPLIT_PART(RELATIVE_PATH, '_', 1)
WHERE RELATIVE_PATH LIKE 'clinical_notes/%';

-- Populate DIAGNOSTIC_IMAGES
INSERT INTO DIAGNOSTIC_IMAGES (IMAGE_ID, REPORT_ID, PATIENT_ID, FILE_NAME, STAGE_PATH, FILE_SIZE_BYTES, IMAGE_FORMAT)
SELECT 
  SPLIT_PART(RELATIVE_PATH, '_', 1) AS IMAGE_ID,
  SPLIT_PART(RELATIVE_PATH, '_', 1) AS REPORT_ID,
  dr.PATIENT_ID,
  RELATIVE_PATH AS FILE_NAME,
  '@IMAGE_STAGE/' || RELATIVE_PATH AS STAGE_PATH,
  SIZE AS FILE_SIZE_BYTES,
  'PNG' AS IMAGE_FORMAT
FROM DIRECTORY(@PATIENT360.RAW.IMAGE_STAGE)
JOIN PATIENT360.RAW.DIAGNOSTIC_REPORTS dr 
  ON dr.REPORT_ID = SPLIT_PART(RELATIVE_PATH, '_', 1);
```

**Validation queries**:
```sql
-- Verify document counts
SELECT 
  (SELECT COUNT(*) FROM PDF_LAB_RESULTS) AS lab_result_pdfs,
  (SELECT COUNT(*) FROM PDF_PRESCRIPTIONS) AS prescription_pdfs,
  (SELECT COUNT(*) FROM PDF_CLINICAL_NOTES) AS clinical_note_pdfs,
  (SELECT COUNT(*) FROM DIAGNOSTIC_IMAGES) AS diagnostic_images;

-- Check for orphaned metadata (files without corresponding records)
SELECT COUNT(*) AS orphaned_lab_pdfs
FROM PDF_LAB_RESULTS pdf
WHERE NOT EXISTS (
  SELECT 1 FROM PATIENT360.RAW.LAB_RESULTS lr 
  WHERE lr.LAB_RESULT_ID = pdf.LAB_RESULT_ID
);
```

**Expected outcome**: All document metadata loaded with proper FK relationships

---

### Phase 5: Data Validation

#### Task 12: Validate Data Load and Referential Integrity

**Comprehensive validation queries**:

```sql
-- 1. Row count summary
SELECT 
  'DOCTORS' AS table_name, COUNT(*) AS row_count, 50 AS expected FROM PATIENT360.RAW.DOCTORS
UNION ALL
SELECT 'DIAGNOSTIC_CENTERS', COUNT(*), 10 FROM PATIENT360.RAW.DIAGNOSTIC_CENTERS
UNION ALL
SELECT 'PATIENTS', COUNT(*), 100 FROM PATIENT360.RAW.PATIENTS
UNION ALL
SELECT 'VISITS', COUNT(*), 572 FROM PATIENT360.RAW.VISITS
UNION ALL
SELECT 'LAB_RESULTS', COUNT(*), NULL FROM PATIENT360.RAW.LAB_RESULTS
UNION ALL
SELECT 'DIAGNOSTIC_REPORTS', COUNT(*), NULL FROM PATIENT360.RAW.DIAGNOSTIC_REPORTS
UNION ALL
SELECT 'INSURANCE_CLAIMS', COUNT(*), NULL FROM PATIENT360.RAW.INSURANCE_CLAIMS
UNION ALL
SELECT 'PRESCRIPTIONS', COUNT(*), NULL FROM PATIENT360.RAW.PRESCRIPTIONS
UNION ALL
SELECT 'CLINICAL_NOTES', COUNT(*), NULL FROM PATIENT360.RAW.CLINICAL_NOTES
UNION ALL
SELECT 'PDF_LAB_RESULTS', COUNT(*), NULL FROM PATIENT360.DOCUMENTS.PDF_LAB_RESULTS
UNION ALL
SELECT 'PDF_PRESCRIPTIONS', COUNT(*), NULL FROM PATIENT360.DOCUMENTS.PDF_PRESCRIPTIONS
UNION ALL
SELECT 'PDF_CLINICAL_NOTES', COUNT(*), NULL FROM PATIENT360.DOCUMENTS.PDF_CLINICAL_NOTES
UNION ALL
SELECT 'DIAGNOSTIC_IMAGES', COUNT(*), 178 FROM PATIENT360.DOCUMENTS.DIAGNOSTIC_IMAGES;

-- 2. Referential integrity checks (should all return 0)
SELECT 
  'VISITS → PATIENTS' AS fk_check,
  COUNT(*) AS violations
FROM PATIENT360.RAW.VISITS v
WHERE NOT EXISTS (SELECT 1 FROM PATIENT360.RAW.PATIENTS p WHERE p.PATIENT_ID = v.PATIENT_ID)

UNION ALL

SELECT 
  'VISITS → DOCTORS',
  COUNT(*)
FROM PATIENT360.RAW.VISITS v
WHERE NOT EXISTS (SELECT 1 FROM PATIENT360.RAW.DOCTORS d WHERE d.DOCTOR_ID = v.DOCTOR_ID)

UNION ALL

SELECT 
  'LAB_RESULTS → VISITS',
  COUNT(*)
FROM PATIENT360.RAW.LAB_RESULTS lr
WHERE NOT EXISTS (SELECT 1 FROM PATIENT360.RAW.VISITS v WHERE v.VISIT_ID = lr.VISIT_ID)

UNION ALL

SELECT 
  'DIAGNOSTIC_REPORTS → VISITS',
  COUNT(*)
FROM PATIENT360.RAW.DIAGNOSTIC_REPORTS dr
WHERE NOT EXISTS (SELECT 1 FROM PATIENT360.RAW.VISITS v WHERE v.VISIT_ID = dr.VISIT_ID);

-- 3. Date consistency checks
SELECT 
  'Visits before patient birth' AS check_name,
  COUNT(*) AS violations
FROM PATIENT360.RAW.VISITS v
JOIN PATIENT360.RAW.PATIENTS p ON v.PATIENT_ID = p.PATIENT_ID
WHERE v.VISIT_DATE < p.DATE_OF_BIRTH

UNION ALL

SELECT 
  'Lab tests before visit',
  COUNT(*)
FROM PATIENT360.RAW.LAB_RESULTS lr
JOIN PATIENT360.RAW.VISITS v ON lr.VISIT_ID = v.VISIT_ID
WHERE lr.TEST_DATE < v.VISIT_DATE

UNION ALL

SELECT 
  'Diagnostic reports before visit',
  COUNT(*)
FROM PATIENT360.RAW.DIAGNOSTIC_REPORTS dr
JOIN PATIENT360.RAW.VISITS v ON dr.VISIT_ID = v.VISIT_ID
WHERE dr.EXAM_DATE < v.VISIT_DATE;

-- 4. File reference validation (check PDF filenames match metadata)
SELECT 
  'Lab results PDF mismatch' AS check_name,
  COUNT(*) AS violations
FROM PATIENT360.RAW.LAB_RESULTS lr
WHERE lr.PDF_FILENAME IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM PATIENT360.DOCUMENTS.PDF_LAB_RESULTS pdf 
    WHERE pdf.FILE_NAME LIKE '%' || lr.PDF_FILENAME || '%'
  )

UNION ALL

SELECT 
  'Prescription PDF mismatch',
  COUNT(*)
FROM PATIENT360.RAW.PRESCRIPTIONS p
WHERE p.PDF_FILENAME IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM PATIENT360.DOCUMENTS.PDF_PRESCRIPTIONS pdf 
    WHERE pdf.FILE_NAME LIKE '%' || p.PDF_FILENAME || '%'
  )

UNION ALL

SELECT 
  'Diagnostic image mismatch',
  COUNT(*)
FROM PATIENT360.RAW.DIAGNOSTIC_REPORTS dr
WHERE dr.IMAGE_FILENAME IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM PATIENT360.DOCUMENTS.DIAGNOSTIC_IMAGES img 
    WHERE img.FILE_NAME LIKE '%' || dr.IMAGE_FILENAME || '%'
  );

-- 5. Data quality spot checks
SELECT 
  'Patients with null names' AS quality_check,
  COUNT(*) AS violations
FROM PATIENT360.RAW.PATIENTS
WHERE FIRST_NAME IS NULL OR LAST_NAME IS NULL

UNION ALL

SELECT 
  'Doctors without specialty',
  COUNT(*)
FROM PATIENT360.RAW.DOCTORS
WHERE SPECIALTY IS NULL

UNION ALL

SELECT 
  'Visits without diagnosis',
  COUNT(*)
FROM PATIENT360.RAW.VISITS
WHERE DIAGNOSIS_CODE IS NULL;
```

**Expected outcome**: 
- All row counts match expected values
- All FK integrity checks return 0 violations
- All date consistency checks return 0 violations
- All file references are valid
- Data quality checks pass with acceptable violation counts

---

## Verification

### Success Criteria

1. **Database structure**: PATIENT360 database exists with 4 schemas (RAW, CURATED, ANALYTICS, DOCUMENTS)
2. **RAW schema**: 9 tables created and populated with correct row counts
3. **DOCUMENTS schema**: 4 metadata tables created and populated
4. **File staging**: 9 CSVs, 1,694 PDFs, and 178 images uploaded to stages
5. **Referential integrity**: All FK constraints satisfied with 0 violations
6. **Data quality**: No critical null values in required fields
7. **File references**: All PDF_FILENAME and IMAGE_FILENAME values in RAW tables have corresponding entries in DOCUMENTS schema

### Validation Commands

Run the comprehensive validation query from Task 12 to verify all success criteria.

### Rollback Plan

If any phase fails:
1. Drop the entire PATIENT360 database: `DROP DATABASE IF EXISTS PATIENT360;`
2. Review error messages and adjust table schemas or data loading approach
3. Re-run from Task 1

---

## Critical Files

- [synthetic-healthcare-data/csv/patients.csv](c:\coco\care360copilot\synthetic-healthcare-data\csv\patients.csv) - Core patient demographic data (100 records)
- [synthetic-healthcare-data/csv/visits.csv](c:\coco\care360copilot\synthetic-healthcare-data\csv\visits.csv) - Patient-doctor visit records (572 records)
- [synthetic-healthcare-data/csv/doctors.csv](c:\coco\care360copilot\synthetic-healthcare-data\csv\doctors.csv) - Doctor information (50 records)
- [synthetic-healthcare-data/pdfs/lab_results/](c:\coco\care360copilot\synthetic-healthcare-data\pdfs\lab_results) - Lab result PDF documents directory
- [synthetic-healthcare-data/images/](c:\coco\care360copilot\synthetic-healthcare-data\images) - Diagnostic imaging files directory (178 PNGs)

---

## Implementation Notes

### Privilege Requirements

The executing role must have:
- `CREATE DATABASE` on account
- `CREATE SCHEMA` on PATIENT360 database
- `CREATE TABLE` on all schemas
- `CREATE STAGE` on RAW schema
- `CREATE FILE FORMAT` on RAW schema
- `INSERT` on all tables
- `USAGE` on warehouse

### Alternative Loading Strategies

If `PUT` command is unavailable or fails:
1. **Python-based loading**: Use Snowflake Python connector with `write_pandas()` to load CSV DataFrames directly
2. **Multi-value INSERT**: Generate batched INSERT statements (20 rows per statement) for each table
3. **External stage**: Use S3/Azure/GCS external stage if internal stages have restrictions

### Performance Considerations

- Load order respects FK dependencies to avoid constraint violations
- Use `PURGE = FALSE` to retain staged files for debugging
- Batch inserts in groups of 20-50 rows for optimal performance
- Consider disabling FK constraints temporarily if load performance is slow, then re-enable and validate after

### Next Phase (Future Work)

After RAW data is loaded:
- **CURATED schema**: Create cleaned/validated views or tables with business rules applied
- **ANALYTICS schema**: Build aggregated tables for reporting (patient visit summaries, claim statistics, etc.)
- **Cortex Search**: Index clinical notes and PDFs for natural language search
- **Semantic views**: Create semantic models over RAW tables for Cortex Analyst queries