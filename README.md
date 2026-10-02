# Synthetic Healthcare Datasets

High-quality synthetic healthcare data generated for Care360 Copilot testing and development. This dataset includes realistic medical records, diagnostic reports, lab results, prescriptions, and clinical documentation following industry-standard medical coding systems.

## Business Problem Statement

Healthcare organizations struggle with fragmented patient data spread across EHRs, claims systems, lab platforms, and clinical documents. Clinicians, care coordinators, and compliance teams spend significant time manually piecing together patient histories from these disconnected sources.

Core challenges:

- **Data silos**: structured records (labs, medications, claims) live in separate systems from unstructured clinical notes.
- **Time-to-insight**: clinicians spend 15-30 minutes per patient assembling a longitudinal view before making care decisions.
- **Evidence gaps**: regulatory and quality teams cannot quickly trace clinical decisions back to supporting documentation.
- **Safety risk**: incomplete views lead to missed drug interactions, duplicate tests, and gaps in care continuity.

**What this system does**: a Snowflake-native copilot that unifies structured healthcare records with clinical documents, so natural-language questions are answered with cited evidence drawn from the patient record.

**What this system does not do**: it does not diagnose conditions, does not suggest therapy choices, does not forecast patient trajectories, and does not substitute for clinician judgement. It operates on synthetic data only and contains no identifiable patient information. Every answer must cite its source record, and the system refuses questions it cannot support with retrieved evidence.

See `docs/architecture.md` for the full architecture and `.specify/memory/constitution.md` for the governing principles.

## Target Users

| Persona | Role | Primary Use Cases |
|---------|------|-------------------|
| Primary Care Physician | Reviews patient records, coordinates care, and manages specialist follow-up | "Summarize this patient's recent visits and test results" / "What chronic conditions does this patient have?" |
| Claims Analyst | Reviews insurance claims and identifies billing, coverage, and documentation issues | "What is the status of recent claims for this patient?" / "Which claims were denied and why?" |
| Patient | Views their own health information and care history, including alerts and recent visits | "What medications am I currently taking?" / "When is my next appointment?" |
| Clinical Pharmacist | Reviews medication safety and interactions, including active prescriptions and indications | "What labs were ordered before starting this medication?" / "Show all active prescriptions and their indications" |

Requirements common to all personas:

- Answers must cite the source record (table, document, date).
- No unsupported medical conclusions may be inferred.
- Interactive responses should remain under 10 seconds.
- The architecture must stay compatible with future role-based access and row-level security by care team.

## 📊 Dataset Overview

### Generated Datasets (9 CSV files + Supporting Documents)

| Dataset | Records | Description |
|---------|---------|-------------|
| **doctors.csv** | 50 | Healthcare providers (25 specialists, 25 general practitioners) |
| **diagnostic_centers.csv** | 10 | Diagnostic facilities with varied service offerings |
| **patients.csv** | 100 | Patient demographics (ages 3-88, realistic distributions) |
| **visits.csv** | 572 | Patient-doctor encounters with ICD-10 diagnoses |
| **lab_results.csv** | 317 | Laboratory test metadata with LOINC codes |
| **diagnostic_reports.csv** | 178 | Imaging study metadata (MRI, CT, X-Ray, Angiogram) |
| **insurance_claims.csv** | 572 | Insurance claims with CPT procedure codes |
| **prescriptions.csv** | 582 | Medication prescriptions with NDC codes |
| **clinical_notes.csv** | 846 | Clinical documentation (SOAP notes, lifestyle recommendations, PT notes) |

### Supporting Documents

- **Lab Result PDFs**: 266 files (blood test reports with results tables)
- **Prescription PDFs**: 582 files (pharmacy-ready Rx documents)
- **Clinical Note PDFs**: 846 files (SOAP format clinical documentation)
- **Diagnostic Images**: 178 PNG files (placeholder medical images with overlays)

## 🏥 Medical Coding Standards

This dataset uses industry-standard medical coding systems:

- **ICD-10-CM**: International Classification of Diseases (diagnosis codes)
- **CPT**: Current Procedural Terminology (procedure codes)
- **LOINC**: Logical Observation Identifiers Names and Codes (lab test codes)
- **NDC**: National Drug Codes (medication identifiers)

## 📁 Directory Structure

