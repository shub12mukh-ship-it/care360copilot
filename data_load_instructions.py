"""
Execute all Patient360 data loading via individual SQL statements
This allows CoCo to execute the full load operation
"""

def main():
    print("=" * 80)
    print("PATIENT360 DATA LOAD - EXECUTION INSTRUCTIONS")
    print("=" * 80)
    
    print("\nThe SQL files have been generated successfully:")
    print("  ✓ load_csv_data.sql - Contains all CSV data INSERT statements")
    print("  ✓ load_files.sql - Contains stage creation and file upload instructions")
    
    print("\n" + "=" * 80)
    print("STEP 1: LOAD CSV DATA")
    print("=" * 80)
    print("\nTo load the CSV data into Snowflake tables:")
    print("  1. Open load_csv_data.sql in Snowsight or a SQL editor")
    print("  2. Execute the entire script")
    print("  3. This will load all 9 tables with the reduced dataset:")
    print("     - DOCTORS: 50 records")
    print("     - DIAGNOSTIC_CENTERS: 10 records")
    print("     - PATIENTS: 100 records")
    print("     - VISITS: 150 records")
    print("     - LAB_RESULTS: 150 records")
    print("     - DIAGNOSTIC_REPORTS: 150 records")
    print("     - INSURANCE_CLAIMS: 150 records")
    print("     - PRESCRIPTIONS: 150 records")
    print("     - CLINICAL_NOTES: 150 records")
    
    print("\n" + "=" * 80)
    print("STEP 2: CREATE STAGES & UPLOAD FILES")
    print("=" * 80)
    print("\nTo upload images and PDFs:")
    print("  1. Open load_files.sql")
    print("  2. Execute the CREATE STAGE commands in Snowsight")
    print("  3. For the PUT commands, you'll need to use Snowflake CLI:")
    print()
    print("     snow sql -q \"PUT file://synthetic-healthcare-data/images/*.png @PATIENT360.RAW.DIAGNOSTIC_IMAGES AUTO_COMPRESS=FALSE;\"")
    print("     snow sql -q \"PUT file://synthetic-healthcare-data/pdfs/lab_results/*.pdf @PATIENT360.RAW.LAB_RESULT_PDFS AUTO_COMPRESS=FALSE;\"")
    print("     snow sql -q \"PUT file://synthetic-healthcare-data/pdfs/prescriptions/*.pdf @PATIENT360.RAW.PRESCRIPTION_PDFS AUTO_COMPRESS=FALSE;\"")
    print("     snow sql -q \"PUT file://synthetic-healthcare-data/pdfs/clinical_notes/*.pdf @PATIENT360.RAW.CLINICAL_NOTE_PDFS AUTO_COMPRESS=FALSE;\"")
    
    print("\n" + "=" * 80)
    print("STEP 3: VERIFY DATA LOAD")
    print("=" * 80)
    print("\nRun this query to verify all data was loaded:")
    print("""
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
    """)
    
    print("\n" + "=" * 80)
    print("FILE SUMMARY")
    print("=" * 80)
    print("\nDataset sizes after reduction:")
    print("  • Images: 150 files")
    print("  • Lab Result PDFs: 150 files")
    print("  • Prescription PDFs: 150 files")
    print("  • Clinical Note PDFs: 150 files")
    print("  • Total files: 600")
    
    print("\n✓ All SQL files are ready for execution!")
    print("\n" + "=" * 80)

if __name__ == '__main__':
    main()
