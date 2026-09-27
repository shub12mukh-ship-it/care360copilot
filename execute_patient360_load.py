import csv
from pathlib import Path

import snowflake.connector


ACCOUNT = "JRMWQMS-PA19066"
USER = "sreejaprabakar"
WAREHOUSE = "CARE360_WH"
DATABASE = "PATIENT360"
SCHEMA = "RAW"


TABLES = [
    {
        "csv": "doctors.csv",
        "table": "DOCTORS",
        "columns": [
            "DOCTOR_ID", "FIRST_NAME", "LAST_NAME", "SPECIALTY", "SUB_SPECIALTY",
            "YEARS_EXPERIENCE", "MEDICAL_SCHOOL", "BOARD_CERTIFIED", "PHONE", "EMAIL", "LICENSE_NUMBER",
        ],
    },
    {
        "csv": "diagnostic_centers.csv",
        "table": "DIAGNOSTIC_CENTERS",
        "columns": [
            "CENTER_ID", "CENTER_NAME", "ADDRESS", "CITY", "STATE", "ZIP_CODE",
            "PHONE", "SERVICES_OFFERED", "ACCREDITATION", "OPERATING_HOURS",
        ],
    },
    {
        "csv": "patients.csv",
        "table": "PATIENTS",
        "columns": [
            "PATIENT_ID", "FIRST_NAME", "LAST_NAME", "DATE_OF_BIRTH", "AGE", "GENDER",
            "ETHNICITY", "BLOOD_TYPE", "ADDRESS", "CITY", "STATE", "ZIP_CODE", "PHONE",
            "EMAIL", "EMERGENCY_CONTACT_NAME", "EMERGENCY_CONTACT_PHONE",
            "INSURANCE_PROVIDER", "INSURANCE_POLICY_NUMBER",
        ],
    },
    {
        "csv": "visits.csv",
        "table": "VISITS",
        "columns": [
            "VISIT_ID", "PATIENT_ID", "DOCTOR_ID", "VISIT_DATE", "VISIT_TIME",
            "VISIT_TYPE", "CHIEF_COMPLAINT", "DIAGNOSIS_CODE", "DIAGNOSIS_DESCRIPTION",
            "TREATMENT_PLAN", "FOLLOW_UP_REQUIRED", "FOLLOW_UP_DATE", "NOTES",
        ],
    },
    {
        "csv": "lab_results.csv",
        "table": "LAB_RESULTS",
        "columns": [
            "LAB_RESULT_ID", "PATIENT_ID", "VISIT_ID", "CENTER_ID", "TEST_DATE",
            "TEST_TYPE", "TEST_CODE", "PDF_FILENAME", "ORDERED_BY_DOCTOR_ID",
            "STATUS", "CRITICAL_FLAG",
        ],
    },
    {
        "csv": "diagnostic_reports.csv",
        "table": "DIAGNOSTIC_REPORTS",
        "columns": [
            "REPORT_ID", "PATIENT_ID", "VISIT_ID", "CENTER_ID", "EXAM_DATE",
            "EXAM_TYPE", "MODALITY", "BODY_PART", "IMAGE_FILENAME", "FINDINGS",
            "IMPRESSION", "RADIOLOGIST_NAME", "CRITICAL_FINDING",
        ],
    },
    {
        "csv": "insurance_claims.csv",
        "table": "INSURANCE_CLAIMS",
        "columns": [
            "CLAIM_ID", "PATIENT_ID", "VISIT_ID", "CLAIM_DATE", "INSURANCE_PROVIDER",
            "POLICY_NUMBER", "PROCEDURE_CODE", "PROCEDURE_DESCRIPTION", "DIAGNOSIS_CODE",
            "BILLED_AMOUNT", "ALLOWED_AMOUNT", "PATIENT_RESPONSIBILITY", "INSURANCE_PAID",
            "CLAIM_STATUS", "CLAIM_STATUS_DATE", "DENIAL_REASON",
        ],
    },
    {
        "csv": "prescriptions.csv",
        "table": "PRESCRIPTIONS",
        "columns": [
            "PRESCRIPTION_ID", "PATIENT_ID", "VISIT_ID", "DOCTOR_ID", "PRESCRIPTION_DATE",
            "MEDICATION_NAME", "NDC_CODE", "DOSAGE", "FREQUENCY", "DURATION", "REFILLS",
            "PDF_FILENAME",
        ],
    },
    {
        "csv": "clinical_notes.csv",
        "table": "CLINICAL_NOTES",
        "columns": [
            "NOTE_ID", "PATIENT_ID", "VISIT_ID", "DOCTOR_ID", "NOTE_DATE",
            "NOTE_TYPE", "PDF_FILENAME", "SUMMARY",
        ],
    },
]