```
synthetic-healthcare-data/
├── csv/
│   ├── doctors.csv
│   ├── diagnostic_centers.csv
│   ├── patients.csv
│   ├── visits.csv
│   ├── lab_results.csv
│   ├── diagnostic_reports.csv
│   ├── insurance_claims.csv
│   ├── prescriptions.csv
│   └── clinical_notes.csv
├── pdfs/
│   ├── lab_results/       # 266 blood test reports
│   ├── prescriptions/     # 582 prescription documents
│   └── clinical_notes/    # 846 clinical documentation PDFs
└── images/                # 178 diagnostic images (MRI, CT, X-Ray, Angiogram)
```

## 🔍 Data Quality Features

✅ **100% Referential Integrity**: All foreign keys are valid  
✅ **Temporal Consistency**: Birth dates < visit dates < test dates  
✅ **Medical Code Compliance**: Valid ICD-10, CPT, LOINC, NDC formats  
✅ **Age Distribution**: 10% pediatric (3-17), 60% adult (18-64), 30% elderly (65-88)  
✅ **Realistic Distributions**: 80% claim approval rate, age-appropriate diagnoses  
✅ **File Integrity**: All referenced PDFs and images exist on disk  

## 📖 Data Schema

### doctors.csv
- `doctor_id`: Unique identifier (D00001-D00050)
- `first_name`, `last_name`: Provider name
- `specialty`: Medical specialty (Cardiology, Family Medicine, etc.)
- `sub_specialty`: Detailed specialization
- `years_experience`: 5-40 years
- `medical_school`: Accredited institution
- `board_certified`: Boolean
- `phone`, `email`: Contact information
- `license_number`: Medical license (MD########)

### diagnostic_centers.csv
- `center_id`: Unique identifier (DC001-DC010)
- `center_name`: Facility name
- `address`, `city`, `state`, `zip_code`: Location
- `phone`: Contact number
- `services_offered`: Comma-separated services (MRI, CT, X-Ray, Blood Tests, etc.)
- `accreditation`: ACR, CAP, CLIA, or Joint Commission
- `operating_hours`: Business hours

### patients.csv
- `patient_id`: Unique identifier (P00001-P00100)
- `first_name`, `last_name`: Patient name
- `date_of_birth`: YYYY-MM-DD format
- `age`: Current age (3-88)
- `gender`: Male, Female, Non-binary
- `ethnicity`: Demographic information
- `blood_type`: A+, A-, B+, B-, AB+, AB-, O+, O-
- `address`, `city`, `state`, `zip_code`: Residential location
- `phone`, `email`: Contact information
- `emergency_contact_name`, `emergency_contact_phone`: Emergency contacts
- `insurance_provider`: Insurance company name
- `insurance_policy_number`: Policy identifier

### visits.csv
- `visit_id`: Unique identifier (V000001-V000572)
- `patient_id`: Foreign key to patients
- `doctor_id`: Foreign key to doctors
- `visit_date`: YYYY-MM-DD (2022-2026 range)
- `visit_time`: HH:MM:SS (business hours)
- `visit_type`: Routine, Urgent Care, Follow-up, Specialist Consultation
- `chief_complaint`: Primary reason for visit
- `diagnosis_code`: ICD-10 code
- `diagnosis_description`: Human-readable diagnosis
- `treatment_plan`: Care instructions
- `follow_up_required`: Boolean
- `follow_up_date`: Next appointment (if applicable)
- `notes`: Additional clinical observations

### lab_results.csv
- `lab_result_id`: Unique identifier (LR000001-LR000317)
- `patient_id`: Foreign key to patients
- `visit_id`: Foreign key to visits
- `center_id`: Foreign key to diagnostic_centers
- `test_date`: YYYY-MM-DD (within 7 days of visit)
- `test_type`: CBC, Lipid Panel, Glucose, Comprehensive Metabolic Panel, etc.
- `test_code`: LOINC code
- `pdf_filename`: Reference to lab report PDF
- `ordered_by_doctor_id`: Foreign key to doctors
- `status`: Completed, Pending, Cancelled
- `critical_flag`: Boolean (abnormal results)

### diagnostic_reports.csv
- `report_id`: Unique identifier (DR000001-DR000178)
- `patient_id`: Foreign key to patients
- `visit_id`: Foreign key to visits
- `center_id`: Foreign key to diagnostic_centers
- `exam_date`: YYYY-MM-DD (within 14 days of visit)
- `exam_type`: MRI, CT, X-Ray, Angiogram
- `modality`: Same as exam_type
- `body_part`: Anatomical region studied
- `image_filename`: Reference to PNG image
- `findings`: Radiologist observations
- `impression`: Clinical summary
- `radiologist_name`: Interpreting physician
- `critical_finding`: Boolean

### insurance_claims.csv
- `claim_id`: Unique identifier (CL000001-CL000572)
- `patient_id`: Foreign key to patients
- `visit_id`: Foreign key to visits
- `claim_date`: YYYY-MM-DD
- `insurance_provider`: Insurance company
- `policy_number`: Patient's policy
- `procedure_code`: CPT code
- `procedure_description`: Human-readable procedure
- `diagnosis_code`: ICD-10 code (same as visit)
- `billed_amount`: Provider charge ($)
- `allowed_amount`: Insurance-approved amount ($)
- `patient_responsibility`: Patient's cost share ($)
- `insurance_paid`: Insurance payment ($)
- `claim_status`: Approved, Partially Approved, Denied, Pending
- `claim_status_date`: Status determination date
- `denial_reason`: Reason if denied

### prescriptions.csv
- `prescription_id`: Unique identifier (RX000001-RX000582)
- `patient_id`: Foreign key to patients
- `visit_id`: Foreign key to visits
- `doctor_id`: Foreign key to doctors
- `prescription_date`: YYYY-MM-DD (same as visit)
- `medication_name`: Drug name
- `ndc_code`: National Drug Code (5-4-2 format)
- `dosage`: Strength (e.g., "10 mg")
- `frequency`: How often (e.g., "Once daily")
- `duration`: Supply length (e.g., "90 days")
- `refills`: Number of refills allowed (0-6)
- `pdf_filename`: Reference to prescription PDF

### clinical_notes.csv
- `note_id`: Unique identifier (CN000001-CN000846)
- `patient_id`: Foreign key to patients
- `visit_id`: Foreign key to visits
- `doctor_id`: Foreign key to doctors
- `note_date`: YYYY-MM-DD (same as visit)
- `note_type`: Clinical Note, Lifestyle Recommendation, Physiotherapy Note
- `pdf_filename`: Reference to PDF document
- `summary`: Brief description

## 🧭 Patient360 Curation Direction

This repository now treats `PATIENT360` as the canonical database target for all
forward-looking curation, semantic-view, and application work.

- Raw synthetic healthcare assets under `synthetic-healthcare-data/` are the source layer.
- Curation logic is defined in `sql/patient360_curation.sql`.
- Semantic-view candidate summaries are defined in `sql/patient360_semantic_prep.sql`.
- Validation scenarios for curated entities, persona workflows, and evidence assets are
  documented in `docs/testing.md`.
- Legacy `CARE360_DB` references are migration debt and must not be copied into new work.

The intended application flow is:
1. load or expose raw synthetic assets in `PATIENT360.RAW`
2. build patient-centered curated entities in `PATIENT360.CURATED`
3. expose semantic-view candidate summaries in `PATIENT360.ANALYTICS`
4. use those business-facing entities for a future Streamlit and semantic-view experience

## 🚀 Usage

### Prerequisites

```bash
pip install pandas faker reportlab Pillow
```

### Generate New Datasets

```bash
python generate_synthetic_healthcare_data.py --seed 42 --output-dir synthetic-healthcare-data
```

**Parameters:**
- `--seed`: Random seed for reproducibility (default: 42)
- `--output-dir`: Output directory (default: synthetic-healthcare-data)
- `--doctors`: Number of doctors (default: 50)
- `--specialists`: Number of specialist doctors (default: 25)
- `--centers`: Number of diagnostic centers (default: 10)
- `--patients`: Number of patients (default: 100)

### Validate Data Quality

```bash
python validate_synthetic_data.py --data-dir synthetic-healthcare-data
```

The validation script checks:
- ✅ Record counts match specifications
- ✅ Referential integrity (all foreign keys valid)
- ✅ Temporal consistency (date logic)
- ✅ Medical code formats (ICD-10, CPT, LOINC, NDC)
- ✅ File existence (all PDFs and images present)
- ✅ Business rules (claim amounts, distributions)

### Load Data in Python

```python
import pandas as pd

# Load CSV datasets
doctors_df = pd.read_csv('synthetic-healthcare-data/csv/doctors.csv')
patients_df = pd.read_csv('synthetic-healthcare-data/csv/patients.csv')
visits_df = pd.read_csv('synthetic-healthcare-data/csv/visits.csv')

# Example: Find all visits for a specific patient
patient_visits = visits_df[visits_df['patient_id'] == 'P00001']

# Example: Count visits by specialty
visit_specialty = visits_df.merge(doctors_df, on='doctor_id')
specialty_counts = visit_specialty['specialty'].value_counts()

# Example: Calculate average claim amount by status
avg_claim = claims_df.groupby('claim_status')['billed_amount'].mean()
```

### Example Queries

#### Find high-risk patients (multiple recent visits)
```python
recent_visits = visits_df[visits_df['visit_date'] >= '2025-01-01']
high_risk = recent_visits.groupby('patient_id').size().sort_values(ascending=False).head(10)
```

#### Analyze lab test utilization by center
```python
lab_by_center = lab_results_df.merge(centers_df, on='center_id')
utilization = lab_by_center.groupby('center_name')['test_type'].value_counts()
```

#### Calculate insurance claim denial rate
```python
denial_rate = (claims_df['claim_status'] == 'Denied').sum() / len(claims_df) * 100
print(f"Denial Rate: {denial_rate:.1f}%")
```

## 📊 Sample Data Statistics

- **Visit Frequency**: Average 5.72 visits per patient
- **Lab Test Coverage**: ~55% of visits have lab tests
- **Imaging Studies**: ~31% of visits have diagnostic imaging
- **Prescription Rate**: ~65% of visits result in prescriptions
- **Clinical Documentation**: 100% of visits have clinical notes
- **Claim Approval Rate**: ~80% approved, ~15% partial, ~5% denied

## 🔒 Privacy & Compliance

⚠️ **IMPORTANT**: This is **SYNTHETIC DATA ONLY**. All information is computer-generated and does not represent real individuals, medical facilities, or healthcare events.

- ✅ No real patient information (HIPAA compliant synthetic data)
- ✅ Generated using Faker library with random seeds
- ✅ Safe for development, testing, and demonstration purposes
- ✅ No personally identifiable information (PII)

## 📝 Use Cases

This synthetic dataset is designed for:

1. **Healthcare Application Development**: Test patient portals, EHR systems, analytics platforms
2. **Machine Learning Model Training**: Predictive models, risk stratification, NLP on clinical notes
3. **Data Pipeline Testing**: ETL workflows, data warehouse loading, integration testing
4. **Healthcare Analytics**: Dashboard development, reporting, visualization
5. **Education & Training**: Learn healthcare data standards, practice SQL queries, data analysis
6. **Demo & Proof of Concept**: Sales demos, pilot projects, stakeholder presentations

## 🛠️ Customization

Modify `generate_synthetic_healthcare_data.py` to adjust:

- Medical specialties and procedures
- Diagnosis codes (ICD-10) and their frequencies
- Lab tests (LOINC codes) and reference ranges
- Medications (NDC codes) and dosages
- Visit patterns and temporal distributions
- Document templates (PDF layouts)

## 📚 References

- **ICD-10-CM**: https://www.cdc.gov/nchs/icd/icd-10-cm.htm
- **CPT Codes**: https://www.ama-assn.org/practice-management/cpt
- **LOINC**: https://loinc.org/
- **NDC**: https://www.fda.gov/drugs/drug-approvals-and-databases/national-drug-code-directory

## 🤝 Contributing

To improve data quality or add new features:

1. Modify generation scripts in `generate_synthetic_healthcare_data.py`
2. Update validation checks in `validate_synthetic_data.py`
3. Test with different random seeds to ensure consistency
4. Document changes in this README

## 📄 License

This synthetic dataset is provided as-is for testing and development purposes. The generation scripts use open-source libraries (Faker, Pandas, ReportLab, Pillow) which have their own licenses.

---

**Generated**: September 2026  
**Version**: 1.0  
**Contact**: Care360 Copilot Team
