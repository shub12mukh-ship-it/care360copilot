# Implementation Plan: Synthetic Healthcare Datasets

**Feature Directory**: `specs/001-synthetic-healthcare-datasets`

**Created**: 2026-09-25

**Status**: Draft

## Executive Summary

This plan outlines the approach for creating high-quality synthetic healthcare datasets for a patient management system. The datasets will include doctors, diagnostic centers, patients, visits, lab results, diagnostic reports, insurance claims, and clinical documentation.

## Technical Context

### Dataset Requirements

**Doctors Dataset (50 records - 25 specialists)**
- 50 total doctors with diverse specializations
- 25 specialists covering major specialties (Cardiology, Neurology, Orthopedics, etc.)
- 25 general practitioners
- Realistic distribution across experience levels and demographics

**Diagnostic Centers (10 records)**
- 10 diagnostic facilities with varied capabilities
- Different service offerings (MRI, CT, X-Ray, Angiogram, blood tests)
- Geographic distribution considerations

**Patients (100 records)**
- Age range: 3 to 88 years
- Diverse demographics (gender, ethnicity, socioeconomic factors)
- Realistic health profiles correlated with age groups

**Visits Dataset**
- Patient-doctor interactions
- Visit types (routine checkup, emergency, follow-up, specialist consultation)
- Temporal distribution over multiple years
- Diagnoses and treatment plans

**Lab Results (Blood Reports - PDFs)**
- CSV metadata file pointing to PDF files
- Common blood tests (CBC, lipid panel, glucose, liver function, kidney function)
- Age-appropriate and condition-appropriate values
- Normal and abnormal results with clinical context

**Diagnostic Reports (Images - PNGs)**
- CSV metadata file linking to image files
- MRI, X-Ray, CT scan, Angiogram images
- Synthetic medical images or placeholders with detailed metadata
- Associated findings and interpretations

**Insurance Claims (CSV)**
- Claim details linked to visits
- CPT codes, ICD-10 codes
- Claim amounts, approvals, denials, and adjustments
- Insurance provider information

**Clinical Documentation (Unstructured PDFs)**
- Prescriptions with medication details
- Clinical notes (SOAP format)
- Lifestyle recommendations
- Physiotherapy plans and progress notes
- Free-text format mimicking real clinical documentation

### Data Quality Requirements

1. **Referential Integrity**: All foreign keys must reference valid primary keys
2. **Realistic Distributions**: Age, gender, disease prevalence should match real-world patterns
3. **Temporal Consistency**: Dates must be logically ordered (birth < visit < lab test)
4. **Clinical Plausibility**: Diagnoses, treatments, and test results must be medically coherent
5. **Privacy Compliance**: All data must be synthetic with no real patient information

### Technology Choices

**Python with Faker Library**
- Primary tool for generating synthetic structured data
- Custom providers for medical terminology and codes
- Random seed control for reproducibility

**ReportLab or FPDF**
- PDF generation for lab results and clinical notes
- Template-based approach for consistency

**Pillow (PIL) or Synthetic Image Libraries**
- Generate placeholder medical images with appropriate dimensions
- Or use openly available synthetic medical imaging datasets

**Pandas**
- Data manipulation and CSV export
- Data quality validation

## Phase 0: Research & Design Decisions

### Research Topics

#### 1. Medical Coding Standards
**Research needed**: Standard code sets for healthcare data

**Key findings**:
- **ICD-10-CM**: Diagnosis codes (e.g., E11.9 for Type 2 Diabetes)
- **CPT**: Procedure codes (e.g., 99213 for office visit)
- **LOINC**: Lab test codes (e.g., 2339-0 for Glucose)
- **SNOMED CT**: Clinical terminology
- **NDC**: National Drug Codes for medications

**Decision**: Use ICD-10-CM for diagnoses, CPT for procedures, LOINC for lab tests, and NDC for prescriptions.

**Rationale**: These are standard codes used in US healthcare systems and provide realistic data structure.

#### 2. Data Distribution Patterns
**Research needed**: Realistic distributions for demographics and conditions

