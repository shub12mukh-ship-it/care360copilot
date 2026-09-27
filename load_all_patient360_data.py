"""
Comprehensive loader for Patient360 data - generates SQL files
No external dependencies required (uses only csv module)
"""

import csv
from pathlib import Path
import sys

def escape_sql(val):
    """Escape single quotes for SQL"""
    if val is None or val == '':
        return 'NULL'
    return "'" + str(val).replace("'", "''") + "'"

def generate_csv_load_sql():
    """Generate SQL for loading CSV data into tables"""
    base_path = Path('synthetic-healthcare-data/csv')
    
    # Define table loading order (respecting FK dependencies)
    tables = [
        # Core entities (no dependencies)
        {
            'csv': 'doctors.csv',
            'table': 'DOCTORS',
            'columns': ['DOCTOR_ID', 'FIRST_NAME', 'LAST_NAME', 'SPECIALTY', 'SUB_SPECIALTY', 
                       'YEARS_EXPERIENCE', 'MEDICAL_SCHOOL', 'BOARD_CERTIFIED', 'PHONE', 'EMAIL', 'LICENSE_NUMBER']
        },
        {
            'csv': 'diagnostic_centers.csv',
            'table': 'DIAGNOSTIC_CENTERS',
            'columns': ['CENTER_ID', 'CENTER_NAME', 'ADDRESS', 'CITY', 'STATE', 'ZIP_CODE', 
                       'PHONE', 'SERVICES_OFFERED', 'ACCREDITATION', 'OPERATING_HOURS']
        },
        {
            'csv': 'patients.csv',
            'table': 'PATIENTS',
            'columns': ['PATIENT_ID', 'FIRST_NAME', 'LAST_NAME', 'DATE_OF_BIRTH', 'AGE', 'GENDER', 
                       'ETHNICITY', 'BLOOD_TYPE', 'ADDRESS', 'CITY', 'STATE', 'ZIP_CODE', 'PHONE', 
                       'EMAIL', 'EMERGENCY_CONTACT_NAME', 'EMERGENCY_CONTACT_PHONE', 
                       'INSURANCE_PROVIDER', 'INSURANCE_POLICY_NUMBER']
        },
        # Visits (depends on patients and doctors)
        {
            'csv': 'visits.csv',
            'table': 'VISITS',
            'columns': ['VISIT_ID', 'PATIENT_ID', 'DOCTOR_ID', 'VISIT_DATE', 'VISIT_TIME', 
                       'VISIT_TYPE', 'CHIEF_COMPLAINT', 'DIAGNOSIS_CODE', 'DIAGNOSIS_DESCRIPTION', 
                       'TREATMENT_PLAN', 'FOLLOW_UP_REQUIRED', 'FOLLOW_UP_DATE', 'NOTES']
        },
        # Lab results (depends on visits)
        {
            'csv': 'lab_results.csv',
            'table': 'LAB_RESULTS',
            'columns': ['LAB_RESULT_ID', 'PATIENT_ID', 'VISIT_ID', 'CENTER_ID', 'TEST_DATE', 
                       'TEST_TYPE', 'TEST_CODE', 'PDF_FILENAME', 'ORDERED_BY_DOCTOR_ID', 
                       'STATUS', 'CRITICAL_FLAG']
        },
        # Diagnostic reports (depends on visits)
        {
            'csv': 'diagnostic_reports.csv',
            'table': 'DIAGNOSTIC_REPORTS',
            'columns': ['REPORT_ID', 'PATIENT_ID', 'VISIT_ID', 'CENTER_ID', 'EXAM_DATE', 
                       'EXAM_TYPE', 'MODALITY', 'BODY_PART', 'IMAGE_FILENAME', 'FINDINGS', 
                       'IMPRESSION', 'RADIOLOGIST_NAME', 'CRITICAL_FINDING']
        },
        # Insurance claims (depends on visits)
        {
            'csv': 'insurance_claims.csv',
            'table': 'INSURANCE_CLAIMS',
            'columns': ['CLAIM_ID', 'PATIENT_ID', 'VISIT_ID', 'CLAIM_DATE', 'INSURANCE_PROVIDER', 
                       'POLICY_NUMBER', 'PROCEDURE_CODE', 'PROCEDURE_DESCRIPTION', 'DIAGNOSIS_CODE', 
                       'BILLED_AMOUNT', 'ALLOWED_AMOUNT', 'PATIENT_RESPONSIBILITY', 'INSURANCE_PAID', 
                       'CLAIM_STATUS', 'CLAIM_STATUS_DATE', 'DENIAL_REASON']
        },
        # Prescriptions (depends on visits)
        {
            'csv': 'prescriptions.csv',
            'table': 'PRESCRIPTIONS',
            'columns': ['PRESCRIPTION_ID', 'PATIENT_ID', 'VISIT_ID', 'DOCTOR_ID', 'PRESCRIPTION_DATE', 
                       'MEDICATION_NAME', 'NDC_CODE', 'DOSAGE', 'FREQUENCY', 'DURATION', 'REFILLS', 
                       'PDF_FILENAME']
        },
        # Clinical notes (depends on visits)
        {
            'csv': 'clinical_notes.csv',
            'table': 'CLINICAL_NOTES',
            'columns': ['NOTE_ID', 'PATIENT_ID', 'VISIT_ID', 'DOCTOR_ID', 'NOTE_DATE', 
                       'NOTE_TYPE', 'PDF_FILENAME', 'SUMMARY']
        }
    ]
    
    print("=" * 80)
    print("GENERATING CSV LOAD STATEMENTS")
    print("=" * 80)
    
    sql_statements = []
    sql_statements.append("-- Load CSV data into RAW tables")
    sql_statements.append("USE DATABASE PATIENT360;")
    sql_statements.append("USE SCHEMA RAW;\n")
    
    for table_info in tables:
        csv_path = base_path / table_info['csv']
        if not csv_path.exists():
            print(f"WARNING: {csv_path} not found, skipping...")
            continue
        
        table_name = table_info['table']
        columns = table_info['columns']
        
        print(f"\nProcessing {table_name} from {csv_path}...")
        
        # Read CSV file
        with open(csv_path, 'r', encoding='utf-8', newline='') as f:
            reader = csv.DictReader(f)
            rows = list(reader)
        
        print(f"  Found {len(rows)} rows")
        
        # Create a lowercase column mapping
        if rows:
            csv_columns_lower = {k.lower(): k for k in rows[0].keys()}
        else:
            csv_columns_lower = {}
        
        # Clear existing data
        sql_statements.append(f"-- Load {table_name}")
        sql_statements.append(f"DELETE FROM {table_name};")
        
        # Generate INSERT statements in batches
        batch_size = 100
        for i in range(0, len(rows), batch_size):
            batch = rows[i:i+batch_size]
            values = []
            
            for row in batch:
                val_parts = []
                for col in columns:
                    # Try to find the column case-insensitively
                    csv_col = csv_columns_lower.get(col.lower())
                    if csv_col and csv_col in row:
                        val = row[csv_col]
                        if val == '' or val is None:
                            val_parts.append('NULL')
                        elif val.replace('.', '', 1).replace('-', '', 1).isdigit():
                            # Numeric value
                            val_parts.append(val)
                        elif val.upper() in ('TRUE', 'FALSE'):
                            val_parts.append(val.upper())
                        else:
                            val_parts.append(escape_sql(val))
                    else:
                        val_parts.append('NULL')
                
                values.append(f"({','.join(val_parts)})")
            
            col_list = ','.join(columns)
            sql_statements.append(f"INSERT INTO {table_name} ({col_list}) VALUES")
            sql_statements.append(',\n'.join(values) + ';')
        
        sql_statements.append("")  # Empty line between tables
    
    # Write to file
    output_file = 'load_csv_data.sql'
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write('\n'.join(sql_statements))
    
    print(f"\n✓ Generated {output_file}")
    return output_file

