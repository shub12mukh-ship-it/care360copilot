"""
Load Patient360 synthetic healthcare data from CSV files to Snowflake
Uses Snowflake Python connector to insert data directly
"""

import pandas as pd
import snowflake.connector
from pathlib import Path
import sys

# Connection parameters (using default connection)
# The connection will use credentials from the active Snowflake session

def get_connection():
    """Get Snowflake connection from environment"""
    try:
        import os
        # Use the snowflake-python-connector to get connection
        conn = snowflake.connector.connect(
            account=os.environ.get('SNOWFLAKE_ACCOUNT', 'JRMWQMS-PA19066'),
            user=os.environ.get('SNOWFLAKE_USER', 'sreejaprabakar'),
            authenticator='externalbrowser',  # Use SSO
            warehouse='CARE360_WH',
            database='PATIENT360',
            schema='RAW'
        )
        return conn
    except Exception as e:
        print(f"Connection error: {e}")
        print("Using SQL execute approach instead...")
        return None

def escape_sql(val):
    """Escape single quotes for SQL"""
    if pd.isna(val):
        return 'NULL'
    return "'" + str(val).replace("'", "''") + "'"

def load_table_from_csv(csv_path, table_name, columns):
    """Load a CSV file into a Snowflake table using multi-value INSERT"""
    print(f"\nLoading {table_name} from {csv_path}...")
    
    df = pd.read_csv(csv_path)
    print(f"  Found {len(df)} rows")
    
    # Generate SQL file with batched INSERTs
    sql_file = f"load_{table_name.lower()}.sql"
    
    with open(sql_file, 'w', encoding='utf-8') as f:
        # Write DELETE statement first
        f.write(f"DELETE FROM PATIENT360.RAW.{table_name};\n\n")
        
        # Batch size of 100 rows per INSERT
        batch_size = 100
        for i in range(0, len(df), batch_size):
            batch = df.iloc[i:i+batch_size]
            values = []
            
            for _, row in batch.iterrows():
                # Build value tuple
                val_parts = []
                for col in columns:
                    if col in df.columns:
                        val = row[col]
                        if pd.isna(val):
                            val_parts.append('NULL')
                        elif isinstance(val, (int, float)) and not pd.isna(val):
                            val_parts.append(str(val))
                        elif isinstance(val, bool):
                            val_parts.append('TRUE' if val else 'FALSE')
                        else:
                            val_parts.append(escape_sql(val))
                    else:
                        val_parts.append('NULL')  # Column doesn't exist in CSV
                
                values.append(f"({','.join(val_parts)})")
            
            # Write INSERT statement
            col_list = ','.join(columns)
            f.write(f"INSERT INTO PATIENT360.RAW.{table_name} ({col_list}) VALUES\n")
            f.write(',\n'.join(values))
            f.write(';\n\n')
    
    print(f"  Generated {sql_file}")
    return sql_file

def main():
    """Main loading script"""
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
    
    sql_files = []
    for table_info in tables:
        csv_path = base_path / table_info['csv']
        if not csv_path.exists():
            print(f"WARNING: {csv_path} not found, skipping...")
            continue
        
        sql_file = load_table_from_csv(csv_path, table_info['table'], table_info['columns'])
        sql_files.append(sql_file)
    
    print(f"\n✓ Generated {len(sql_files)} SQL files")
    print("\nTo load data, execute these SQL files in Snowflake in order:")
    for i, sql_file in enumerate(sql_files, 1):
        print(f"  {i}. {sql_file}")
    
    print("\nOr concatenate them all:")
    print("  cat load_*.sql > load_all_data.sql")

if __name__ == '__main__':
    main()