**Key findings**:
- Age distribution: US census data patterns (bimodal with peaks in childhood and elderly)
- Disease prevalence: CDC data for common conditions by age group
- Specialist consultation rates: ~15-20% of visits involve specialists
- Lab test frequency: CBC is most common (~30% of tests), followed by comprehensive metabolic panel

**Decision**: Use weighted random distributions based on CDC and census statistics.

**Rationale**: Ensures data reflects real-world healthcare patterns for realistic testing scenarios.

#### 3. Synthetic Medical Image Generation
**Research needed**: Options for generating or sourcing synthetic medical images

**Key findings**:
- **Option A**: Use publicly available synthetic medical imaging datasets (e.g., MedMNIST, synthetic CT scan datasets)
- **Option B**: Generate placeholder images with metadata annotations
- **Option C**: Use GANs or diffusion models to generate synthetic images (complex, time-intensive)

**Decision**: Use Option B - placeholder images with rich metadata.

**Rationale**: 
- No licensing concerns
- Faster implementation
- Metadata is more important than actual image content for system testing
- Can be enhanced later with real synthetic images if needed

#### 4. Clinical Documentation Structure
**Research needed**: Standard formats for clinical notes and prescriptions

**Key findings**:
- **SOAP format**: Subjective, Objective, Assessment, Plan
- **Prescription format**: Patient info, Rx details, sig, refills, prescriber signature
- **Lab report format**: Patient demographics, test details, results with reference ranges, interpretation
- **Physiotherapy notes**: Initial evaluation, treatment plan, progress notes

**Decision**: Use industry-standard formats for each document type with realistic variability.

**Rationale**: Mimics real clinical documentation for accurate system testing.

#### 5. Dataset Relationships and Cardinality
**Research needed**: Realistic relationships between entities

**Key findings**:
- Patient-to-doctor: Many-to-many (patients see multiple doctors over time)
- Patient-to-visit: One-to-many (avg 2-4 visits per year for chronic patients)
- Visit-to-lab: One-to-many (some visits generate multiple lab orders)
- Visit-to-claim: One-to-one or one-to-many (complex visits may have multiple claims)
- Visit-to-prescription: One-to-many (multiple medications per visit)

**Decision**: Use realistic cardinality ratios with some variability.

**Rationale**: Ensures test scenarios cover common and complex relationship patterns.

## Phase 1: Data Model & Contracts

### Entity Relationship Overview

```
Doctors (1) ----< Visits (M) >---- (M) Patients
                    |
                    +----< Lab Results (M)
                    +----< Diagnostic Reports (M)
                    +----< Insurance Claims (M)
                    +----< Prescriptions (M)
                    +----< Clinical Notes (M)

Diagnostic Centers (1) ----< Lab Results / Diagnostic Reports (M)
```

### Data Model Details

#### 1. Doctors Dataset (`doctors.csv`)

**Purpose**: Store physician information and specializations

**Schema**:
```
doctor_id,first_name,last_name,specialty,sub_specialty,years_experience,medical_school,board_certified,phone,email,license_number
```

**Field Definitions**:
- `doctor_id` (INT): Unique identifier, format: D00001-D00050
- `first_name` (VARCHAR): Physician's first name
- `last_name` (VARCHAR): Physician's last name
- `specialty` (VARCHAR): Primary specialty (Cardiology, Neurology, Family Medicine, etc.)
- `sub_specialty` (VARCHAR): Sub-specialization (Interventional Cardiology, Pediatric Neurology, etc.)
- `years_experience` (INT): Years since medical school graduation (5-40 years)
- `medical_school` (VARCHAR): Name of medical school
- `board_certified` (BOOLEAN): TRUE/FALSE
- `phone` (VARCHAR): Office phone number
- `email` (VARCHAR): Professional email
- `license_number` (VARCHAR): State medical license number

**Validation Rules**:
- All IDs must be unique
- Years experience must be >= 0
- Phone numbers must follow US format
- 25 records must have specialty != "Family Medicine" or "General Practice"

#### 2. Diagnostic Centers Dataset (`diagnostic_centers.csv`)

**Purpose**: Store diagnostic facility information

**Schema**:
```
center_id,center_name,address,city,state,zip_code,phone,services_offered,accreditation,operating_hours
```

