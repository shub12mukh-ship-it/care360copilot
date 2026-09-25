"""
Synthetic Healthcare Data Generator
Generates high-quality synthetic healthcare datasets for Care360 Copilot testing

Usage:
    python generate_synthetic_healthcare_data.py --seed 42 --output-dir synthetic-healthcare-data
"""

import argparse
import random
from datetime import datetime, timedelta
from pathlib import Path
import pandas as pd
from faker import Faker
from reportlab.lib.pagesizes import letter
from reportlab.pdfgen import canvas
from reportlab.lib.units import inch
from PIL import Image, ImageDraw, ImageFont
import io

# Initialize Faker
fake = Faker()

# Medical code dictionaries
SPECIALTIES = {
    'specialists': [
        'Cardiology', 'Neurology', 'Orthopedics', 'Dermatology', 'Gastroenterology',
        'Pulmonology', 'Endocrinology', 'Nephrology', 'Oncology', 'Psychiatry',
        'Rheumatology', 'Urology', 'Ophthalmology', 'ENT', 'Pediatrics',
        'Obstetrics and Gynecology', 'Radiology', 'Anesthesiology', 'Pathology',
        'Emergency Medicine', 'Infectious Disease', 'Hematology', 'Allergy and Immunology',
        'Physical Medicine', 'Sports Medicine'
    ],
    'general': ['Family Medicine', 'General Practice', 'Internal Medicine']
}

MEDICAL_SCHOOLS = [
    'Harvard Medical School', 'Johns Hopkins School of Medicine', 'Stanford School of Medicine',
    'Mayo Clinic School of Medicine', 'UCSF School of Medicine', 'Duke School of Medicine',
    'University of Pennsylvania Perelman School of Medicine', 'Columbia College of Physicians',
    'Yale School of Medicine', 'University of Chicago Pritzker School of Medicine',
    'Washington University School of Medicine', 'Cornell Medical College', 'UCLA Medical School'
]

DIAGNOSTIC_SERVICES = [
    'MRI', 'CT', 'X-Ray', 'Ultrasound', 'Blood Tests', 'Urine Tests',
    'Angiogram', 'ECG', 'EEG', 'Mammography', 'Bone Density', 'PET Scan'
]

BLOOD_TYPES = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-']

ETHNICITIES = ['Caucasian', 'African American', 'Hispanic', 'Asian', 'Native American', 'Pacific Islander', 'Other']

INSURANCE_PROVIDERS = [
    'Blue Cross Blue Shield', 'UnitedHealthcare', 'Aetna', 'Cigna', 'Humana',
    'Kaiser Permanente', 'Anthem', 'Medicare', 'Medicaid', 'WellCare'
]

# ICD-10 Diagnosis codes (sample)
ICD10_CODES = {
    'E11.9': 'Type 2 diabetes mellitus without complications',
    'I10': 'Essential (primary) hypertension',
    'J45.909': 'Unspecified asthma, uncomplicated',
    'M54.5': 'Low back pain',
    'K21.9': 'Gastro-esophageal reflux disease without esophagitis',
    'F41.9': 'Anxiety disorder, unspecified',
    'I25.10': 'Atherosclerotic heart disease',
    'E78.5': 'Hyperlipidemia, unspecified',
    'G43.909': 'Migraine, unspecified',
    'M25.511': 'Pain in right shoulder',
    'J06.9': 'Acute upper respiratory infection',
    'R51': 'Headache',
    'K59.00': 'Constipation, unspecified',
    'N39.0': 'Urinary tract infection',
    'J20.9': 'Acute bronchitis',
    'L70.0': 'Acne vulgaris',
    'E66.9': 'Obesity, unspecified',
    'F32.9': 'Major depressive disorder, single episode, unspecified',
    'M19.90': 'Unspecified osteoarthritis',
    'H52.4': 'Presbyopia'
}

# CPT Procedure codes (sample)
CPT_CODES = {
    '99213': ('Office visit, established patient, 20-29 min', 150.00),
    '99214': ('Office visit, established patient, 30-39 min', 215.00),
    '99203': ('Office visit, new patient, 30-44 min', 200.00),
    '85025': ('Complete blood count (CBC) with differential', 45.00),
    '80053': ('Comprehensive metabolic panel', 65.00),
    '70553': ('MRI brain with and without contrast', 1200.00),
    '71046': ('Chest X-ray, 2 views', 125.00),
    '93000': ('Electrocardiogram, routine ECG', 85.00),
    '36415': ('Routine venipuncture', 25.00),
    '80061': ('Lipid panel', 55.00),
    '83036': ('Hemoglobin A1C', 40.00),
    '82947': ('Glucose, blood quantitative', 30.00),
    '84443': ('Thyroid stimulating hormone (TSH)', 50.00),
    '87086': ('Urine culture', 45.00)
}

# LOINC Lab test codes (sample)
LOINC_TESTS = {
    '718-7': ('Hemoglobin', 'g/dL', (12.0, 18.0)),
    '2339-0': ('Glucose, blood', 'mg/dL', (70, 100)),
    '2093-3': ('Cholesterol, total', 'mg/dL', (125, 200)),
    '2571-8': ('Triglycerides', 'mg/dL', (40, 150)),
    '2951-2': ('Sodium, serum', 'mmol/L', (136, 145)),
    '2823-3': ('Potassium, serum', 'mmol/L', (3.5, 5.0)),
    '3094-0': ('BUN (Blood Urea Nitrogen)', 'mg/dL', (7, 20)),
    '2160-0': ('Creatinine, serum', 'mg/dL', (0.6, 1.2)),
    '1751-7': ('Albumin, serum', 'g/dL', (3.5, 5.5)),
    '1920-8': ('AST (SGOT)', 'U/L', (10, 40)),
    '1742-6': ('ALT (SGPT)', 'U/L', (7, 56)),
    '1975-2': ('Bilirubin, total', 'mg/dL', (0.1, 1.2))
}

# Common medications with NDC codes
MEDICATIONS = {
    'Lisinopril': ('68180-0513-01', '10 mg', 'Once daily', '90 days'),
    'Metformin': ('68180-0512-06', '500 mg', 'Twice daily', '90 days'),
    'Atorvastatin': ('68180-0373-06', '20 mg', 'Once daily', '90 days'),
    'Amlodipine': ('68180-0512-11', '5 mg', 'Once daily', '90 days'),
    'Omeprazole': ('68180-0287-09', '20 mg', 'Once daily', '30 days'),
    'Levothyroxine': ('68180-0365-06', '50 mcg', 'Once daily', '90 days'),
    'Albuterol Inhaler': ('00173-0682-20', '90 mcg', 'As needed', '30 days'),
    'Gabapentin': ('68180-0723-11', '300 mg', 'Three times daily', '90 days'),
    'Sertraline': ('68180-0512-03', '50 mg', 'Once daily', '90 days'),
    'Amoxicillin': ('68180-0514-09', '500 mg', 'Three times daily', '10 days')
}