def generate_file_load_sql():
    """Generate SQL for loading images and PDFs using stages"""
    
    print("\n" + "=" * 80)
    print("GENERATING FILE LOAD STATEMENTS (IMAGES & PDFS)")
    print("=" * 80)
    
    sql_statements = []
    sql_statements.append("-- Load images and PDFs into Snowflake stages")
    sql_statements.append("USE DATABASE PATIENT360;")
    sql_statements.append("USE SCHEMA RAW;\n")
    
    # Create stages if they don't exist
    sql_statements.append("-- Create stages for file storage")
    sql_statements.append("CREATE STAGE IF NOT EXISTS DIAGNOSTIC_IMAGES")
    sql_statements.append("  DIRECTORY = (ENABLE = TRUE)")
    sql_statements.append("  COMMENT = 'Stage for storing diagnostic images (X-rays, CT scans, MRIs, Ultrasounds)';")
    sql_statements.append("")
    
    sql_statements.append("CREATE STAGE IF NOT EXISTS LAB_RESULT_PDFS")
    sql_statements.append("  DIRECTORY = (ENABLE = TRUE)")
    sql_statements.append("  COMMENT = 'Stage for storing lab result PDF reports';")
    sql_statements.append("")
    
    sql_statements.append("CREATE STAGE IF NOT EXISTS PRESCRIPTION_PDFS")
    sql_statements.append("  DIRECTORY = (ENABLE = TRUE)")
    sql_statements.append("  COMMENT = 'Stage for storing prescription PDF documents';")
    sql_statements.append("")
    
    sql_statements.append("CREATE STAGE IF NOT EXISTS CLINICAL_NOTE_PDFS")
    sql_statements.append("  DIRECTORY = (ENABLE = TRUE)")
    sql_statements.append("  COMMENT = 'Stage for storing clinical note PDF documents';")
    sql_statements.append("")
    
    # Count files
    images_path = Path('synthetic-healthcare-data/images')
    pdfs_path = Path('synthetic-healthcare-data/pdfs')
    
    image_files = list(images_path.rglob('*.png')) + list(images_path.rglob('*.jpg'))
    print(f"\nFound {len(image_files)} images to upload")
    
    lab_pdfs = list((pdfs_path / 'lab_results').glob('*.pdf')) if (pdfs_path / 'lab_results').exists() else []
    print(f"Found {len(lab_pdfs)} lab result PDFs to upload")
    
    prescription_pdfs = list((pdfs_path / 'prescriptions').glob('*.pdf')) if (pdfs_path / 'prescriptions').exists() else []
    print(f"Found {len(prescription_pdfs)} prescription PDFs to upload")
    
    clinical_pdfs = list((pdfs_path / 'clinical_notes').glob('*.pdf')) if (pdfs_path / 'clinical_notes').exists() else []
    print(f"Found {len(clinical_pdfs)} clinical note PDFs to upload")
    
    # Add PUT commands (to be executed via SnowSQL or Snowflake CLI)
    sql_statements.append("-- Upload files using PUT commands")
    sql_statements.append("-- Note: PUT commands must be run from SnowSQL or Snowflake CLI")
    sql_statements.append("-- They cannot be executed through standard SQL clients\n")
    
    sql_statements.append("-- Upload diagnostic images")
    sql_statements.append("PUT file://synthetic-healthcare-data/images/*.png @DIAGNOSTIC_IMAGES AUTO_COMPRESS=FALSE;")
    sql_statements.append("PUT file://synthetic-healthcare-data/images/*.jpg @DIAGNOSTIC_IMAGES AUTO_COMPRESS=FALSE;")
    sql_statements.append("")
    
    sql_statements.append("-- Upload lab result PDFs")
    sql_statements.append("PUT file://synthetic-healthcare-data/pdfs/lab_results/*.pdf @LAB_RESULT_PDFS AUTO_COMPRESS=FALSE;")
    sql_statements.append("")
    
    sql_statements.append("-- Upload prescription PDFs")
    sql_statements.append("PUT file://synthetic-healthcare-data/pdfs/prescriptions/*.pdf @PRESCRIPTION_PDFS AUTO_COMPRESS=FALSE;")
    sql_statements.append("")
    
    sql_statements.append("-- Upload clinical note PDFs")
    sql_statements.append("PUT file://synthetic-healthcare-data/pdfs/clinical_notes/*.pdf @CLINICAL_NOTE_PDFS AUTO_COMPRESS=FALSE;")
    sql_statements.append("")
    
    sql_statements.append("-- Verify uploads")
    sql_statements.append("LIST @DIAGNOSTIC_IMAGES;")
    sql_statements.append("LIST @LAB_RESULT_PDFS;")
    sql_statements.append("LIST @PRESCRIPTION_PDFS;")
    sql_statements.append("LIST @CLINICAL_NOTE_PDFS;")
    
    # Write to file
    output_file = 'load_files.sql'
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write('\n'.join(sql_statements))
    
    print(f"\n✓ Generated {output_file}")
    return output_file