**Field Definitions**:
- `center_id` (INT): Unique identifier, format: DC001-DC010
- `center_name` (VARCHAR): Facility name
- `address` (VARCHAR): Street address
- `city` (VARCHAR): City name
- `state` (VARCHAR): Two-letter state code
- `zip_code` (VARCHAR): 5-digit ZIP code
- `phone` (VARCHAR): Contact phone number
- `services_offered` (VARCHAR): Comma-separated list (MRI, CT, X-Ray, Ultrasound, Blood Tests, etc.)
- `accreditation` (VARCHAR): Accrediting body (ACR, CAP, CLIA, etc.)
- `operating_hours` (VARCHAR): Business hours

**Validation Rules**:
- All IDs must be unique
- At least 8 centers must offer blood tests
- At least 5 centers must offer MRI
- At least 7 centers must offer X-Ray
- Services offered should vary across centers

#### 3. Patients Dataset (`patients.csv`)

**Purpose**: Store patient demographic and contact information

**Schema**:
```
patient_id,first_name,last_name,date_of_birth,age,gender,ethnicity,blood_type,address,city,state,zip_code,phone,email,emergency_contact_name,emergency_contact_phone,insurance_provider,insurance_policy_number
```

**Field Definitions**:
- `patient_id` (INT): Unique identifier, format: P00001-P00100
- `first_name` (VARCHAR): Patient's first name
- `last_name` (VARCHAR): Patient's last name
- `date_of_birth` (DATE): Birth date (calculated to give ages 3-88)
- `age` (INT): Current age in years (3-88)
- `gender` (VARCHAR): Male, Female, Non-binary
- `ethnicity` (VARCHAR): Caucasian, African American, Hispanic, Asian, Other
- `blood_type` (VARCHAR): A+, A-, B+, B-, AB+, AB-, O+, O-
- `address` (VARCHAR): Street address
- `city`, `state`, `zip_code`: Location information
- `phone` (VARCHAR): Contact number
- `email` (VARCHAR): Email address
- `emergency_contact_name` (VARCHAR): Emergency contact
- `emergency_contact_phone` (VARCHAR): Emergency contact number
- `insurance_provider` (VARCHAR): Insurance company name
- `insurance_policy_number` (VARCHAR): Policy number

**Validation Rules**:
- All IDs must be unique
- Age distribution: 10% pediatric (3-17), 60% adult (18-64), 30% elderly (65-88)
- Gender distribution: ~48% male, ~48% female, ~4% non-binary
- Ethnicity reflects US demographic distribution

#### 4. Visits Dataset (`visits.csv`)

**Purpose**: Record patient-doctor encounters

**Schema**:
```
visit_id,patient_id,doctor_id,visit_date,visit_time,visit_type,chief_complaint,diagnosis_code,diagnosis_description,treatment_plan,follow_up_required,follow_up_date,notes
```

**Field Definitions**:
- `visit_id` (INT): Unique identifier, format: V000001-V999999
- `patient_id` (FK): References patients.patient_id
- `doctor_id` (FK): References doctors.doctor_id
- `visit_date` (DATE): Date of visit (2022-01-01 to 2026-09-25)
- `visit_time` (TIME): Time of visit
- `visit_type` (VARCHAR): Routine, Urgent Care, Emergency, Follow-up, Specialist Consultation
- `chief_complaint` (VARCHAR): Reason for visit
- `diagnosis_code` (VARCHAR): ICD-10 code
- `diagnosis_description` (VARCHAR): Human-readable diagnosis
- `treatment_plan` (TEXT): Brief treatment summary
- `follow_up_required` (BOOLEAN): TRUE/FALSE
- `follow_up_date` (DATE): Scheduled follow-up date if applicable
- `notes` (TEXT): Additional visit notes

**Validation Rules**:
- Patient and doctor IDs must exist
- Visit dates must be logically consistent (after patient birth date)
- Each patient should have 1-10 visits
- Diagnosis codes must be valid ICD-10 codes

#### 5. Lab Results Metadata (`lab_results.csv`)

**Purpose**: Index and describe blood test PDFs

**Schema**:
```
lab_result_id,patient_id,visit_id,center_id,test_date,test_type,test_code,pdf_filename,ordered_by_doctor_id,status,critical_flag
```