def set_seed(seed):
    """Set random seed for reproducibility"""
    random.seed(seed)
    Faker.seed(seed)


def generate_doctors(n_doctors=50, n_specialists=25):
    """Generate doctor dataset"""
    print(f"Generating {n_doctors} doctors ({n_specialists} specialists)...")
    
    doctors = []
    doctor_id_counter = 1
    
    # Generate specialists
    for i in range(n_specialists):
        specialty = random.choice(SPECIALTIES['specialists'])
        doctor = {
            'doctor_id': f'D{doctor_id_counter:05d}',
            'first_name': fake.first_name(),
            'last_name': fake.last_name(),
            'specialty': specialty,
            'sub_specialty': f'{specialty} Specialist',
            'years_experience': random.randint(5, 40),
            'medical_school': random.choice(MEDICAL_SCHOOLS),
            'board_certified': random.choice([True, True, True, False]),  # 75% board certified
            'phone': fake.phone_number(),
            'email': fake.email(),
            'license_number': f'MD{fake.random_number(digits=8)}'
        }
        doctors.append(doctor)
        doctor_id_counter += 1
    
    # Generate general practitioners
    for i in range(n_doctors - n_specialists):
        specialty = random.choice(SPECIALTIES['general'])
        doctor = {
            'doctor_id': f'D{doctor_id_counter:05d}',
            'first_name': fake.first_name(),
            'last_name': fake.last_name(),
            'specialty': specialty,
            'sub_specialty': '',
            'years_experience': random.randint(5, 40),
            'medical_school': random.choice(MEDICAL_SCHOOLS),
            'board_certified': random.choice([True, True, True, False]),
            'phone': fake.phone_number(),
            'email': fake.email(),
            'license_number': f'MD{fake.random_number(digits=8)}'
        }
        doctors.append(doctor)
        doctor_id_counter += 1
    
    return pd.DataFrame(doctors)


def generate_diagnostic_centers(n_centers=10):
    """Generate diagnostic center dataset"""
    print(f"Generating {n_centers} diagnostic centers...")
    
    centers = []
    for i in range(1, n_centers + 1):
        # Ensure service variety
        n_services = random.randint(4, 8)
        services = random.sample(DIAGNOSTIC_SERVICES, n_services)
        
        # Ensure minimum coverage
        if i <= 8:
            if 'Blood Tests' not in services:
                services.append('Blood Tests')
        if i <= 5:
            if 'MRI' not in services:
                services.append('MRI')
        if i <= 7:
            if 'X-Ray' not in services:
                services.append('X-Ray')
        
        center = {
            'center_id': f'DC{i:03d}',
            'center_name': f'{fake.city()} Diagnostic Center',
            'address': fake.street_address(),
            'city': fake.city(),
            'state': fake.state_abbr(),
            'zip_code': fake.zipcode(),
            'phone': fake.phone_number(),
            'services_offered': ', '.join(services),
            'accreditation': random.choice(['ACR', 'CAP', 'CLIA', 'Joint Commission']),
            'operating_hours': '7:00 AM - 7:00 PM'
        }
        centers.append(center)
    
    return pd.DataFrame(centers)


def generate_patients(n_patients=100):
    """Generate patient dataset with age variety 3-88"""
    print(f"Generating {n_patients} patients...")
    
    patients = []
    # Use earliest visit date (2022) as reference for age calculation
    reference_date = datetime(2022, 1, 1)
    
    # Calculate age distribution
    n_pediatric = int(n_patients * 0.10)  # 10% ages 3-17
    n_adult = int(n_patients * 0.60)      # 60% ages 18-64
    n_elderly = n_patients - n_pediatric - n_adult  # 30% ages 65-88
    
    ages = (
        [random.randint(3, 17) for _ in range(n_pediatric)] +
        [random.randint(18, 64) for _ in range(n_adult)] +
        [random.randint(65, 88) for _ in range(n_elderly)]
    )
    random.shuffle(ages)
    
    for i, age in enumerate(ages, 1):
        # Calculate date of birth from age (relative to earliest visit date)
        dob = reference_date - timedelta(days=age*365 + random.randint(0, 364))
        
        # Gender distribution
        gender = random.choices(
            ['Male', 'Female', 'Non-binary'],
            weights=[48, 48, 4],
            k=1
        )[0]
        
        patient = {
            'patient_id': f'P{i:05d}',
            'first_name': fake.first_name(),
            'last_name': fake.last_name(),
            'date_of_birth': dob.strftime('%Y-%m-%d'),
            'age': age,
            'gender': gender,
            'ethnicity': random.choice(ETHNICITIES),
            'blood_type': random.choice(BLOOD_TYPES),
            'address': fake.street_address(),
            'city': fake.city(),
            'state': fake.state_abbr(),
            'zip_code': fake.zipcode(),
            'phone': fake.phone_number(),
            'email': fake.email(),
            'emergency_contact_name': fake.name(),
            'emergency_contact_phone': fake.phone_number(),
            'insurance_provider': random.choice(INSURANCE_PROVIDERS),
            'insurance_policy_number': fake.bothify(text='POL-########')
        }
        patients.append(patient)
    
    return pd.DataFrame(patients)


