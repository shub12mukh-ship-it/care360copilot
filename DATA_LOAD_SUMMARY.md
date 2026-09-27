# Patient360 Data Load Summary

## Status: SQL Files Generated ✓

All necessary SQL files have been generated successfully to load the Patient360 dataset into Snowflake.

## Generated Files

1. **load_csv_data.sql** (204 KB)
   - Contains INSERT statements for all 9 CSV tables
   - Ready to execute in Snowsight or any Snowflake SQL client

2. **load_files.sql**
   - CREATE STAGE commands for file storage
   - PUT commands for uploading images and PDFs

3. **load_all_data.sql**
   - Verification queries to confirm data load

## Dataset Summary (After Reduction)

### CSV Tables
| Table | Records |
|-------|---------|
| DOCTORS | 50 |
| DIAGNOSTIC_CENTERS | 10 |
| PATIENTS | 100 |
| VISITS | 150 |
| LAB_RESULTS | 150 |
| DIAGNOSTIC_REPORTS | 150 |
| INSURANCE_CLAIMS | 150 |
| PRESCRIPTIONS | 150 |
| CLINICAL_NOTES | 150 |
| **TOTAL** | **1,060** |

### Files
- **Images**: 150 diagnostic images (X-rays, CT scans, MRIs, Ultrasounds)
- **Lab Result PDFs**: 150 PDF reports
- **Prescription PDFs**: 150 PDF documents
- **Clinical Note PDFs**: 150 PDF documents
- **Total Files**: 600

## Next Steps

### Option 1: Execute via Snowsight (Recommended)

1. Open Snowsight (Snowflake web UI)
2. Navigate to Worksheets
3. Open `load_csv_data.sql`
4. Execute the entire script
5. Verify with the query in `load_all_data.sql`

### Option 2: Execute via Snowflake CLI

If you have the Snowflake CLI (`snow`) installed:

```bash
# Load CSV data
snow sql -f load_csv_data.sql

# Create stages and upload files
snow sql -f load_files.sql

# Verify
snow sql -f load_all_data.sql
```

### Step 2: Upload Files

After loading CSV data, upload files using the Snowflake CLI:

```bash
# Upload diagnostic images
snow sql -q "PUT file://synthetic-healthcare-data/images/*.png @PATIENT360.RAW.DIAGNOSTIC_IMAGES AUTO_COMPRESS=FALSE;"

# Upload lab result PDFs
snow sql -q "PUT file://synthetic-healthcare-data/pdfs/lab_results/*.pdf @PATIENT360.RAW.LAB_RESULT_PDFS AUTO_COMPRESS=FALSE;"

# Upload prescription PDFs
snow sql -q "PUT file://synthetic-healthcare-data/pdfs/prescriptions/*.pdf @PATIENT360.RAW.PRESCRIPTION_PDFS AUTO_COMPRESS=FALSE;"

# Upload clinical note PDFs
snow sql -q "PUT file://synthetic-healthcare-data/pdfs/clinical_notes/*.pdf @PATIENT360.RAW.CLINICAL_NOTE_PDFS AUTO_COMPRESS=FALSE;"
```

## Verification Query

Run this to confirm all data loaded correctly:

```sql
USE DATABASE PATIENT360;
USE SCHEMA RAW;

SELECT 'DOCTORS' AS TABLE_NAME, COUNT(*) AS ROW_COUNT FROM DOCTORS
UNION ALL SELECT 'PATIENTS', COUNT(*) FROM PATIENTS
UNION ALL SELECT 'VISITS', COUNT(*) FROM VISITS
UNION ALL SELECT 'LAB_RESULTS', COUNT(*) FROM LAB_RESULTS
UNION ALL SELECT 'DIAGNOSTIC_REPORTS', COUNT(*) FROM DIAGNOSTIC_REPORTS
UNION ALL SELECT 'PRESCRIPTIONS', COUNT(*) FROM PRESCRIPTIONS
UNION ALL SELECT 'CLINICAL_NOTES', COUNT(*) FROM CLINICAL_NOTES
UNION ALL SELECT 'INSURANCE_CLAIMS', COUNT(*) FROM INSURANCE_CLAIMS
UNION ALL SELECT 'DIAGNOSTIC_CENTERS', COUNT(*) FROM DIAGNOSTIC_CENTERS
ORDER BY TABLE_NAME;
```

## Files Location

All synthetic data files are in:
- CSV: `synthetic-healthcare-data/csv/`
- Images: `synthetic-healthcare-data/images/`
- PDFs: `synthetic-healthcare-data/pdfs/`

## Database Structure

```
PATIENT360 (Database)
└── RAW (Schema)
    ├── Tables (9)
    │   ├── DOCTORS
    │   ├── DIAGNOSTIC_CENTERS
    │   ├── PATIENTS
    │   ├── VISITS
    │   ├── LAB_RESULTS
    │   ├── DIAGNOSTIC_REPORTS
    │   ├── INSURANCE_CLAIMS
    │   ├── PRESCRIPTIONS
    │   └── CLINICAL_NOTES
    └── Stages (4)
        ├── DIAGNOSTIC_IMAGES
        ├── LAB_RESULT_PDFS
        ├── PRESCRIPTION_PDFS
        └── CLINICAL_NOTE_PDFS
```

## Notes

- All SQL statements are ready to execute
- The PUT commands require Snowflake CLI or SnowSQL
- Alternatively, files can be uploaded via Snowsight UI
- Data relationships and foreign keys are respected in load order