**Field Definitions**:
- `lab_result_id` (INT): Unique identifier, format: LR000001-LR999999
- `patient_id` (FK): References patients.patient_id
- `visit_id` (FK): References visits.visit_id
- `center_id` (FK): References diagnostic_centers.center_id
- `test_date` (DATE): Date test was performed
- `test_type` (VARCHAR): CBC, Lipid Panel, Glucose, Liver Function, Kidney Function, etc.
- `test_code` (VARCHAR): LOINC code
- `pdf_filename` (VARCHAR): Filename of PDF report (e.g., LR000001_CBC.pdf)
- `ordered_by_doctor_id` (FK): References doctors.doctor_id
- `status` (VARCHAR): Completed, Pending, Cancelled
- `critical_flag` (BOOLEAN): TRUE if results are critically abnormal

**Validation Rules**:
- All foreign keys must be valid
- Test date must be on or after visit date
- PDF filename must follow naming convention
- 60-70% of tests should be completed with normal results

**PDF Content Structure**:
Each PDF will contain:
- Patient demographics header
- Ordering physician information
- Test name and LOINC code
- Results table with: Test component, Result value, Reference range, Flag (H/L/Critical)
- Interpretation/comments section

#### 6. Diagnostic Reports Metadata (`diagnostic_reports.csv`)

**Purpose**: Index and describe diagnostic imaging files

**Schema**:
```
report_id,patient_id,visit_id,center_id,exam_date,exam_type,modality,body_part,image_filename,findings,impression,radiologist_name,critical_finding
```

**Field Definitions**:
- `report_id` (INT): Unique identifier, format: DR000001-DR999999
- `patient_id` (FK): References patients.patient_id
- `visit_id` (FK): References visits.visit_id
- `center_id` (FK): References diagnostic_centers.center_id
- `exam_date` (DATE): Date of imaging study
- `exam_type` (VARCHAR): MRI, CT, X-Ray, Angiogram
- `modality` (VARCHAR): MRI, CT, Radiography, Angiography
- `body_part` (VARCHAR): Brain, Chest, Abdomen, Extremity, etc.
- `image_filename` (VARCHAR): Filename of PNG image (e.g., DR000001_MRI_Brain.png)
- `findings` (TEXT): Detailed findings description
- `impression` (TEXT): Radiologist's impression/conclusion
- `radiologist_name` (VARCHAR): Name of interpreting radiologist
- `critical_finding` (BOOLEAN): TRUE if urgent findings present

**Validation Rules**:
- All foreign keys must be valid
- Exam date must be on or after visit date
- Image filename must follow naming convention
- Modality and exam type must be consistent

**Image Content**:
- PNG placeholder images (512x512 or 1024x1024 pixels)
- Overlay text with: Patient ID, Exam type, Body part, Date
- Grayscale for X-Ray/CT, colored for other modalities

#### 7. Insurance Claims Dataset (`insurance_claims.csv`)

**Purpose**: Record insurance billing and claims

**Schema**:
```
claim_id,patient_id,visit_id,claim_date,insurance_provider,policy_number,procedure_code,procedure_description,diagnosis_code,billed_amount,allowed_amount,patient_responsibility,insurance_paid,claim_status,claim_status_date,denial_reason
```

**Field Definitions**:
- `claim_id` (INT): Unique identifier, format: CL000001-CL999999
- `patient_id` (FK): References patients.patient_id
- `visit_id` (FK): References visits.visit_id
- `claim_date` (DATE): Date claim was submitted
- `insurance_provider` (VARCHAR): Insurance company name
- `policy_number` (VARCHAR): Patient's policy number
- `procedure_code` (VARCHAR): CPT code
- `procedure_description` (VARCHAR): Human-readable procedure
- `diagnosis_code` (VARCHAR): ICD-10 code (justification)
- `billed_amount` (DECIMAL): Amount billed by provider
- `allowed_amount` (DECIMAL): Insurance-allowed amount
- `patient_responsibility` (DECIMAL): Patient copay/deductible
- `insurance_paid` (DECIMAL): Amount paid by insurance
- `claim_status` (VARCHAR): Approved, Denied, Pending, Partially Approved
- `claim_status_date` (DATE): Date of status determination
- `denial_reason` (VARCHAR): Reason if denied