def generate_visits(patients_df, doctors_df, min_visits_per_patient=1, max_visits_per_patient=10):
    """Generate visit records linking patients and doctors"""
    print("Generating patient visits...")
    
    visits = []
    visit_id_counter = 1
    
    start_date = datetime(2022, 1, 1)
    end_date = datetime(2026, 9, 25)
    
    for _, patient in patients_df.iterrows():
        n_visits = random.randint(min_visits_per_patient, max_visits_per_patient)
        
        for _ in range(n_visits):
            # Random visit date
            days_between = (end_date - start_date).days
            visit_date = start_date + timedelta(days=random.randint(0, days_between))
            
            # Business hours (8 AM - 6 PM)
            visit_time = f'{random.randint(8, 17):02d}:{random.choice([0, 15, 30, 45]):02d}:00'
            
            # Select doctor (80% general, 20% specialist)
            if random.random() < 0.80:
                doctor = doctors_df[doctors_df['specialty'].isin(SPECIALTIES['general'])].sample(1).iloc[0]
                visit_type = random.choice(['Routine', 'Urgent Care', 'Follow-up'])
            else:
                doctor = doctors_df[~doctors_df['specialty'].isin(SPECIALTIES['general'])].sample(1).iloc[0]
                visit_type = 'Specialist Consultation'
            
            # Select diagnosis
            diagnosis_code = random.choice(list(ICD10_CODES.keys()))
            diagnosis_desc = ICD10_CODES[diagnosis_code]
            
            # Chief complaint based on diagnosis
            chief_complaints = {
                'E11.9': 'Frequent urination and increased thirst',
                'I10': 'High blood pressure reading',
                'J45.909': 'Difficulty breathing and wheezing',
                'M54.5': 'Lower back pain',
                'K21.9': 'Heartburn and acid reflux',
                'F41.9': 'Excessive worry and anxiety',
                'I25.10': 'Chest pain and shortness of breath',
                'E78.5': 'High cholesterol screening',
                'G43.909': 'Severe headache',
                'M25.511': 'Right shoulder pain'
            }
            chief_complaint = chief_complaints.get(diagnosis_code, 'General checkup')
            
            visit = {
                'visit_id': f'V{visit_id_counter:06d}',
                'patient_id': patient['patient_id'],
                'doctor_id': doctor['doctor_id'],
                'visit_date': visit_date.strftime('%Y-%m-%d'),
                'visit_time': visit_time,
                'visit_type': visit_type,
                'chief_complaint': chief_complaint,
                'diagnosis_code': diagnosis_code,
                'diagnosis_description': diagnosis_desc,
                'treatment_plan': f'Prescribed medication, lifestyle changes, follow-up in {random.randint(1, 6)} months',
                'follow_up_required': random.choice([True, False]),
                'follow_up_date': (visit_date + timedelta(days=random.randint(30, 180))).strftime('%Y-%m-%d') if random.choice([True, False]) else '',
                'notes': fake.sentence(nb_words=15)
            }
            visits.append(visit)
            visit_id_counter += 1
    
    return pd.DataFrame(visits)


def generate_lab_results(visits_df, centers_df, doctors_df):
    """Generate lab results metadata (50-60% of visits)"""
    print("Generating lab results metadata...")
    
    lab_results = []
    lab_id_counter = 1
    
    # Sample 50-60% of visits for lab tests
    visits_with_labs = visits_df.sample(frac=random.uniform(0.50, 0.60))
    
    for _, visit in visits_with_labs.iterrows():
        # Select center that offers blood tests
        blood_test_centers = centers_df[centers_df['services_offered'].str.contains('Blood Tests')]
        center = blood_test_centers.sample(1).iloc[0]
        
        # Select test type
        test_types = ['CBC', 'Lipid Panel', 'Glucose', 'Comprehensive Metabolic Panel', 
                      'Liver Function', 'Kidney Function', 'Thyroid Panel', 'Hemoglobin A1C']
        test_type = random.choice(test_types)
        
        # Get LOINC code (simplified - use first match)
        test_code = random.choice(list(LOINC_TESTS.keys()))
        
        # Test date (0-7 days after visit)
        visit_date = datetime.strptime(visit['visit_date'], '%Y-%m-%d')
        test_date = visit_date + timedelta(days=random.randint(0, 7))
        
        lab_result = {
            'lab_result_id': f'LR{lab_id_counter:06d}',
            'patient_id': visit['patient_id'],
            'visit_id': visit['visit_id'],
            'center_id': center['center_id'],
            'test_date': test_date.strftime('%Y-%m-%d'),
            'test_type': test_type,
            'test_code': test_code,
            'pdf_filename': f'LR{lab_id_counter:06d}_{test_type.replace(" ", "_")}.pdf',
            'ordered_by_doctor_id': visit['doctor_id'],
            'status': random.choices(['Completed', 'Pending', 'Cancelled'], weights=[85, 10, 5], k=1)[0],
            'critical_flag': random.choices([True, False], weights=[10, 90], k=1)[0]
        }
        lab_results.append(lab_result)
        lab_id_counter += 1
    
    return pd.DataFrame(lab_results)


def generate_lab_result_pdf(lab_result, patient, center, output_dir):
    """Generate a lab result PDF"""
    filepath = output_dir / lab_result['pdf_filename']
    
    c = canvas.Canvas(str(filepath), pagesize=letter)
    width, height = letter
    
    # Header
    c.setFont("Helvetica-Bold", 16)
    c.drawString(1*inch, height - 1*inch, center['center_name'])
    c.setFont("Helvetica", 10)
    c.drawString(1*inch, height - 1.3*inch, f"{center['address']}, {center['city']}, {center['state']}")
    c.drawString(1*inch, height - 1.5*inch, f"Phone: {center['phone']}")
    
    # Title
    c.setFont("Helvetica-Bold", 14)
    c.drawString(1*inch, height - 2*inch, "LABORATORY RESULTS")
    
    # Patient Info
    c.setFont("Helvetica-Bold", 11)
    c.drawString(1*inch, height - 2.5*inch, "Patient Information:")
    c.setFont("Helvetica", 10)
    c.drawString(1*inch, height - 2.7*inch, f"Name: {patient['first_name']} {patient['last_name']}")
    c.drawString(1*inch, height - 2.9*inch, f"Patient ID: {patient['patient_id']}")
    c.drawString(1*inch, height - 3.1*inch, f"Date of Birth: {patient['date_of_birth']}")
    c.drawString(4*inch, height - 2.7*inch, f"Test Date: {lab_result['test_date']}")
    c.drawString(4*inch, height - 2.9*inch, f"Test Type: {lab_result['test_type']}")
    c.drawString(4*inch, height - 3.1*inch, f"Test Code (LOINC): {lab_result['test_code']}")
    
    # Results Table
    c.setFont("Helvetica-Bold", 11)
    c.drawString(1*inch, height - 3.6*inch, "Test Results:")
    
    # Table headers
    y = height - 4*inch
    c.setFont("Helvetica-Bold", 9)
    c.drawString(1*inch, y, "Test Component")
    c.drawString(3*inch, y, "Result")
    c.drawString(4*inch, y, "Reference Range")
    c.drawString(5.5*inch, y, "Flag")
    
    # Draw line
    c.line(1*inch, y-0.1*inch, 7*inch, y-0.1*inch)
    
    # Generate sample test results
    y -= 0.3*inch
    c.setFont("Helvetica", 9)
    
    # Generate 3-8 test components
    for i in range(random.randint(3, 8)):
        loinc_code = random.choice(list(LOINC_TESTS.keys()))
        test_name, unit, (ref_min, ref_max) = LOINC_TESTS[loinc_code]
        
        # Generate result value (70% normal, 20% high, 10% low)
        result_category = random.choices(['normal', 'high', 'low'], weights=[70, 20, 10], k=1)[0]
        
        if result_category == 'normal':
            result_value = round(random.uniform(ref_min, ref_max), 1)
            flag = ''
        elif result_category == 'high':
            result_value = round(random.uniform(ref_max, ref_max * 1.3), 1)
            flag = 'H'
        else:
            result_value = round(random.uniform(ref_min * 0.7, ref_min), 1)
            flag = 'L'
        
        c.drawString(1*inch, y, test_name)
        c.drawString(3*inch, y, f"{result_value} {unit}")
        c.drawString(4*inch, y, f"{ref_min}-{ref_max} {unit}")
        c.drawString(5.5*inch, y, flag)
        y -= 0.2*inch
    
    # Interpretation
    y -= 0.3*inch
    c.setFont("Helvetica-Bold", 10)
    c.drawString(1*inch, y, "Interpretation:")
    y -= 0.2*inch
    c.setFont("Helvetica", 9)
    
    if lab_result['critical_flag']:
        interpretation = "CRITICAL: Abnormal results require immediate physician review."
    else:
        interpretation = "Results within expected parameters. Physician will review and contact if needed."
    
    c.drawString(1*inch, y, interpretation)
    
    # Footer
    c.setFont("Helvetica", 8)
    c.drawString(1*inch, 1*inch, f"Report ID: {lab_result['lab_result_id']}")
    c.drawString(1*inch, 0.8*inch, f"Status: {lab_result['status']}")
    c.drawString(1*inch, 0.6*inch, "This is a computer-generated report.")
    
    c.save()


