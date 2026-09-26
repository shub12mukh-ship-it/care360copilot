# Data Loading Instructions for Patient360

## Status
✅ **Completed (160 rows)**:
- DOCTORS: 50 rows
- DIAGNOSTIC_CENTERS: 10 rows
- PATIENTS: 100 rows

⏳ **Ready to Load (3,067 rows)**:
1. VISITS: 572 rows (MUST LOAD FIRST)
2. LAB_RESULTS: 317 rows
3. DIAGNOSTIC_REPORTS: 178 rows
4. INSURANCE_CLAIMS: 572 rows
5. PRESCRIPTIONS: 582 rows
6. CLINICAL_NOTES: 846 rows

## Loading Method (Recommended)

### Option 1: Via Snowsight (Visual, Easiest)
1. Open Snowsight: https://app.snowflake.com/jrmwqms/pa19066/
2. Navigate to Worksheets
3. Create a new SQL worksheet
4. For each file **in order** (VISITS first!):
   - Open the SQL file in Notepad: `C:\coco\care360copilot\sql_visits.sql`
   - Select All (Ctrl+A) and Copy (Ctrl+C)
   - Paste into Snowsight worksheet (Ctrl+V)
   - Click "Run All" button (or Ctrl+Enter)
   - Wait for completion (should take 5-15 seconds)
   - Verify row count in output
5. Repeat for remaining files in order:
   - `sql_lab_results.sql`
   - `sql_diagnostic_reports.sql`
   - `sql_insurance_claims.sql`
   - `sql_prescriptions.sql`
   - `sql_clinical_notes.sql`

### Option 2: Via PowerShell (Automated - Coming Soon)
I can create a PowerShell script to automate the loading. Would you like me to do that?

## Loading Order (Critical!)
**MUST load VISITS before the others** due to foreign key dependencies:
```
VISITS (parent table)
  ↓
├─ LAB_RESULTS
├─ DIAGNOSTIC_REPORTS  
├─ INSURANCE_CLAIMS
├─ PRESCRIPTIONS
└─ CLINICAL_NOTES
```

## Verification Queries
After loading, run these to verify:

```sql
-- Check row counts
SELECT 'DOCTORS' AS TABLE_NAME, COUNT(*) AS ROWS FROM PATIENT360.RAW.DOCTORS
UNION ALL
SELECT 'DIAGNOSTIC_CENTERS', COUNT(*) FROM PATIENT360.RAW.DIAGNOSTIC_CENTERS
UNION ALL
SELECT 'PATIENTS', COUNT(*) FROM PATIENT360.RAW.PATIENTS
UNION ALL
SELECT 'VISITS', COUNT(*) FROM PATIENT360.RAW.VISITS
UNION ALL
SELECT 'LAB_RESULTS', COUNT(*) FROM PATIENT360.RAW.LAB_RESULTS
UNION ALL
SELECT 'DIAGNOSTIC_REPORTS', COUNT(*) FROM PATIENT360.RAW.DIAGNOSTIC_REPORTS
UNION ALL
SELECT 'INSURANCE_CLAIMS', COUNT(*) FROM PATIENT360.RAW.INSURANCE_CLAIMS
UNION ALL
SELECT 'PRESCRIPTIONS', COUNT(*) FROM PATIENT360.RAW.PRESCRIPTIONS
UNION ALL
SELECT 'CLINICAL_NOTES', COUNT(*) FROM PATIENT360.RAW.CLINICAL_NOTES;
```

Expected results:
- DOCTORS: 50
- DIAGNOSTIC_CENTERS: 10
- PATIENTS: 100
- VISITS: 572
- LAB_RESULTS: 317
- DIAGNOSTIC_REPORTS: 178
- INSURANCE_CLAIMS: 572
- PRESCRIPTIONS: 582
- CLINICAL_NOTES: 846
- **Total: 3,227 rows**
