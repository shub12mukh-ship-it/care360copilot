-- Load images and PDFs into Snowflake stages
USE DATABASE PATIENT360;
USE SCHEMA RAW;

-- Create stages for file storage
CREATE STAGE IF NOT EXISTS DIAGNOSTIC_IMAGES
  DIRECTORY = (ENABLE = TRUE)
  COMMENT = 'Stage for storing diagnostic images (X-rays, CT scans, MRIs, Ultrasounds)';

CREATE STAGE IF NOT EXISTS LAB_RESULT_PDFS
  DIRECTORY = (ENABLE = TRUE)
  COMMENT = 'Stage for storing lab result PDF reports';

CREATE STAGE IF NOT EXISTS PRESCRIPTION_PDFS
  DIRECTORY = (ENABLE = TRUE)
  COMMENT = 'Stage for storing prescription PDF documents';

CREATE STAGE IF NOT EXISTS CLINICAL_NOTE_PDFS
  DIRECTORY = (ENABLE = TRUE)
  COMMENT = 'Stage for storing clinical note PDF documents';

-- Upload files using PUT commands
-- Note: PUT commands must be run from SnowSQL or Snowflake CLI
-- They cannot be executed through standard SQL clients

-- Upload diagnostic images
PUT file://synthetic-healthcare-data/images/*.png @DIAGNOSTIC_IMAGES AUTO_COMPRESS=FALSE;
PUT file://synthetic-healthcare-data/images/*.jpg @DIAGNOSTIC_IMAGES AUTO_COMPRESS=FALSE;

-- Upload lab result PDFs
PUT file://synthetic-healthcare-data/pdfs/lab_results/*.pdf @LAB_RESULT_PDFS AUTO_COMPRESS=FALSE;

-- Upload prescription PDFs
PUT file://synthetic-healthcare-data/pdfs/prescriptions/*.pdf @PRESCRIPTION_PDFS AUTO_COMPRESS=FALSE;

-- Upload clinical note PDFs
PUT file://synthetic-healthcare-data/pdfs/clinical_notes/*.pdf @CLINICAL_NOTE_PDFS AUTO_COMPRESS=FALSE;

-- Verify uploads
LIST @DIAGNOSTIC_IMAGES;
LIST @LAB_RESULT_PDFS;
LIST @PRESCRIPTION_PDFS;
LIST @CLINICAL_NOTE_PDFS;