def generate_diagnostic_reports(visits_df, centers_df):
    """Generate diagnostic report metadata (30-40% of visits)"""
    print("Generating diagnostic reports metadata...")
    
    reports = []
    report_id_counter = 1
    
    # Sample 30-40% of visits for diagnostic imaging
    visits_with_imaging = visits_df.sample(frac=random.uniform(0.30, 0.40))
    
    modality_services = {
        'MRI': 'MRI',
        'CT': 'CT',
        'X-Ray': 'X-Ray',
        'Angiogram': 'Angiogram'
    }
    
    body_parts = {
        'MRI': ['Brain', 'Spine', 'Knee', 'Shoulder', 'Abdomen'],
        'CT': ['Head', 'Chest', 'Abdomen', 'Pelvis', 'Spine'],
        'X-Ray': ['Chest', 'Hand', 'Foot', 'Spine', 'Shoulder', 'Knee'],
        'Angiogram': ['Heart', 'Brain', 'Legs', 'Renal']
    }
    
    for _, visit in visits_with_imaging.iterrows():
        # Select modality
        exam_type = random.choice(list(modality_services.keys()))
        
        # Find center that offers this service
        suitable_centers = centers_df[centers_df['services_offered'].str.contains(modality_services[exam_type])]
        if suitable_centers.empty:
            continue
        center = suitable_centers.sample(1).iloc[0]
        
        # Select body part
        body_part = random.choice(body_parts[exam_type])
        
        # Exam date (0-14 days after visit)
        visit_date = datetime.strptime(visit['visit_date'], '%Y-%m-%d')
        exam_date = visit_date + timedelta(days=random.randint(0, 14))
        
        # Generate findings based on modality
        findings_templates = {
            'MRI': f'MRI of the {body_part} shows {random.choice(["normal findings", "mild degenerative changes", "unremarkable appearance"])}.',
            'CT': f'CT scan of the {body_part} demonstrates {random.choice(["no acute abnormality", "age-appropriate appearance", "normal findings"])}.',
            'X-Ray': f'X-ray of the {body_part} reveals {random.choice(["no acute fracture or dislocation", "normal bone alignment", "no significant abnormality"])}.',
            'Angiogram': f'Angiogram of {body_part} shows {random.choice(["patent vessels", "normal vascular anatomy", "no significant stenosis"])}.'
        }
        
        report = {
            'report_id': f'DR{report_id_counter:06d}',
            'patient_id': visit['patient_id'],
            'visit_id': visit['visit_id'],
            'center_id': center['center_id'],
            'exam_date': exam_date.strftime('%Y-%m-%d'),
            'exam_type': exam_type,
            'modality': exam_type,
            'body_part': body_part,
            'image_filename': f'DR{report_id_counter:06d}_{exam_type}_{body_part.replace(" ", "_")}.png',
            'findings': findings_templates[exam_type],
            'impression': random.choice([
                'No acute findings.',
                'Findings within normal limits.',
                'Recommend clinical correlation.',
                'Follow-up imaging recommended in 6-12 months.'
            ]),
            'radiologist_name': fake.name(),
            'critical_finding': random.choices([True, False], weights=[5, 95], k=1)[0]
        }
        reports.append(report)
        report_id_counter += 1
    
    return pd.DataFrame(reports)


def generate_diagnostic_image(report, patient, output_dir):
    """Generate a placeholder diagnostic image (PNG)"""
    filepath = output_dir / report['image_filename']
    
    # Create image (grayscale for X-Ray/CT, color for others)
    if report['modality'] in ['X-Ray', 'CT']:
        img = Image.new('L', (512, 512), color=random.randint(30, 80))
    else:
        img = Image.new('RGB', (512, 512), color=(random.randint(20, 60), random.randint(20, 60), random.randint(20, 60)))
    
    draw = ImageDraw.Draw(img)
    
    # Try to use a default font, fall back to default if not available
    try:
        font = ImageFont.truetype("arial.ttf", 20)
        small_font = ImageFont.truetype("arial.ttf", 14)
    except:
        font = ImageFont.load_default()
        small_font = ImageFont.load_default()
    
    # Add text overlay
    text_color = 'white' if report['modality'] in ['X-Ray', 'CT'] else (255, 255, 255)
    
    draw.text((20, 20), f"Patient ID: {patient['patient_id']}", fill=text_color, font=font)
    draw.text((20, 50), f"{report['modality']}: {report['body_part']}", fill=text_color, font=font)
    draw.text((20, 80), f"Date: {report['exam_date']}", fill=text_color, font=small_font)
    draw.text((20, 100), f"Report ID: {report['report_id']}", fill=text_color, font=small_font)
    
    # Add some noise pattern to simulate medical image
    for _ in range(1000):
        x, y = random.randint(0, 511), random.randint(0, 511)
        if report['modality'] in ['X-Ray', 'CT']:
            draw.point((x, y), fill=random.randint(100, 200))
        else:
            draw.point((x, y), fill=(random.randint(100, 200), random.randint(100, 200), random.randint(100, 200)))
    
    img.save(filepath)


