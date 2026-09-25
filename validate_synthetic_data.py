"""
Synthetic Healthcare Data Validation Script
Validates data quality, referential integrity, and business rules

Usage:
    python validate_synthetic_data.py --data-dir synthetic-healthcare-data
"""

import argparse
import re
from pathlib import Path
from datetime import datetime
import pandas as pd


class DataValidator:
    def __init__(self, data_dir):
        self.data_dir = Path(data_dir)
        self.csv_dir = self.data_dir / 'csv'
        self.pdf_lab_dir = self.data_dir / 'pdfs' / 'lab_results'
        self.pdf_rx_dir = self.data_dir / 'pdfs' / 'prescriptions'
        self.pdf_notes_dir = self.data_dir / 'pdfs' / 'clinical_notes'
        self.images_dir = self.data_dir / 'images'
        
        self.errors = []
        self.warnings = []
        self.success_count = 0
        self.total_checks = 0
        
    def log_error(self, check_name, message):
        """Log a validation error"""
        self.errors.append(f"[{check_name}] {message}")
        
    def log_warning(self, check_name, message):
        """Log a validation warning"""
        self.warnings.append(f"[{check_name}] {message}")
        
    def log_success(self, check_name):
        """Log a successful validation"""
        self.success_count += 1
        
    def run_check(self, check_name, check_func):
        """Run a validation check and track results"""
        self.total_checks += 1
        print(f"  Checking: {check_name}...", end=' ')
        try:
            result = check_func()
            if result:
                self.log_success(check_name)
                print("✓ PASS")
                return True
            else:
                print("✗ FAIL")
                return False
        except Exception as e:
            self.log_error(check_name, f"Exception: {str(e)}")
            print(f"✗ ERROR: {str(e)}")
            return False
    
    def load_data(self):
        """Load all CSV files"""
        print("\nLoading datasets...")
        self.doctors_df = pd.read_csv(self.csv_dir / 'doctors.csv')
        self.centers_df = pd.read_csv(self.csv_dir / 'diagnostic_centers.csv')
        self.patients_df = pd.read_csv(self.csv_dir / 'patients.csv')
        self.visits_df = pd.read_csv(self.csv_dir / 'visits.csv')
        self.lab_results_df = pd.read_csv(self.csv_dir / 'lab_results.csv')
        self.diagnostic_reports_df = pd.read_csv(self.csv_dir / 'diagnostic_reports.csv')
        self.claims_df = pd.read_csv(self.csv_dir / 'insurance_claims.csv')
        self.prescriptions_df = pd.read_csv(self.csv_dir / 'prescriptions.csv')
        self.clinical_notes_df = pd.read_csv(self.csv_dir / 'clinical_notes.csv')
        
        print(f"✓ Loaded 9 CSV files")
        print(f"  - Doctors: {len(self.doctors_df)} records")
        print(f"  - Diagnostic Centers: {len(self.centers_df)} records")
        print(f"  - Patients: {len(self.patients_df)} records")
        print(f"  - Visits: {len(self.visits_df)} records")
        print(f"  - Lab Results: {len(self.lab_results_df)} records")
        print(f"  - Diagnostic Reports: {len(self.diagnostic_reports_df)} records")
        print(f"  - Insurance Claims: {len(self.claims_df)} records")
        print(f"  - Prescriptions: {len(self.prescriptions_df)} records")
        print(f"  - Clinical Notes: {len(self.clinical_notes_df)} records")
    
    def validate_counts(self):
        """Validate record counts match requirements"""
        print("\n" + "="*60)
        print("1. DATASET COUNTS VALIDATION")
        print("="*60)
        
        # Check doctor count (exactly 50)
        def check_doctor_count():
            if len(self.doctors_df) != 50:
                self.log_error("Doctor Count", f"Expected 50 doctors, got {len(self.doctors_df)}")
                return False
            return True
        self.run_check("Doctor Count (50)", check_doctor_count)
        
        # Check specialist count (exactly 25)
        def check_specialist_count():
            specialists = self.doctors_df[~self.doctors_df['specialty'].isin(['Family Medicine', 'General Practice', 'Internal Medicine'])]
            if len(specialists) != 25:
                self.log_error("Specialist Count", f"Expected 25 specialists, got {len(specialists)}")
                return False
            return True
        self.run_check("Specialist Count (25)", check_specialist_count)
        
        # Check diagnostic center count (exactly 10)
        def check_center_count():
            if len(self.centers_df) != 10:
                self.log_error("Center Count", f"Expected 10 centers, got {len(self.centers_df)}")
                return False
            return True
        self.run_check("Diagnostic Center Count (10)", check_center_count)
        
        # Check patient count (exactly 100)
        def check_patient_count():
            if len(self.patients_df) != 100:
                self.log_error("Patient Count", f"Expected 100 patients, got {len(self.patients_df)}")
                return False
            return True
        self.run_check("Patient Count (100)", check_patient_count)
        
        # Check age range (3-88)
        def check_age_range():
            min_age = self.patients_df['age'].min()
            max_age = self.patients_df['age'].max()
            if min_age < 3 or max_age > 88:
                self.log_error("Age Range", f"Ages should be 3-88, got {min_age}-{max_age}")
                return False
            return True
        self.run_check("Patient Age Range (3-88)", check_age_range)
        
        # Check age distribution
        def check_age_distribution():
            pediatric = len(self.patients_df[self.patients_df['age'] < 18])
            adult = len(self.patients_df[(self.patients_df['age'] >= 18) & (self.patients_df['age'] < 65)])
            elderly = len(self.patients_df[self.patients_df['age'] >= 65])
            
            # Allow ±5% tolerance
            expected_pediatric = (8, 12)  # 10% ±2
            expected_adult = (55, 65)     # 60% ±5
            expected_elderly = (25, 35)   # 30% ±5
            
            issues = []
            if not (expected_pediatric[0] <= pediatric <= expected_pediatric[1]):
                issues.append(f"Pediatric: {pediatric} (expected ~10)")
            if not (expected_adult[0] <= adult <= expected_adult[1]):
                issues.append(f"Adult: {adult} (expected ~60)")
            if not (expected_elderly[0] <= elderly <= expected_elderly[1]):
                issues.append(f"Elderly: {elderly} (expected ~30)")
            
            if issues:
                self.log_warning("Age Distribution", f"Outside expected ranges: {', '.join(issues)}")
                return True  # Warning, not error
            return True
        self.run_check("Age Distribution (10% pediatric, 60% adult, 30% elderly)", check_age_distribution)
    
    def validate_referential_integrity(self):
        """Validate foreign key relationships"""
        print("\n" + "="*60)
        print("2. REFERENTIAL INTEGRITY VALIDATION")
        print("="*60)
        
        # Visits reference valid patients
        def check_visit_patients():
            invalid = self.visits_df[~self.visits_df['patient_id'].isin(self.patients_df['patient_id'])]
            if len(invalid) > 0:
                self.log_error("Visit Patient FK", f"{len(invalid)} visits reference invalid patient_id")
                return False
            return True
        self.run_check("Visits → Patients FK", check_visit_patients)
        
        # Visits reference valid doctors
        def check_visit_doctors():
            invalid = self.visits_df[~self.visits_df['doctor_id'].isin(self.doctors_df['doctor_id'])]
            if len(invalid) > 0:
                self.log_error("Visit Doctor FK", f"{len(invalid)} visits reference invalid doctor_id")
                return False
            return True
        self.run_check("Visits → Doctors FK", check_visit_doctors)
        
        # Lab results reference valid visits
        def check_lab_visits():
            invalid = self.lab_results_df[~self.lab_results_df['visit_id'].isin(self.visits_df['visit_id'])]
            if len(invalid) > 0:
                self.log_error("Lab Visit FK", f"{len(invalid)} lab results reference invalid visit_id")
                return False
            return True
        self.run_check("Lab Results → Visits FK", check_lab_visits)
        
        # Lab results reference valid centers
        def check_lab_centers():
            invalid = self.lab_results_df[~self.lab_results_df['center_id'].isin(self.centers_df['center_id'])]
            if len(invalid) > 0:
                self.log_error("Lab Center FK", f"{len(invalid)} lab results reference invalid center_id")
                return False
            return True
        self.run_check("Lab Results → Centers FK", check_lab_centers)
        
        # Diagnostic reports reference valid visits
        def check_report_visits():
            invalid = self.diagnostic_reports_df[~self.diagnostic_reports_df['visit_id'].isin(self.visits_df['visit_id'])]
            if len(invalid) > 0:
                self.log_error("Report Visit FK", f"{len(invalid)} reports reference invalid visit_id")
                return False
            return True
        self.run_check("Diagnostic Reports → Visits FK", check_report_visits)
        
        # Claims reference valid visits
        def check_claim_visits():
            invalid = self.claims_df[~self.claims_df['visit_id'].isin(self.visits_df['visit_id'])]
            if len(invalid) > 0:
                self.log_error("Claim Visit FK", f"{len(invalid)} claims reference invalid visit_id")
                return False
            return True
        self.run_check("Insurance Claims → Visits FK", check_claim_visits)
        
        # Prescriptions reference valid visits
        def check_rx_visits():
            invalid = self.prescriptions_df[~self.prescriptions_df['visit_id'].isin(self.visits_df['visit_id'])]
            if len(invalid) > 0:
                self.log_error("Rx Visit FK", f"{len(invalid)} prescriptions reference invalid visit_id")
                return False
            return True
        self.run_check("Prescriptions → Visits FK", check_rx_visits)
        
        # Clinical notes reference valid visits
        def check_note_visits():
            invalid = self.clinical_notes_df[~self.clinical_notes_df['visit_id'].isin(self.visits_df['visit_id'])]
            if len(invalid) > 0:
                self.log_error("Note Visit FK", f"{len(invalid)} notes reference invalid visit_id")
                return False
            return True
        self.run_check("Clinical Notes → Visits FK", check_note_visits)
    
    def validate_temporal_consistency(self):
        """Validate date logic"""
        print("\n" + "="*60)
        print("3. TEMPORAL CONSISTENCY VALIDATION")
        print("="*60)
        
        # Convert date columns
        self.patients_df['dob_dt'] = pd.to_datetime(self.patients_df['date_of_birth'])
        self.visits_df['visit_dt'] = pd.to_datetime(self.visits_df['visit_date'])
        
        # Patient DOB before visit date
        def check_dob_before_visit():
            merged = self.visits_df.merge(self.patients_df[['patient_id', 'dob_dt']], on='patient_id')
            invalid = merged[merged['dob_dt'] >= merged['visit_dt']]
            if len(invalid) > 0:
                self.log_error("DOB Before Visit", f"{len(invalid)} visits occur before patient birth")
                return False
            return True
        self.run_check("Patient DOB < Visit Date", check_dob_before_visit)
        
        # Lab test dates reasonable (within 30 days of visit)
        def check_lab_dates():
            self.lab_results_df['test_dt'] = pd.to_datetime(self.lab_results_df['test_date'])
            merged = self.lab_results_df.merge(self.visits_df[['visit_id', 'visit_dt']], on='visit_id')
            merged['days_diff'] = (merged['test_dt'] - merged['visit_dt']).dt.days
            invalid = merged[(merged['days_diff'] < 0) | (merged['days_diff'] > 30)]
            if len(invalid) > 0:
                self.log_warning("Lab Date Range", f"{len(invalid)} lab tests outside 0-30 day window")
            return True
        self.run_check("Lab Test Dates (within 30 days of visit)", check_lab_dates)
        
        # Visit dates in valid range (2022-2026)
        def check_visit_date_range():
            start_date = datetime(2022, 1, 1)
            end_date = datetime(2026, 12, 31)
            invalid = self.visits_df[(self.visits_df['visit_dt'] < start_date) | (self.visits_df['visit_dt'] > end_date)]
            if len(invalid) > 0:
                self.log_error("Visit Date Range", f"{len(invalid)} visits outside 2022-2026 range")
                return False
            return True
        self.run_check("Visit Dates (2022-2026)", check_visit_date_range)
    
    def validate_medical_codes(self):
        """Validate medical coding standards"""
        print("\n" + "="*60)
        print("4. MEDICAL CODE FORMAT VALIDATION")
        print("="*60)
        
        # ICD-10 code format
        def check_icd10_format():
            # ICD-10 pattern: Letter followed by 2 digits, optional decimal and more digits
            pattern = r'^[A-Z]\d{2}(\.\d{1,4})?$'
            invalid = self.visits_df[~self.visits_df['diagnosis_code'].str.match(pattern)]
            if len(invalid) > 0:
                self.log_error("ICD-10 Format", f"{len(invalid)} invalid ICD-10 codes")
                return False
            return True
        self.run_check("ICD-10 Code Format", check_icd10_format)
        
        # CPT code format (5 digits)
        def check_cpt_format():
            pattern = r'^\d{5}$'
            # Convert to string first
            procedure_codes = self.claims_df['procedure_code'].astype(str)
            invalid = self.claims_df[~procedure_codes.str.match(pattern)]
            if len(invalid) > 0:
                self.log_error("CPT Format", f"{len(invalid)} invalid CPT codes")
                return False
            return True
        self.run_check("CPT Code Format", check_cpt_format)
        
        # LOINC code format (digits with optional dash)
        def check_loinc_format():
            pattern = r'^\d+-\d+$'
            invalid = self.lab_results_df[~self.lab_results_df['test_code'].str.match(pattern)]
            if len(invalid) > 0:
                self.log_error("LOINC Format", f"{len(invalid)} invalid LOINC codes")
                return False
            return True
        self.run_check("LOINC Code Format", check_loinc_format)
        
        # NDC code format (5-4-2 format)
        def check_ndc_format():
            pattern = r'^\d{5}-\d{4}-\d{2}$'
            invalid = self.prescriptions_df[~self.prescriptions_df['ndc_code'].str.match(pattern)]
            if len(invalid) > 0:
                self.log_error("NDC Format", f"{len(invalid)} invalid NDC codes")
                return False
            return True
        self.run_check("NDC Code Format", check_ndc_format)
    
    def validate_file_existence(self):
        """Validate that referenced files exist"""
        print("\n" + "="*60)
        print("5. FILE EXISTENCE VALIDATION")
        print("="*60)
        
        # Lab result PDFs
        def check_lab_pdfs():
            completed_labs = self.lab_results_df[self.lab_results_df['status'] == 'Completed']
            missing = []
            for _, row in completed_labs.iterrows():
                filepath = self.pdf_lab_dir / row['pdf_filename']
                if not filepath.exists():
                    missing.append(row['pdf_filename'])
            if missing:
                self.log_error("Lab PDFs", f"{len(missing)} lab result PDFs missing")
                return False
            return True
        self.run_check(f"Lab Result PDFs ({len(self.lab_results_df[self.lab_results_df['status'] == 'Completed'])} files)", check_lab_pdfs)
        
        # Prescription PDFs
        def check_rx_pdfs():
            missing = []
            for _, row in self.prescriptions_df.iterrows():
                filepath = self.pdf_rx_dir / row['pdf_filename']
                if not filepath.exists():
                    missing.append(row['pdf_filename'])
            if missing:
                self.log_error("Rx PDFs", f"{len(missing)} prescription PDFs missing")
                return False
            return True
        self.run_check(f"Prescription PDFs ({len(self.prescriptions_df)} files)", check_rx_pdfs)
        
        # Clinical note PDFs
        def check_note_pdfs():
            missing = []
            for _, row in self.clinical_notes_df.iterrows():
                filepath = self.pdf_notes_dir / row['pdf_filename']
                if not filepath.exists():
                    missing.append(row['pdf_filename'])
            if missing:
                self.log_error("Note PDFs", f"{len(missing)} clinical note PDFs missing")
                return False
            return True
        self.run_check(f"Clinical Note PDFs ({len(self.clinical_notes_df)} files)", check_note_pdfs)
        
        # Diagnostic images
        def check_images():
            missing = []
            for _, row in self.diagnostic_reports_df.iterrows():
                filepath = self.images_dir / row['image_filename']
                if not filepath.exists():
                    missing.append(row['image_filename'])
            if missing:
                self.log_error("Images", f"{len(missing)} diagnostic images missing")
                return False
            return True
        self.run_check(f"Diagnostic Images ({len(self.diagnostic_reports_df)} files)", check_images)
    
    def validate_business_rules(self):
        """Validate business logic"""
        print("\n" + "="*60)
        print("6. BUSINESS RULES VALIDATION")
        print("="*60)
        
        # Insurance claim amounts logical
        def check_claim_amounts():
            invalid = self.claims_df[self.claims_df['allowed_amount'] > self.claims_df['billed_amount']]
            if len(invalid) > 0:
                self.log_error("Claim Amounts", f"{len(invalid)} claims with allowed > billed")
                return False
            return True
        self.run_check("Insurance Claim Amounts (allowed ≤ billed)", check_claim_amounts)
        
        # Claim status distribution
        def check_claim_status_distribution():
            approved = len(self.claims_df[self.claims_df['claim_status'] == 'Approved'])
            total = len(self.claims_df)
            approval_rate = (approved / total) * 100
            if approval_rate < 70 or approval_rate > 90:
                self.log_warning("Claim Approval Rate", f"Approval rate {approval_rate:.1f}% (expected ~80%)")
            return True
        self.run_check("Claim Approval Rate (~80%)", check_claim_status_distribution)
        
        # Unique patient IDs
        def check_unique_patients():
            if self.patients_df['patient_id'].duplicated().any():
                self.log_error("Patient ID Uniqueness", "Duplicate patient IDs found")
                return False
            return True
        self.run_check("Unique Patient IDs", check_unique_patients)
        
        # Every visit has at least one associated record
        def check_visit_coverage():
            # At least insurance claim
            visits_with_data = set()
            visits_with_data.update(self.claims_df['visit_id'].unique())
            
            uncovered_visits = set(self.visits_df['visit_id']) - visits_with_data
            if uncovered_visits:
                self.log_warning("Visit Coverage", f"{len(uncovered_visits)} visits without any associated records")
            return True
        self.run_check("Visit Coverage (all visits have claims)", check_visit_coverage)
    
    def print_summary(self):
        """Print validation summary"""
        print("\n" + "="*60)
        print("VALIDATION SUMMARY")
        print("="*60)
        
        print(f"\nTotal Checks: {self.total_checks}")
        print(f"Passed: {self.success_count}")
        print(f"Failed: {len(self.errors)}")
        print(f"Warnings: {len(self.warnings)}")
        
        if self.errors:
            print(f"\n❌ ERRORS ({len(self.errors)}):")
            for error in self.errors:
                print(f"  • {error}")
        
        if self.warnings:
            print(f"\n⚠️  WARNINGS ({len(self.warnings)}):")
            for warning in self.warnings:
                print(f"  • {warning}")
        
        if not self.errors:
            print("\n✅ ALL VALIDATIONS PASSED!")
            print("Dataset is ready for use.")
        else:
            print(f"\n❌ VALIDATION FAILED with {len(self.errors)} error(s)")
            print("Please review and fix errors before using dataset.")
        
        success_rate = (self.success_count / self.total_checks * 100) if self.total_checks > 0 else 0
        print(f"\nSuccess Rate: {success_rate:.1f}%")
        print("="*60 + "\n")
        
        return len(self.errors) == 0
    
    def validate_all(self):
        """Run all validation checks"""
        print("\n" + "="*60)
        print("SYNTHETIC HEALTHCARE DATA VALIDATION")
        print("="*60)
        print(f"Data Directory: {self.data_dir.absolute()}\n")
        
        self.load_data()
        self.validate_counts()
        self.validate_referential_integrity()
        self.validate_temporal_consistency()
        self.validate_medical_codes()
        self.validate_file_existence()
        self.validate_business_rules()
        
        return self.print_summary()


def main():
    parser = argparse.ArgumentParser(description='Validate synthetic healthcare datasets')
    parser.add_argument('--data-dir', type=str, default='synthetic-healthcare-data', 
                        help='Data directory to validate')
    
    args = parser.parse_args()
    
    validator = DataValidator(args.data_dir)
    success = validator.validate_all()
    
    # Exit with appropriate code
    exit(0 if success else 1)


if __name__ == '__main__':
    main()