**Validation Rules**:
- All foreign keys must be valid
- Claim date must be on or after visit date
- billed_amount = insurance_paid + patient_responsibility (for approved claims)
- ~80% of claims should be approved
- ~15% partially approved
- ~5% denied

#### 8. Prescriptions Metadata (`prescriptions.csv`)

**Purpose**: Index prescription PDFs

**Schema**:
```
prescription_id,patient_id,visit_id,doctor_id,prescription_date,medication_name,ndc_code,dosage,frequency,duration,refills,pdf_filename
```

**Field Definitions**:
- `prescription_id` (INT): Unique identifier, format: RX000001-RX999999
- `patient_id` (FK): References patients.patient_id
- `visit_id` (FK): References visits.visit_id
- `doctor_id` (FK): References doctors.doctor_id
- `prescription_date` (DATE): Date prescribed
- `medication_name` (VARCHAR): Medication name (generic)
- `ndc_code` (VARCHAR): National Drug Code
- `dosage` (VARCHAR): Dosage strength (e.g., "500 mg")
- `frequency` (VARCHAR): How often (e.g., "Twice daily")
- `duration` (VARCHAR): How long (e.g., "10 days")
- `refills` (INT): Number of refills authorized
- `pdf_filename` (VARCHAR): Filename of prescription PDF

**Validation Rules**:
- All foreign keys must be valid
- Prescription date must match visit date
- ~60% of visits should generate at least one prescription

#### 9. Clinical Notes Metadata (`clinical_notes.csv`)

**Purpose**: Index clinical documentation PDFs

**Schema**:
```
note_id,patient_id,visit_id,doctor_id,note_date,note_type,pdf_filename,summary
```

**Field Definitions**:
- `note_id` (INT): Unique identifier, format: CN000001-CN999999
- `patient_id` (FK): References patients.patient_id
- `visit_id` (FK): References visits.visit_id (nullable for ongoing therapy notes)
- `doctor_id` (FK): References doctors.doctor_id
- `note_date` (DATE): Date of note
- `note_type` (VARCHAR): Clinical Note, Lifestyle Recommendation, Physiotherapy Note, Progress Note
- `pdf_filename` (VARCHAR): Filename of PDF document
- `summary` (TEXT): Brief summary of note content

**Validation Rules**:
- All foreign keys must be valid
- Note date must be on or after visit date
- Each visit should have at least one clinical note

**PDF Content Types**:
1. **Clinical Notes**: SOAP format (Subjective, Objective, Assessment, Plan)
2. **Lifestyle Recommendations**: Diet, exercise, stress management, sleep hygiene
3. **Physiotherapy Plans**: Initial evaluation, treatment goals, exercise protocol
4. **Progress Notes**: Follow-up on treatment progress, modifications to plan

### Data Generation Strategy

#### Generation Order
1. **Doctors** → Independent, generate first
2. **Diagnostic Centers** → Independent, generate first
3. **Patients** → Independent, generate first
4. **Visits** → Depends on Patients and Doctors
5. **Lab Results** → Depends on Visits and Diagnostic Centers
6. **Diagnostic Reports** → Depends on Visits and Diagnostic Centers
7. **Insurance Claims** → Depends on Visits
8. **Prescriptions** → Depends on Visits
9. **Clinical Notes** → Depends on Visits

#### Python Generation Approach

**Libraries**:
```python
from faker import Faker
import pandas as pd
import random
from datetime import datetime, timedelta
from reportlab.lib.pagesizes import letter
from reportlab.pdfgen import canvas
from PIL import Image, ImageDraw, ImageFont
```

**Key Techniques**:
- Use `Faker` with seed for reproducibility
- Create custom providers for medical data (ICD-10 codes, CPT codes, medications)
- Use weighted random choices for realistic distributions
- Validate referential integrity before exporting
- Generate PDFs and images after CSV metadata is created

## Contracts

### Data File Contracts

