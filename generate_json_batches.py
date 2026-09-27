import csv
import json
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


def normalize_value(raw_value):
    if raw_value is None or raw_value == "":
        return None
    lowered = raw_value.lower()
    if lowered == "true":
        return True
    if lowered == "false":
        return False
    if raw_value.isdigit() or (raw_value.count(".") == 1 and raw_value.replace(".", "", 1).isdigit()):
        if "." in raw_value:
            return float(raw_value)
        return int(raw_value)
    return raw_value


def main():
    output_dir = Path("json_batches")
    output_dir.mkdir(exist_ok=True)
    base_path = Path("synthetic-healthcare-data") / "csv"

    for table in TABLES:
        csv_path = base_path / table["csv"]
        with csv_path.open("r", encoding="utf-8", newline="") as file_obj:
            reader = csv.DictReader(file_obj)
            rows = list(reader)
            column_map = {column.lower(): column for column in reader.fieldnames or []}

        normalized_rows = []
        for row in rows:
            normalized_rows.append(
                {
                    column: normalize_value(row.get(column_map.get(column.lower(), "")))
                    for column in table["columns"]
                }
            )

        output_path = output_dir / f"{table['table'].lower()}.json"
        output_path.write_text(json.dumps(normalized_rows, ensure_ascii=True), encoding="utf-8")
        print(f"Wrote {len(normalized_rows)} rows to {output_path}")


if __name__ == "__main__":
    main()