def generate_insurance_claims(visits_df, patients_df):
    """Generate insurance claims (one per visit minimum)"""
    print("Generating insurance claims...")
    
    claims = []
    claim_id_counter = 1
    
    for _, visit in visits_df.iterrows():
        patient = patients_df[patients_df['patient_id'] == visit['patient_id']].iloc[0]
        
        # Select procedure code based on visit type
        if visit['visit_type'] in ['Routine', 'Follow-up']:
            procedure_code = '99213'
        elif visit['visit_type'] == 'Urgent Care':
            procedure_code = '99214'
        else:
            procedure_code = '99203'
        
        procedure_desc, base_amount = CPT_CODES[procedure_code]
        
        # Calculate amounts
        billed_amount = round(base_amount * random.uniform(0.95, 1.15), 2)
        allowed_amount = round(billed_amount * random.uniform(0.70, 0.90), 2)
        
        # Claim status (80% approved, 15% partial, 5% denied)
        claim_status = random.choices(
            ['Approved', 'Partially Approved', 'Denied', 'Pending'],
            weights=[80, 15, 3, 2],
            k=1
        )[0]
        
        if claim_status == 'Approved':
            insurance_paid = round(allowed_amount * 0.80, 2)
            patient_responsibility = round(allowed_amount * 0.20, 2)
            denial_reason = ''
        elif claim_status == 'Partially Approved':
            insurance_paid = round(allowed_amount * 0.50, 2)
            patient_responsibility = round(allowed_amount * 0.50, 2)
            denial_reason = ''
        elif claim_status == 'Denied':
            insurance_paid = 0.00
            patient_responsibility = billed_amount
            denial_reason = random.choice([
                'Pre-authorization required',
                'Not medically necessary',
                'Out of network provider',
                'Service not covered under plan'
            ])
        else:  # Pending
            insurance_paid = 0.00
            patient_responsibility = 0.00
            denial_reason = ''
        
        # Claim date (within 30 days of visit)
        visit_date = datetime.strptime(visit['visit_date'], '%Y-%m-%d')
        claim_date = visit_date + timedelta(days=random.randint(1, 30))
        claim_status_date = claim_date + timedelta(days=random.randint(5, 45))
        
        claim = {
            'claim_id': f'CL{claim_id_counter:06d}',
            'patient_id': visit['patient_id'],
            'visit_id': visit['visit_id'],
            'claim_date': claim_date.strftime('%Y-%m-%d'),
            'insurance_provider': patient['insurance_provider'],
            'policy_number': patient['insurance_policy_number'],
            'procedure_code': procedure_code,
            'procedure_description': procedure_desc,
            'diagnosis_code': visit['diagnosis_code'],
            'billed_amount': billed_amount,
            'allowed_amount': allowed_amount,
            'patient_responsibility': patient_responsibility,
            'insurance_paid': insurance_paid,
            'claim_status': claim_status,
            'claim_status_date': claim_status_date.strftime('%Y-%m-%d'),
            'denial_reason': denial_reason
        }
        claims.append(claim)
        claim_id_counter += 1
    
    return pd.DataFrame(claims)


def generate_prescriptions(visits_df, doctors_df):
    """Generate prescription metadata (60-70% of visits)"""
    print("Generating prescription metadata...")
    
    prescriptions = []
    rx_id_counter = 1
    
    # Sample 60-70% of visits for prescriptions
    visits_with_rx = visits_df.sample(frac=random.uniform(0.60, 0.70))
    
    for _, visit in visits_with_rx.iterrows():
        # Select 1-3 medications per visit
        n_meds = random.choices([1, 2, 3], weights=[60, 30, 10], k=1)[0]
        
        for _ in range(n_meds):
            medication_name = random.choice(list(MEDICATIONS.keys()))
            ndc_code, dosage, frequency, duration = MEDICATIONS[medication_name]
            
            prescription = {
                'prescription_id': f'RX{rx_id_counter:06d}',
                'patient_id': visit['patient_id'],
                'visit_id': visit['visit_id'],
                'doctor_id': visit['doctor_id'],
                'prescription_date': visit['visit_date'],
                'medication_name': medication_name,
                'ndc_code': ndc_code,
                'dosage': dosage,
                'frequency': frequency,
                'duration': duration,
                'refills': random.choice([0, 1, 2, 3, 6]),
                'pdf_filename': f'RX{rx_id_counter:06d}_{medication_name.replace(" ", "_")}.pdf'
            }
            prescriptions.append(prescription)
            rx_id_counter += 1
    
    return pd.DataFrame(prescriptions)


