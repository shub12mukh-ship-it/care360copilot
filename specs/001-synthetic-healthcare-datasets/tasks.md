# Tasks: Synthetic Healthcare Datasets Generation

**Feature**: Synthetic Healthcare Datasets  
**Feature Directory**: `specs/001-synthetic-healthcare-datasets`  
**Status**: Ready for Implementation

## Implementation Strategy

**MVP Scope**: Complete dataset generation system with all 9 entities and validation

**Delivery Approach**: Sequential generation with validation at each step

## Task Phases

### Phase 1: Project Setup

- [ ] T001 Create project directory structure (synthetic-healthcare-data/{csv,pdfs,images})
- [ ] T002 Create requirements.txt with dependencies (faker, pandas, reportlab, Pillow)
- [ ] T003 Create main generation script generate_synthetic_healthcare_data.py

### Phase 2: Core Data Generation

#### Doctors Dataset
- [ ] T004 [P] Implement doctor generation function in generate_synthetic_healthcare_data.py
- [ ] T005 [P] Generate 50 doctors (25 specialists, 25 general practitioners) with realistic distributions
- [ ] T006 [P] Export doctors.csv with proper schema validation

#### Diagnostic Centers Dataset
- [ ] T007 [P] Implement diagnostic center generation function
- [ ] T008 [P] Generate 10 diagnostic centers with varied service offerings
- [ ] T009 [P] Export diagnostic_centers.csv with proper schema validation

#### Patients Dataset
- [ ] T010 [P] Implement patient generation function
- [ ] T011 [P] Generate 100 patients with age range 3-88 years
- [ ] T012 [P] Ensure age distribution (10% pediatric, 60% adult, 30% elderly)
- [ ] T013 [P] Export patients.csv with proper schema validation

### Phase 3: Visit and Relationship Data

#### Visits Dataset
- [ ] T014 Implement visit generation function linking patients and doctors
- [ ] T015 Generate 300-600 visits with realistic temporal distribution (2022-2026)
- [ ] T016 Assign realistic diagnoses with ICD-10 codes
- [ ] T017 Ensure referential integrity (valid patient_id and doctor_id)
- [ ] T018 Export visits.csv with proper schema validation

### Phase 4: Lab Results with PDFs

#### Lab Results Metadata
- [ ] T019 Implement lab result metadata generation function
- [ ] T020 Generate 200-400 lab result records (50-60% of visits)
- [ ] T021 Assign test types (CBC, Lipid Panel, Glucose, etc.) with LOINC codes
- [ ] T022 Ensure referential integrity with visits and diagnostic centers
- [ ] T023 Export lab_results.csv

#### Lab Result PDFs
- [ ] T024 [P] Implement PDF generation function for blood reports
- [ ] T025 [P] Create PDF template with patient demographics, test results, reference ranges
- [ ] T026 [P] Generate age-appropriate and condition-appropriate test values
- [ ] T027 [P] Generate all lab result PDFs (200-400 files) in pdfs/lab_results/
- [ ] T028 [P] Validate PDF filenames match CSV metadata

### Phase 5: Diagnostic Reports with Images

#### Diagnostic Report Metadata
- [ ] T029 Implement diagnostic report metadata generation function
- [ ] T030 Generate 150-300 diagnostic report records (30-40% of visits)
- [ ] T031 Assign modalities (MRI, CT, X-Ray, Angiogram) and body parts
- [ ] T032 Generate realistic findings and impressions
- [ ] T033 Export diagnostic_reports.csv

#### Diagnostic Images
- [ ] T034 [P] Implement PNG placeholder image generation function
- [ ] T035 [P] Create images with overlay text (patient ID, exam type, body part, date)
- [ ] T036 [P] Generate all diagnostic images (150-300 files) in images/
- [ ] T037 [P] Validate image filenames match CSV metadata

### Phase 6: Insurance Claims