#### CSV Format Standards
- **Encoding**: UTF-8
- **Delimiter**: Comma (,)
- **Quote Character**: Double quote (")
- **Header Row**: Required in first row
- **Date Format**: YYYY-MM-DD
- **Time Format**: HH:MM:SS (24-hour)
- **Decimal Separator**: Period (.)
- **NULL Representation**: Empty string or "NULL"

#### File Naming Conventions
- **CSV files**: `{entity_name}.csv` (e.g., `doctors.csv`, `patients.csv`)
- **PDF files**: `{record_id}_{document_type}.pdf` (e.g., `LR000001_CBC.pdf`, `RX000123_Prescription.pdf`)
- **Image files**: `{record_id}_{modality}_{body_part}.png` (e.g., `DR000045_MRI_Brain.png`)

#### Directory Structure
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
│   ├── lab_results/
│   │   ├── LR000001_CBC.pdf
│   │   ├── LR000002_Lipid_Panel.pdf
│   │   └── ...
│   ├── prescriptions/
│   │   ├── RX000001_Prescription.pdf
│   │   └── ...
│   └── clinical_notes/
│       ├── CN000001_Clinical_Note.pdf
│       ├── CN000002_Physiotherapy.pdf
│       └── ...
└── images/
    ├── DR000001_MRI_Brain.png
    ├── DR000002_XRAY_Chest.png
    └── ...
```

### Medical Code Standards

#### ICD-10-CM Sample Codes (Diagnoses)
- `E11.9`: Type 2 diabetes mellitus without complications
- `I10`: Essential (primary) hypertension
- `J45.909`: Unspecified asthma, uncomplicated
- `M54.5`: Low back pain
- `K21.9`: Gastro-esophageal reflux disease without esophagitis
- `F41.9`: Anxiety disorder, unspecified
- `I25.10`: Atherosclerotic heart disease
- `E78.5`: Hyperlipidemia, unspecified
- `G43.909`: Migraine, unspecified, not intractable, without status migrainosus
- `M25.511`: Pain in right shoulder

#### CPT Sample Codes (Procedures)
- `99213`: Office visit, established patient, 20-29 minutes
- `99214`: Office visit, established patient, 30-39 minutes
- `99203`: Office visit, new patient, 30-44 minutes
- `85025`: Complete blood count (CBC) with differential
- `80053`: Comprehensive metabolic panel
- `70553`: MRI brain with and without contrast
- `71046`: Chest X-ray, 2 views
- `93000`: Electrocardiogram, routine ECG with interpretation
- `36415`: Routine venipuncture for specimen collection

#### LOINC Sample Codes (Lab Tests)
- `718-7`: Hemoglobin
- `2339-0`: Glucose, blood
- `2093-3`: Cholesterol, total
- `2571-8`: Triglycerides
- `2951-2`: Sodium, serum
- `2823-3`: Potassium, serum
- `3094-0`: BUN (Blood Urea Nitrogen)
- `2160-0`: Creatinine, serum

## Quickstart Validation Guide

### Prerequisites
- Python 3.8+
- Required libraries: `faker`, `pandas`, `reportlab`, `Pillow`

### Setup Commands

```bash
# Install dependencies
pip install faker pandas reportlab Pillow

# Create output directory structure
mkdir -p synthetic-healthcare-data/{csv,pdfs/{lab_results,prescriptions,clinical_notes},images}
```

### Generation Script Execution

```bash
# Run the main generation script
python generate_synthetic_healthcare_data.py --seed 42 --output-dir synthetic-healthcare-data

# Verify data generation
python validate_synthetic_data.py --data-dir synthetic-healthcare-data
```

### Expected Outcomes

#### File Counts
- **CSV files**: 9 files (doctors, diagnostic_centers, patients, visits, lab_results, diagnostic_reports, insurance_claims, prescriptions, clinical_notes)
- **Lab result PDFs**: 200-400 files
- **Prescription PDFs**: 200-350 files
- **Clinical note PDFs**: 250-500 files
- **Diagnostic images**: 150-300 PNG files

#### Data Volume
- **Total patients**: 100
- **Total doctors**: 50 (25 specialists, 25 general practitioners)
- **Total diagnostic centers**: 10
- **Total visits**: 300-600 (avg 3-6 per patient)
- **Total lab results**: 200-400 (50-60% of visits generate lab orders)
- **Total diagnostic reports**: 150-300 (30-40% of visits)
- **Total insurance claims**: 300-600 (one per visit minimum)
- **Total prescriptions**: 200-350 (60-70% of visits)
- **Total clinical notes**: 250-500 (includes visit notes and ongoing therapy notes)

#### Validation Checks
1. **Referential Integrity**: All foreign keys resolve to valid primary keys
2. **Date Consistency**: All dates follow logical order (birth < visit < test)
3. **Age Distribution**: 10% ages 3-17, 60% ages 18-64, 30% ages 65-88
4. **Specialty Distribution**: Exactly 25 specialist doctors
5. **No Null Critical Fields**: Patient names, doctor names, visit dates have no nulls
6. **File Existence**: All PDF and image filenames in CSV metadata exist on disk
7. **Medical Code Validity**: All ICD-10, CPT, LOINC codes are valid formats
8. **Numeric Ranges**: Ages between 3-88, experience 5-40 years, claim amounts > 0

### Sample Data Queries

After generation, you can validate with these checks:

```python
import pandas as pd

# Load datasets
doctors = pd.read_csv('synthetic-healthcare-data/csv/doctors.csv')
patients = pd.read_csv('synthetic-healthcare-data/csv/patients.csv')
visits = pd.read_csv('synthetic-healthcare-data/csv/visits.csv')

# Check specialist count
specialists = doctors[doctors['specialty'] != 'Family Medicine']
assert len(specialists) >= 25, f"Expected >= 25 specialists, got {len(specialists)}"

# Check age distribution
age_groups = patients['age'].apply(lambda x: 'pediatric' if x < 18 else ('adult' if x < 65 else 'elderly'))
print(age_groups.value_counts(normalize=True))

# Check visit distribution per patient
visits_per_patient = visits.groupby('patient_id').size()
print(f"Avg visits per patient: {visits_per_patient.mean():.2f}")
print(f"Min visits: {visits_per_patient.min()}, Max visits: {visits_per_patient.max()}")

# Verify referential integrity
invalid_patient_ids = visits[~visits['patient_id'].isin(patients['patient_id'])]
assert len(invalid_patient_ids) == 0, f"Found {len(invalid_patient_ids)} visits with invalid patient IDs"

invalid_doctor_ids = visits[~visits['doctor_id'].isin(doctors['doctor_id'])]
assert len(invalid_doctor_ids) == 0, f"Found {len(invalid_doctor_ids)} visits with invalid doctor IDs"

print("✓ All validation checks passed!")
```

## Implementation Notes

### Key Implementation Decisions

1. **Reproducibility**: Use fixed random seed (default: 42) to ensure consistent datasets across runs
2. **Scalability**: Modular functions allow easy adjustment of record counts
3. **Realism**: Age-correlated health conditions and visit patterns
4. **Performance**: Generate CSVs first, then PDFs/images in parallel if needed
5. **Extensibility**: Easy to add new medical conditions, tests, or document types

### Assumptions

- All patients have insurance (100% coverage for simplicity)
- Timestamps for visits distributed across business hours (8 AM - 6 PM)
- Lab results available within 1-7 days of visit
- Diagnostic imaging within 0-14 days of visit
- Claims submitted within 30 days of visit
- All monetary amounts in USD

### Out of Scope (for this plan)

- Real medical image generation (using synthetic/AI-generated images)
- Integration with actual EMR/EHR systems
- HIPAA compliance documentation (data is synthetic, but best practices followed)
- Internationalization (US healthcare system focus)
- Longitudinal patient histories with chronic disease progression modeling

## Completion Report

**Status**: Plan complete and ready for task generation

**Next Steps**:
1. Run `/speckit-tasks` to generate actionable implementation tasks
2. Tasks will break down the generation script into modular components
3. Implementation phase will create Python scripts for each dataset and document type

**Key Deliverables**:
- 9 CSV files with synthetic healthcare data
- 500-1200 PDF documents (lab results, prescriptions, clinical notes)
- 150-300 PNG placeholder images (diagnostic reports)
- Data validation script
- Documentation for dataset usage

**Estimated Complexity**: Medium
- Well-defined schemas and standards
- Straightforward generation logic with Faker
- No complex dependencies or integrations
- Main challenge: ensuring clinical plausibility and referential integrity