def generate_prescription_pdf(prescription, patient, doctor, output_dir):
    """Generate a prescription PDF"""
    filepath = output_dir / prescription['pdf_filename']
    
    c = canvas.Canvas(str(filepath), pagesize=letter)
    width, height = letter
    
    # Header
    c.setFont("Helvetica-Bold", 16)
    c.drawString(1*inch, height - 1*inch, "PRESCRIPTION")
    
    # Doctor Info
    c.setFont("Helvetica-Bold", 11)
    c.drawString(1*inch, height - 1.5*inch, "Prescriber Information:")
    c.setFont("Helvetica", 10)
    c.drawString(1*inch, height - 1.7*inch, f"Dr. {doctor['first_name']} {doctor['last_name']}, {doctor['specialty']}")
    c.drawString(1*inch, height - 1.9*inch, f"License: {doctor['license_number']}")
    c.drawString(1*inch, height - 2.1*inch, f"Phone: {doctor['phone']}")
    
    # Patient Info
    c.setFont("Helvetica-Bold", 11)
    c.drawString(1*inch, height - 2.6*inch, "Patient Information:")
    c.setFont("Helvetica", 10)
    c.drawString(1*inch, height - 2.8*inch, f"Name: {patient['first_name']} {patient['last_name']}")
    c.drawString(1*inch, height - 3.0*inch, f"Date of Birth: {patient['date_of_birth']}")
    c.drawString(1*inch, height - 3.2*inch, f"Address: {patient['address']}, {patient['city']}, {patient['state']} {patient['zip_code']}")
    
    # Date
    c.drawString(5*inch, height - 2.8*inch, f"Date: {prescription['prescription_date']}")
    c.drawString(5*inch, height - 3.0*inch, f"Rx #: {prescription['prescription_id']}")
    
    # Rx Symbol
    c.setFont("Helvetica-Bold", 24)
    c.drawString(1*inch, height - 3.8*inch, "℞")
    
    # Medication Details
    c.setFont("Helvetica-Bold", 12)
    c.drawString(1.5*inch, height - 3.8*inch, prescription['medication_name'])
    c.setFont("Helvetica", 11)
    c.drawString(1.5*inch, height - 4.1*inch, f"Strength: {prescription['dosage']}")
    c.drawString(1.5*inch, height - 4.3*inch, f"Quantity: {prescription['duration']}")
    c.drawString(1.5*inch, height - 4.5*inch, f"Refills: {prescription['refills']}")
    
    # Sig (Directions)
    c.setFont("Helvetica-Bold", 10)
    c.drawString(1*inch, height - 4.9*inch, "Sig:")
    c.setFont("Helvetica", 10)
    c.drawString(1.5*inch, height - 4.9*inch, f"Take {prescription['frequency']} for {prescription['duration']}")
    
    # NDC Code
    c.setFont("Helvetica", 8)
    c.drawString(1*inch, height - 5.3*inch, f"NDC: {prescription['ndc_code']}")
    
    # Signature line
    c.line(1*inch, height - 6*inch, 4*inch, height - 6*inch)
    c.setFont("Helvetica", 9)
    c.drawString(1*inch, height - 6.2*inch, "Prescriber Signature")
    c.drawString(1*inch, height - 6.4*inch, f"Dr. {doctor['first_name']} {doctor['last_name']}")
    
    # Footer
    c.setFont("Helvetica", 7)
    c.drawString(1*inch, 1*inch, "Dispense as written - Do not substitute")
    c.drawString(1*inch, 0.8*inch, "This prescription is valid for 12 months from the date issued")
    
    c.save()


def generate_clinical_notes(visits_df, doctors_df):
    """Generate clinical notes metadata"""
    print("Generating clinical notes metadata...")
    
    notes = []
    note_id_counter = 1
    
    # Every visit gets at least one clinical note
    for _, visit in visits_df.iterrows():
        # Main visit note (SOAP format)
        note = {
            'note_id': f'CN{note_id_counter:06d}',
            'patient_id': visit['patient_id'],
            'visit_id': visit['visit_id'],
            'doctor_id': visit['doctor_id'],
            'note_date': visit['visit_date'],
            'note_type': 'Clinical Note',
            'pdf_filename': f'CN{note_id_counter:06d}_Clinical_Note.pdf',
            'summary': f'SOAP note for {visit["chief_complaint"]}'
        }
        notes.append(note)
        note_id_counter += 1
        
        # 30% of visits get lifestyle recommendations
        if random.random() < 0.30:
            note = {
                'note_id': f'CN{note_id_counter:06d}',
                'patient_id': visit['patient_id'],
                'visit_id': visit['visit_id'],
                'doctor_id': visit['doctor_id'],
                'note_date': visit['visit_date'],
                'note_type': 'Lifestyle Recommendation',
                'pdf_filename': f'CN{note_id_counter:06d}_Lifestyle_Recommendation.pdf',
                'summary': 'Diet, exercise, and wellness recommendations'
            }
            notes.append(note)
            note_id_counter += 1
        
        # 20% of visits get physiotherapy notes
        if random.random() < 0.20:
            note = {
                'note_id': f'CN{note_id_counter:06d}',
                'patient_id': visit['patient_id'],
                'visit_id': visit['visit_id'],
                'doctor_id': visit['doctor_id'],
                'note_date': visit['visit_date'],
                'note_type': 'Physiotherapy Note',
                'pdf_filename': f'CN{note_id_counter:06d}_Physiotherapy_Note.pdf',
                'summary': 'Physical therapy evaluation and treatment plan'
            }
            notes.append(note)
            note_id_counter += 1
    
    return pd.DataFrame(notes)


