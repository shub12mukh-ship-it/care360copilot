import csv
from pathlib import Path


TABLES = [
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


def escape_sql(value):
    if value is None or value == "":
        return "NULL"
    lowered = value.lower()
    if lowered == "true":
        return "TRUE"
    if lowered == "false":
        return "FALSE"
    if value.isdigit() or (value.count(".") == 1 and value.replace(".", "", 1).isdigit()):
        return value
    return "'" + value.replace("'", "''") + "'"


def main():
    input_dir = Path("synthetic-healthcare-data") / "csv"
    output_dir = Path("sql_batches")
    output_dir.mkdir(exist_ok=True)

    for table_info in TABLES:
        csv_path = input_dir / table_info["csv"]
        with csv_path.open("r", encoding="utf-8", newline="") as file_obj:
            reader = csv.DictReader(file_obj)
            rows = list(reader)
            csv_columns_lower = {column.lower(): column for column in reader.fieldnames or []}

        values = []
        for row in rows:
            current = []
            for column in table_info["columns"]:
                source_column = csv_columns_lower.get(column.lower())
                current.append(escape_sql(row.get(source_column) if source_column else None))
            values.append("(" + ",".join(current) + ")")

        sql_text = []
        sql_text.append(f"DELETE FROM PATIENT360.RAW.{table_info['table']};")
        sql_text.append(
            f"INSERT INTO PATIENT360.RAW.{table_info['table']} ({','.join(table_info['columns'])}) VALUES\n"
            + ",\n".join(values)
            + ";"
        )

        output_path = output_dir / f"{table_info['table'].lower()}.sql"
        output_path.write_text("\n".join(sql_text), encoding="utf-8")
        print(f"Wrote {output_path}")


if __name__ == "__main__":
    main()