def get_connection():
    return snowflake.connector.connect(
        account=ACCOUNT,
        user=USER,
        authenticator="externalbrowser",
        warehouse=WAREHOUSE,
        database=DATABASE,
        schema=SCHEMA,
    )


def parse_value(raw_value):
    if raw_value is None or raw_value == "":
        return None
    lowered = raw_value.lower()
    if lowered == "true":
        return True
    if lowered == "false":
        return False
    return raw_value


def load_csv_table(cursor, table_info):
    csv_path = Path("synthetic-healthcare-data") / "csv" / table_info["csv"]
    with csv_path.open("r", encoding="utf-8", newline="") as file_obj:
        reader = csv.DictReader(file_obj)
        rows = list(reader)

    csv_columns_lower = {column.lower(): column for column in reader.fieldnames or []}
    ordered_rows = []
    for row in rows:
        ordered_rows.append(
            tuple(parse_value(row.get(csv_columns_lower.get(column.lower(), ""))) for column in table_info["columns"])
        )

    cursor.execute(f"DELETE FROM {table_info['table']}")

    placeholders = ",".join(["%s"] * len(table_info["columns"]))
    column_list = ",".join(table_info["columns"])
    insert_sql = f"INSERT INTO {table_info['table']} ({column_list}) VALUES ({placeholders})"
    cursor.executemany(insert_sql, ordered_rows)
    print(f"Loaded {len(ordered_rows)} rows into {table_info['table']}")


def upload_pattern(cursor, relative_pattern, stage_name):
    absolute_pattern = (Path.cwd() / relative_pattern).as_posix()
    put_sql = f"PUT file://{absolute_pattern} @{stage_name} AUTO_COMPRESS=FALSE OVERWRITE=TRUE"
    cursor.execute(put_sql)
    results = cursor.fetchall()
    print(f"Uploaded {len(results)} files to {stage_name} from {relative_pattern}")


def verify_counts(cursor):
    print("\nTable counts:")
    for table_info in TABLES:
        cursor.execute(f"SELECT COUNT(*) FROM {table_info['table']}")
        count = cursor.fetchone()[0]
        print(f"  {table_info['table']}: {count}")

    print("\nStage counts:")
    for stage_name in ["DIAGNOSTIC_IMAGES", "LAB_RESULT_PDFS", "PRESCRIPTION_PDFS", "CLINICAL_NOTE_PDFS"]:
        cursor.execute(f"LIST @{stage_name}")
        count = len(cursor.fetchall())
        print(f"  {stage_name}: {count}")


def main():
    connection = get_connection()
    try:
        cursor = connection.cursor()
        cursor.execute(f"USE DATABASE {DATABASE}")
        cursor.execute(f"USE SCHEMA {SCHEMA}")

        for table_info in TABLES:
            load_csv_table(cursor, table_info)

        upload_pattern(cursor, Path("synthetic-healthcare-data") / "images" / "*.png", "DIAGNOSTIC_IMAGES")
        upload_pattern(cursor, Path("synthetic-healthcare-data") / "images" / "*.jpg", "DIAGNOSTIC_IMAGES")
        upload_pattern(cursor, Path("synthetic-healthcare-data") / "pdfs" / "lab_results" / "*.pdf", "LAB_RESULT_PDFS")
        upload_pattern(cursor, Path("synthetic-healthcare-data") / "pdfs" / "prescriptions" / "*.pdf", "PRESCRIPTION_PDFS")
        upload_pattern(cursor, Path("synthetic-healthcare-data") / "pdfs" / "clinical_notes" / "*.pdf", "CLINICAL_NOTE_PDFS")

        verify_counts(cursor)
    finally:
        connection.close()


if __name__ == "__main__":
    main()