def generate_clinical_note_pdf(note, patient, doctor, visit, output_dir):
    """Generate clinical documentation PDF"""
    filepath = output_dir / note['pdf_filename']
    
    c = canvas.Canvas(str(filepath), pagesize=letter)
    width, height = letter
    
    # Header
    c.setFont("Helvetica-Bold", 14)
    c.drawString(1*inch, height - 1*inch, f"{note['note_type'].upper()}")
    
    # Patient and Doctor Info
    c.setFont("Helvetica", 9)
    c.drawString(1*inch, height - 1.3*inch, f"Patient: {patient['first_name']} {patient['last_name']} (ID: {patient['patient_id']})")
    c.drawString(1*inch, height - 1.5*inch, f"DOB: {patient['date_of_birth']} | Age: {patient['age']}")
    c.drawString(1*inch, height - 1.7*inch, f"Provider: Dr. {doctor['first_name']} {doctor['last_name']}, {doctor['specialty']}")
    c.drawString(1*inch, height - 1.9*inch, f"Date: {note['note_date']}")
    
    y = height - 2.3*inch
    
    if note['note_type'] == 'Clinical Note':
        # SOAP Format
        c.setFont("Helvetica-Bold", 11)
        c.drawString(1*inch, y, "Subjective:")
        y -= 0.2*inch
        c.setFont("Helvetica", 9)
        c.drawString(1*inch, y, f"Chief Complaint: {visit['chief_complaint']}")
        y -= 0.15*inch
        c.drawString(1*inch, y, "Patient reports symptoms began approximately 2-3 weeks ago.")
        y -= 0.15*inch
        c.drawString(1*inch, y, "Denies fever, weight loss, or other systemic symptoms.")
        y -= 0.3*inch
        
        c.setFont("Helvetica-Bold", 11)
        c.drawString(1*inch, y, "Objective:")
        y -= 0.2*inch
        c.setFont("Helvetica", 9)
        c.drawString(1*inch, y, f"Vital Signs: BP {random.randint(110, 140)}/{random.randint(70, 90)}, HR {random.randint(60, 90)}, Temp {round(random.uniform(97.5, 98.9), 1)}°F")
        y -= 0.15*inch
        c.drawString(1*inch, y, "Physical Examination: Alert and oriented. No acute distress.")
        y -= 0.15*inch
        c.drawString(1*inch, y, "Examination findings consistent with presenting complaint.")
        y -= 0.3*inch
        
        c.setFont("Helvetica-Bold", 11)
        c.drawString(1*inch, y, "Assessment:")
        y -= 0.2*inch
        c.setFont("Helvetica", 9)
        c.drawString(1*inch, y, f"{visit['diagnosis_code']}: {visit['diagnosis_description']}")
        y -= 0.3*inch
        
        c.setFont("Helvetica-Bold", 11)
        c.drawString(1*inch, y, "Plan:")
        y -= 0.2*inch
        c.setFont("Helvetica", 9)
        c.drawString(1*inch, y, visit['treatment_plan'])
        y -= 0.15*inch
        c.drawString(1*inch, y, "Patient educated on condition and treatment plan.")
        y -= 0.15*inch
        c.drawString(1*inch, y, "Discussed warning signs and when to seek immediate care.")
        
    elif note['note_type'] == 'Lifestyle Recommendation':
        c.setFont("Helvetica-Bold", 11)
        c.drawString(1*inch, y, "Lifestyle and Wellness Recommendations")
        y -= 0.3*inch
        
        c.setFont("Helvetica-Bold", 10)
        c.drawString(1*inch, y, "Diet:")
        y -= 0.2*inch
        c.setFont("Helvetica", 9)
        c.drawString(1.3*inch, y, "• Increase intake of fruits and vegetables (5-7 servings daily)")
        y -= 0.15*inch
        c.drawString(1.3*inch, y, "• Reduce sodium intake to < 2000mg per day")
        y -= 0.15*inch
        c.drawString(1.3*inch, y, "• Maintain adequate hydration (8-10 glasses of water daily)")
        y -= 0.3*inch
        
        c.setFont("Helvetica-Bold", 10)
        c.drawString(1*inch, y, "Exercise:")
        y -= 0.2*inch
        c.setFont("Helvetica", 9)
        c.drawString(1.3*inch, y, "• Aim for 150 minutes of moderate aerobic activity per week")
        y -= 0.15*inch
        c.drawString(1.3*inch, y, "• Include strength training exercises 2-3 times per week")
        y -= 0.15*inch
        c.drawString(1.3*inch, y, "• Start slowly and gradually increase intensity")
        y -= 0.3*inch
        
        c.setFont("Helvetica-Bold", 10)
        c.drawString(1*inch, y, "Sleep Hygiene:")
        y -= 0.2*inch
        c.setFont("Helvetica", 9)
        c.drawString(1.3*inch, y, "• Maintain consistent sleep schedule (7-9 hours nightly)")
        y -= 0.15*inch
        c.drawString(1.3*inch, y, "• Limit screen time 1 hour before bed")
        y -= 0.15*inch
        c.drawString(1.3*inch, y, "• Create comfortable sleep environment")
        
    elif note['note_type'] == 'Physiotherapy Note':
        c.setFont("Helvetica-Bold", 11)
        c.drawString(1*inch, y, "Physical Therapy Evaluation")
        y -= 0.3*inch
        
        c.setFont("Helvetica-Bold", 10)
        c.drawString(1*inch, y, "Initial Assessment:")
        y -= 0.2*inch
        c.setFont("Helvetica", 9)
        c.drawString(1*inch, y, f"Patient presents with {visit['chief_complaint']}")
        y -= 0.15*inch
        c.drawString(1*inch, y, f"Functional limitations: Difficulty with daily activities")
        y -= 0.15*inch
        c.drawString(1*inch, y, f"Pain level: {random.randint(4, 8)}/10 on visual analog scale")
        y -= 0.3*inch
        
        c.setFont("Helvetica-Bold", 10)
        c.drawString(1*inch, y, "Treatment Plan:")
        y -= 0.2*inch
        c.setFont("Helvetica", 9)
        c.drawString(1.3*inch, y, "• Therapeutic exercises: Range of motion and strengthening")
        y -= 0.15*inch
        c.drawString(1.3*inch, y, "• Manual therapy techniques as indicated")
        y -= 0.15*inch
        c.drawString(1.3*inch, y, "• Home exercise program instruction")
        y -= 0.15*inch
        c.drawString(1.3*inch, y, f"• Frequency: 2-3x weekly for {random.randint(4, 8)} weeks")
        y -= 0.3*inch
        
        c.setFont("Helvetica-Bold", 10)
        c.drawString(1*inch, y, "Goals:")
        y -= 0.2*inch
        c.setFont("Helvetica", 9)
        c.drawString(1.3*inch, y, "• Reduce pain to 2/10 or less")
        y -= 0.15*inch
        c.drawString(1.3*inch, y, "• Improve functional mobility and independence")
        y -= 0.15*inch
        c.drawString(1.3*inch, y, "• Return to normal activities within 6-8 weeks")
    
    # Footer
    c.setFont("Helvetica", 7)
    c.drawString(1*inch, 1*inch, f"Note ID: {note['note_id']}")
    c.drawString(1*inch, 0.8*inch, "This document contains confidential patient health information.")
    
    c.save()


