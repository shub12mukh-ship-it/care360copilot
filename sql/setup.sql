-- =============================================================================
-- Care360 Copilot - Snowflake Setup
-- Run this first to create all database objects
-- =============================================================================

USE ROLE SYSADMIN;

-- =============================================================================
-- DATABASE
-- =============================================================================
CREATE DATABASE IF NOT EXISTS CARE360_DB;
USE DATABASE CARE360_DB;

-- =============================================================================
-- WAREHOUSE
-- =============================================================================
CREATE WAREHOUSE IF NOT EXISTS CARE360_WH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 120
    AUTO_RESUME = TRUE;

USE WAREHOUSE CARE360_WH;

-- =============================================================================
-- SCHEMAS
-- =============================================================================
CREATE SCHEMA IF NOT EXISTS RAW;
CREATE SCHEMA IF NOT EXISTS CURATED;
CREATE SCHEMA IF NOT EXISTS ANALYTICS;
CREATE SCHEMA IF NOT EXISTS DOCUMENTS;

-- =============================================================================
-- RAW SCHEMA - Source tables matching CSV ingestion
-- =============================================================================
USE SCHEMA RAW;

-- Internal stage for CSV data loading
CREATE STAGE IF NOT EXISTS care360_stage
    FILE_FORMAT = (TYPE = 'CSV' FIELD_OPTIONALLY_ENCLOSED_BY = '"' SKIP_HEADER = 1);

-- Reusable file format
CREATE FILE FORMAT IF NOT EXISTS csv_format
    TYPE = 'CSV'
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    SKIP_HEADER = 1
    NULL_IF = ('NULL', 'null', '');