def generate_master_script():
    """Generate a master script that combines everything"""
    
    sql_statements = []
    sql_statements.append("/*")
    sql_statements.append(" * Master script for loading Patient360 data")
    sql_statements.append(" * Includes: CSV data, images, and PDFs")
    sql_statements.append(" */\n")
    
    sql_statements.append("-- Step 1: Load CSV data into tables")
    sql_statements.append("-- Execute load_csv_data.sql first\n")
    
    sql_statements.append("-- Step 2: Create stages and upload files")
    sql_statements.append("-- Then execute load_files.sql\n")
    
    sql_statements.append("-- Step 3: Verify data loads")
    sql_statements.append("USE DATABASE PATIENT360;")
    sql_statements.append("USE SCHEMA RAW;\n")
    sql_statements.append("SELECT 'DOCTORS' AS TABLE_NAME, COUNT(*) AS ROW_COUNT FROM DOCTORS")
    sql_statements.append("UNION ALL SELECT 'PATIENTS', COUNT(*) FROM PATIENTS")
    sql_statements.append("UNION ALL SELECT 'VISITS', COUNT(*) FROM VISITS")
    sql_statements.append("UNION ALL SELECT 'LAB_RESULTS', COUNT(*) FROM LAB_RESULTS")
    sql_statements.append("UNION ALL SELECT 'DIAGNOSTIC_REPORTS', COUNT(*) FROM DIAGNOSTIC_REPORTS")
    sql_statements.append("UNION ALL SELECT 'PRESCRIPTIONS', COUNT(*) FROM PRESCRIPTIONS")
    sql_statements.append("UNION ALL SELECT 'CLINICAL_NOTES', COUNT(*) FROM CLINICAL_NOTES")
    sql_statements.append("UNION ALL SELECT 'INSURANCE_CLAIMS', COUNT(*) FROM INSURANCE_CLAIMS")
    sql_statements.append("UNION ALL SELECT 'DIAGNOSTIC_CENTERS', COUNT(*) FROM DIAGNOSTIC_CENTERS;")
    
    output_file = 'load_all_data.sql'
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write('\n'.join(sql_statements))
    
    print(f"\n✓ Generated {output_file}")
    return output_file

def main():
    """Main execution"""
    print("=" * 80)
    print("PATIENT360 DATA LOADER")
    print("=" * 80)
    print("This script generates SQL files to load all data into PATIENT360.RAW schema")
    print("including CSV data, images, and PDFs\n")
    
    try:
        # Generate SQL files
        csv_file = generate_csv_load_sql()
        files_file = generate_file_load_sql()
        master_file = generate_master_script()
        
        print("\n" + "=" * 80)
        print("SUMMARY")
        print("=" * 80)
        print(f"✓ Generated 3 SQL files:")
        print(f"  1. {csv_file} - Loads all CSV data into tables")
        print(f"  2. {files_file} - Creates stages and uploads images/PDFs")
        print(f"  3. {master_file} - Verification queries")
        
        print("\n📋 NEXT STEPS:")
        print("  1. Execute load_csv_data.sql to load CSV data")
        print("  2. Execute load_files.sql to create stages")
        print("  3. Use SnowSQL or Snowflake CLI to run the PUT commands")
        print("     for uploading images and PDFs")
        
    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == '__main__':
    main()