def main():
    parser = argparse.ArgumentParser(description='Generate synthetic healthcare datasets')
    parser.add_argument('--seed', type=int, default=42, help='Random seed for reproducibility')
    parser.add_argument('--output-dir', type=str, default='synthetic-healthcare-data', help='Output directory')
    parser.add_argument('--doctors', type=int, default=50, help='Number of doctors')
    parser.add_argument('--specialists', type=int, default=25, help='Number of specialist doctors')
    parser.add_argument('--centers', type=int, default=10, help='Number of diagnostic centers')
    parser.add_argument('--patients', type=int, default=100, help='Number of patients')
    
    args = parser.parse_args()
    
    # Set seed
    set_seed(args.seed)
    
    # Create output directories
    output_dir = Path(args.output_dir)
    csv_dir = output_dir / 'csv'
    pdf_lab_dir = output_dir / 'pdfs' / 'lab_results'
    pdf_rx_dir = output_dir / 'pdfs' / 'prescriptions'
    pdf_notes_dir = output_dir / 'pdfs' / 'clinical_notes'
    images_dir = output_dir / 'images'
    
    for directory in [csv_dir, pdf_lab_dir, pdf_rx_dir, pdf_notes_dir, images_dir]:
        directory.mkdir(parents=True, exist_ok=True)
    
    print("\n" + "="*60)
    print("SYNTHETIC HEALTHCARE DATA GENERATOR")
    print("="*60 + "\n")
    
    # Generate core datasets
    print("Phase 1: Generating core datasets...")
    doctors_df = generate_doctors(args.doctors, args.specialists)
    doctors_df.to_csv(csv_dir / 'doctors.csv', index=False)
    print(f"✓ Generated {len(doctors_df)} doctors")
    
    centers_df = generate_diagnostic_centers(args.centers)
    centers_df.to_csv(csv_dir / 'diagnostic_centers.csv', index=False)
    print(f"✓ Generated {len(centers_df)} diagnostic centers")
    
    patients_df = generate_patients(args.patients)
    patients_df.to_csv(csv_dir / 'patients.csv', index=False)
    print(f"✓ Generated {len(patients_df)} patients")
    
    # Generate visits
    print("\nPhase 2: Generating visits...")
    visits_df = generate_visits(patients_df, doctors_df)
    visits_df.to_csv(csv_dir / 'visits.csv', index=False)
    print(f"✓ Generated {len(visits_df)} visits")
    
    # Generate lab results
    print("\nPhase 3: Generating lab results...")
    lab_results_df = generate_lab_results(visits_df, centers_df, doctors_df)
    lab_results_df.to_csv(csv_dir / 'lab_results.csv', index=False)
    print(f"✓ Generated {len(lab_results_df)} lab result records")
    
    # Generate lab PDFs
    print("Generating lab result PDFs...")
    for idx, lab_result in lab_results_df[lab_results_df['status'] == 'Completed'].iterrows():
        patient = patients_df[patients_df['patient_id'] == lab_result['patient_id']].iloc[0]
        center = centers_df[centers_df['center_id'] == lab_result['center_id']].iloc[0]
        generate_lab_result_pdf(lab_result, patient, center, pdf_lab_dir)
        if (idx + 1) % 50 == 0:
            print(f"  Generated {idx + 1} lab PDFs...")
    print(f"✓ Generated {len(lab_results_df[lab_results_df['status'] == 'Completed'])} lab result PDFs")
    
    # Generate diagnostic reports
    print("\nPhase 4: Generating diagnostic reports...")
    diagnostic_reports_df = generate_diagnostic_reports(visits_df, centers_df)
    diagnostic_reports_df.to_csv(csv_dir / 'diagnostic_reports.csv', index=False)
    print(f"✓ Generated {len(diagnostic_reports_df)} diagnostic report records")
    
    # Generate diagnostic images
    print("Generating diagnostic images...")
    for idx, report in diagnostic_reports_df.iterrows():
        patient = patients_df[patients_df['patient_id'] == report['patient_id']].iloc[0]
        generate_diagnostic_image(report, patient, images_dir)
        if (idx + 1) % 50 == 0:
            print(f"  Generated {idx + 1} images...")
    print(f"✓ Generated {len(diagnostic_reports_df)} diagnostic images")
    
    # Generate insurance claims
    print("\nPhase 5: Generating insurance claims...")
    claims_df = generate_insurance_claims(visits_df, patients_df)
    claims_df.to_csv(csv_dir / 'insurance_claims.csv', index=False)
    print(f"✓ Generated {len(claims_df)} insurance claims")
    
    # Generate prescriptions
    print("\nPhase 6: Generating prescriptions...")
    prescriptions_df = generate_prescriptions(visits_df, doctors_df)
    prescriptions_df.to_csv(csv_dir / 'prescriptions.csv', index=False)
    print(f"✓ Generated {len(prescriptions_df)} prescription records")
    
    # Generate prescription PDFs
    print("Generating prescription PDFs...")
    for idx, prescription in prescriptions_df.iterrows():
        patient = patients_df[patients_df['patient_id'] == prescription['patient_id']].iloc[0]
        doctor = doctors_df[doctors_df['doctor_id'] == prescription['doctor_id']].iloc[0]
        generate_prescription_pdf(prescription, patient, doctor, pdf_rx_dir)
        if (idx + 1) % 50 == 0:
            print(f"  Generated {idx + 1} prescription PDFs...")
    print(f"✓ Generated {len(prescriptions_df)} prescription PDFs")
    
    # Generate clinical notes
    print("\nPhase 7: Generating clinical notes...")
    clinical_notes_df = generate_clinical_notes(visits_df, doctors_df)
    clinical_notes_df.to_csv(csv_dir / 'clinical_notes.csv', index=False)
    print(f"✓ Generated {len(clinical_notes_df)} clinical note records")
    
    # Generate clinical note PDFs
    print("Generating clinical note PDFs...")
    for idx, note in clinical_notes_df.iterrows():
        patient = patients_df[patients_df['patient_id'] == note['patient_id']].iloc[0]
        doctor = doctors_df[doctors_df['doctor_id'] == note['doctor_id']].iloc[0]
        visit = visits_df[visits_df['visit_id'] == note['visit_id']].iloc[0]
        generate_clinical_note_pdf(note, patient, doctor, visit, pdf_notes_dir)
        if (idx + 1) % 100 == 0:
            print(f"  Generated {idx + 1} clinical note PDFs...")
    print(f"✓ Generated {len(clinical_notes_df)} clinical note PDFs")
    
    # Summary
    print("\n" + "="*60)
    print("GENERATION COMPLETE!")
    print("="*60)
    print(f"\nDataset Summary:")
    print(f"  Doctors: {len(doctors_df)} ({args.specialists} specialists)")
    print(f"  Diagnostic Centers: {len(centers_df)}")
    print(f"  Patients: {len(patients_df)}")
    print(f"  Visits: {len(visits_df)}")
    print(f"  Lab Results: {len(lab_results_df)} ({len(lab_results_df[lab_results_df['status'] == 'Completed'])} PDFs)")
    print(f"  Diagnostic Reports: {len(diagnostic_reports_df)} ({len(diagnostic_reports_df)} images)")
    print(f"  Insurance Claims: {len(claims_df)}")
    print(f"  Prescriptions: {len(prescriptions_df)} ({len(prescriptions_df)} PDFs)")
    print(f"  Clinical Notes: {len(clinical_notes_df)} ({len(clinical_notes_df)} PDFs)")
    print(f"\nOutput directory: {output_dir.absolute()}")
    print("\nNext steps:")
    print("  1. Run validate_synthetic_data.py to verify data quality")
    print("  2. Review README.md for usage instructions")
    print("="*60 + "\n")


if __name__ == '__main__':
    main()