-- Patients
CREATE OR REPLACE TABLE PATIENTS (
    patient_id              VARCHAR(20)  PRIMARY KEY,
    first_name              VARCHAR(50),
    last_name               VARCHAR(50),
    date_of_birth           DATE,
    gender                  VARCHAR(10),
    race                    VARCHAR(30),
    ethnicity               VARCHAR(30),
    language                VARCHAR(30),
    marital_status          VARCHAR(20),
    address                 VARCHAR(200),
    city                    VARCHAR(50),
    state                   VARCHAR(2),
    zip_code                VARCHAR(10),
    phone                   VARCHAR(20),
    email                   VARCHAR(100),
    insurance_type          VARCHAR(30),
    insurance_plan          VARCHAR(100),
    pcp_name                VARCHAR(100),
    pcp_phone               VARCHAR(20),
    emergency_contact_name  VARCHAR(100),
    emergency_contact_phone VARCHAR(20),
    blood_type              VARCHAR(5),
    smoking_status          VARCHAR(20),
    alcohol_use             VARCHAR(20),
    bmi                     NUMBER(5,1),
    risk_score              VARCHAR(20),
    created_at              TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- Diagnosis
CREATE OR REPLACE TABLE DIAGNOSIS (
    diagnosis_id            VARCHAR(20)  PRIMARY KEY,
    patient_id              VARCHAR(20)  REFERENCES PATIENTS(patient_id),
    visit_id                VARCHAR(20),
    icd10_code              VARCHAR(10),
    diagnosis_description   VARCHAR(200),
    diagnosis_type          VARCHAR(20),
    diagnosis_date          DATE,
    diagnosed_by            VARCHAR(100),
    status                  VARCHAR(20),
    onset_date              DATE,
    severity                VARCHAR(20),
    is_chronic              VARCHAR(5),
    created_at              TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- Medications
CREATE OR REPLACE TABLE MEDICATIONS (
    medication_id           VARCHAR(20)  PRIMARY KEY,
    patient_id              VARCHAR(20)  REFERENCES PATIENTS(patient_id),
    visit_id                VARCHAR(20),
    medication_name         VARCHAR(100),
    generic_name            VARCHAR(100),
    ndc_code                VARCHAR(20),
    dosage                  VARCHAR(50),
    route                   VARCHAR(20),
    frequency               VARCHAR(50),
    prescribing_provider    VARCHAR(100),
    start_date              DATE,
    end_date                DATE,
    status                  VARCHAR(20),
    refills_remaining       NUMBER(5),
    pharmacy                VARCHAR(100),
    indication              VARCHAR(200),
    drug_class              VARCHAR(50),
    created_at              TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- Labs
CREATE OR REPLACE TABLE LABS (
    lab_id                  VARCHAR(20)  PRIMARY KEY,
    patient_id              VARCHAR(20)  REFERENCES PATIENTS(patient_id),
    visit_id                VARCHAR(20),
    lab_date                DATE,
    test_name               VARCHAR(100),
    test_code               VARCHAR(20),
    result_value            VARCHAR(50),
    result_unit             VARCHAR(20),
    reference_range_low     NUMBER(10,2),
    reference_range_high    NUMBER(10,2),
    abnormal_flag           VARCHAR(10),
    ordering_provider       VARCHAR(100),
    lab_status              VARCHAR(20),
    category                VARCHAR(50),
    created_at              TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- Visits
CREATE OR REPLACE TABLE VISITS (
    visit_id                VARCHAR(20)  PRIMARY KEY,
    patient_id              VARCHAR(20)  REFERENCES PATIENTS(patient_id),
    visit_date              DATE,
    visit_type              VARCHAR(20),
    department              VARCHAR(50),
    provider_name           VARCHAR(100),
    chief_complaint         VARCHAR(200),
    primary_diagnosis       VARCHAR(10),
    diagnosis_desc          VARCHAR(200),
    discharge_disposition   VARCHAR(50),
    length_of_stay_days     NUMBER(5,1),
    created_at              TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- Claims
CREATE OR REPLACE TABLE CLAIMS (
    claim_id                VARCHAR(20)  PRIMARY KEY,
    patient_id              VARCHAR(20)  REFERENCES PATIENTS(patient_id),
    visit_id                VARCHAR(20),
    claim_date              DATE,
    service_date            DATE,
    claim_type              VARCHAR(30),
    icd10_primary           VARCHAR(10),
    cpt_code                VARCHAR(10),
    cpt_description         VARCHAR(200),
    billed_amount           NUMBER(10,2),
    allowed_amount          NUMBER(10,2),
    paid_amount             NUMBER(10,2),
    patient_responsibility  NUMBER(10,2),
    claim_status            VARCHAR(20),
    payer_name              VARCHAR(100),
    denial_reason           VARCHAR(200),
    provider_name           VARCHAR(100),
    facility_name           VARCHAR(100),
    place_of_service        VARCHAR(50),
    created_at              TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- =============================================================================
-- DOCUMENTS SCHEMA - Chunked documents for Cortex Search / RAG
-- =============================================================================
USE SCHEMA DOCUMENTS;

CREATE OR REPLACE TABLE DOCUMENT_CHUNKS (
    chunk_id                VARCHAR(30)  PRIMARY KEY,
    document_id             VARCHAR(20),
    patient_id              VARCHAR(20),
    visit_id                VARCHAR(20),
    document_date           DATE,
    document_type           VARCHAR(50),
    author_name             VARCHAR(100),
    chunk_index             NUMBER(5),
    chunk_text              VARCHAR(8000),
    patient_name            VARCHAR(100),
    created_at              TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- =============================================================================
-- CURATED SCHEMA - Cleaned / enriched views (populated by pipeline.sql)
-- =============================================================================
USE SCHEMA CURATED;

-- Placeholder: curated tables/views are created by the transformation pipeline

-- =============================================================================
-- ANALYTICS SCHEMA - Aggregated views for dashboards and reporting
-- =============================================================================
USE SCHEMA ANALYTICS;

-- Placeholder: analytics tables/views are created by patient360.sql

-- =============================================================================
-- GRANTS (adjust role names to match your environment)
-- =============================================================================
-- GRANT USAGE ON DATABASE CARE360_DB TO ROLE <your_role>;
-- GRANT USAGE ON ALL SCHEMAS IN DATABASE CARE360_DB TO ROLE <your_role>;
-- GRANT SELECT ON ALL TABLES IN SCHEMA CARE360_DB.RAW TO ROLE <your_role>;
-- GRANT SELECT ON ALL TABLES IN SCHEMA CARE360_DB.CURATED TO ROLE <your_role>;
-- GRANT SELECT ON ALL TABLES IN SCHEMA CARE360_DB.ANALYTICS TO ROLE <your_role>;
-- GRANT SELECT ON ALL TABLES IN SCHEMA CARE360_DB.DOCUMENTS TO ROLE <your_role>;