- [ ] T038 Implement insurance claim generation function
- [ ] T039 Generate 300-600 claims (one per visit minimum)
- [ ] T040 Assign CPT codes for procedures
- [ ] T041 Calculate realistic billed amounts, allowed amounts, and patient responsibility
- [ ] T042 Set claim status (80% approved, 15% partial, 5% denied)
- [ ] T043 Export insurance_claims.csv with proper schema validation

### Phase 7: Prescriptions with PDFs

#### Prescription Metadata
- [ ] T044 Implement prescription metadata generation function
- [ ] T045 Generate 200-350 prescription records (60-70% of visits)
- [ ] T046 Assign medications with NDC codes, dosage, frequency, duration
- [ ] T047 Export prescriptions.csv

#### Prescription PDFs
- [ ] T048 [P] Implement PDF generation function for prescriptions
- [ ] T049 [P] Create PDF template with Rx format (patient info, medication, sig, refills)
- [ ] T050 [P] Generate all prescription PDFs (200-350 files) in pdfs/prescriptions/
- [ ] T051 [P] Validate PDF filenames match CSV metadata

### Phase 8: Clinical Documentation with PDFs

#### Clinical Notes Metadata
- [ ] T052 Implement clinical notes metadata generation function
- [ ] T053 Generate 250-500 clinical note records
- [ ] T054 Assign note types (Clinical Note, Lifestyle Recommendation, Physiotherapy)
- [ ] T055 Export clinical_notes.csv

#### Clinical Documentation PDFs
- [ ] T056 [P] Implement PDF generation for clinical notes (SOAP format)
- [ ] T057 [P] Implement PDF generation for lifestyle recommendations
- [ ] T058 [P] Implement PDF generation for physiotherapy plans and progress notes
- [ ] T059 [P] Generate all clinical note PDFs (250-500 files) in pdfs/clinical_notes/
- [ ] T060 [P] Validate PDF filenames match CSV metadata

### Phase 9: Data Quality Validation

- [ ] T061 Create data validation script validate_synthetic_data.py
- [ ] T062 Implement referential integrity checks (all foreign keys valid)
- [ ] T063 Implement temporal consistency checks (birth < visit < test dates)
- [ ] T064 Implement distribution validation (age groups, specialist counts)
- [ ] T065 Implement file existence checks (all PDFs and images exist)
- [ ] T066 Implement schema validation (required fields, data types, formats)
- [ ] T067 Implement medical code format validation (ICD-10, CPT, LOINC patterns)
- [ ] T068 Run complete validation suite and generate report

### Phase 10: Documentation and Usage

- [ ] T069 Create README.md with dataset description and usage instructions
- [ ] T070 Document data schemas and relationships
- [ ] T071 Create example queries for data validation
- [ ] T072 Document medical code standards used

## Task Dependencies

**Critical Path**:
1. Setup (T001-T003) → Core Data (T004-T013) → Visits (T014-T018) → All dependent datasets (T019+)

**Parallel Opportunities**:
- After T003: T004-T013 can run in parallel (doctors, centers, patients are independent)
- After T018: T019-T060 can run in parallel with some coordination (all depend on visits but not on each other)
- PDF/Image generation (T024-T028, T034-T037, T048-T051, T056-T060) can run in parallel within their phases

## Validation Criteria

**Dataset Completeness**:
- ✓ All 9 CSV files generated
- ✓ 200-400 lab result PDFs
- ✓ 200-350 prescription PDFs
- ✓ 250-500 clinical note PDFs
- ✓ 150-300 diagnostic images

**Data Quality**:
- ✓ 100% referential integrity
- ✓ Age distribution matches specification (10/60/30 split)
- ✓ Exactly 25 specialist doctors
- ✓ Temporal consistency (all dates logically ordered)
- ✓ All filenames in CSV metadata exist on disk

**Medical Realism**:
- ✓ ICD-10 codes are valid format
- ✓ CPT codes are valid format
- ✓ LOINC codes are valid format
- ✓ Age-appropriate diagnoses and test results
- ✓ Realistic claim approval rates (80/15/5 split)

## Done When

- [ ] All 72 tasks completed
- [ ] Validation script passes 100%
- [ ] README documentation complete
- [ ] Dataset ready for use in Care360 Copilot testing
