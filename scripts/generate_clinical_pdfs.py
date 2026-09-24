"""
Generate synthetic clinical PDFs for the Care360 Copilot project.

No third-party dependencies: builds valid multi-page PDF files with a small
pure-Python writer (Helvetica base-14 font). Each document carries:
  - Document name
  - Patient ID
  - Date
  - Page number
  - Section title(s)
  - Clinical text

Run:  python scripts/generate_clinical_pdfs.py
"""

import os

BASE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "documents")

# ---------------------------------------------------------------------------
# Minimal PDF writer
# ---------------------------------------------------------------------------

PAGE_W, PAGE_H = 612, 792  # US Letter, points
MARGIN_L = 72
MARGIN_TOP = 720
LINE_H = 15
FONT_BODY = "F1"   # Helvetica
FONT_BOLD = "F2"   # Helvetica-Bold


def _esc(text):
    return text.replace("\\", r"\\").replace("(", r"\(").replace(")", r"\)")


class Line:
    def __init__(self, text, size=11, bold=False, gap_before=0):
        self.text = text
        self.size = size
        self.bold = bold
        self.gap_before = gap_before


def _wrap(text, max_chars):
    words = text.split()
    if not words:
        return [""]
    lines, cur = [], ""
    for w in words:
        cand = w if not cur else cur + " " + w
        if len(cand) <= max_chars:
            cur = cand
        else:
            if cur:
                lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return lines


def paginate(lines, lines_per_page=42):
    """Split a flat list of Line objects into pages (list of lists)."""
    pages, cur = [], []
    for ln in lines:
        if len(cur) >= lines_per_page:
            pages.append(cur)
            cur = []
        cur.append(ln)
    if cur:
        pages.append(cur)
    return pages


def _content_stream(page_lines, page_no, total_pages, footer):
    parts = ["BT", "/%s 11 Tf" % FONT_BODY]
    y = MARGIN_TOP
    parts.append("1 0 0 1 %d %d Tm" % (MARGIN_L, y))
    first = True
    for ln in page_lines:
        y -= LINE_H + ln.gap_before
        font = FONT_BOLD if ln.bold else FONT_BODY
        # Move text position absolutely each line for simplicity
        parts.append("ET")
        parts.append("BT")
        parts.append("/%s %d Tf" % (font, ln.size))
        parts.append("1 0 0 1 %d %d Tm" % (MARGIN_L, y))
        parts.append("(%s) Tj" % _esc(ln.text))
        first = False
    parts.append("ET")
    # Footer with page number
    parts.append("BT")
    parts.append("/%s 9 Tf" % FONT_BODY)
    parts.append("1 0 0 1 %d %d Tm" % (MARGIN_L, 40))
    parts.append("(%s) Tj" % _esc(footer))
    parts.append("ET")
    parts.append("BT")
    parts.append("/%s 9 Tf" % FONT_BODY)
    parts.append("1 0 0 1 %d %d Tm" % (PAGE_W - 140, 40))
    parts.append("(Page %d of %d) Tj" % (page_no, total_pages))
    parts.append("ET")
    return "\n".join(parts).encode("latin-1", "replace")


def write_pdf(path, all_lines, footer):
    pages = paginate(all_lines)
    total = len(pages)

    objects = []  # list of raw byte strings (object bodies without "N 0 obj")

    # Object numbering:
    # 1 Catalog, 2 Pages, 3 Font F1, 4 Font F2,
    # then per page: page obj + content obj
    font_f1 = 3
    font_f2 = 4
    page_obj_ids = []
    content_obj_ids = []
    next_id = 5
    for _ in pages:
        page_obj_ids.append(next_id)
        content_obj_ids.append(next_id + 1)
        next_id += 2

    kids = " ".join("%d 0 R" % pid for pid in page_obj_ids)

    obj_bodies = {}
    obj_bodies[1] = b"<< /Type /Catalog /Pages 2 0 R >>"
    obj_bodies[2] = ("<< /Type /Pages /Count %d /Kids [%s] >>" % (total, kids)).encode()
    obj_bodies[font_f1] = b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"
    obj_bodies[font_f2] = b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>"

    for i, page_lines in enumerate(pages):
        pid = page_obj_ids[i]
        cid = content_obj_ids[i]
        stream = _content_stream(page_lines, i + 1, total, footer)
        obj_bodies[cid] = (
            b"<< /Length %d >>\nstream\n" % len(stream) + stream + b"\nendstream"
        )
        page_dict = (
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %d %d] "
            "/Resources << /Font << /%s %d 0 R /%s %d 0 R >> >> "
            "/Contents %d 0 R >>"
            % (PAGE_W, PAGE_H, FONT_BODY, font_f1, FONT_BOLD, font_f2, cid)
        ).encode()
        obj_bodies[pid] = page_dict

    total_objs = next_id - 1

    # Assemble file with xref
    out = bytearray()
    out += b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n"
    offsets = {}
    for n in range(1, total_objs + 1):
        offsets[n] = len(out)
        out += ("%d 0 obj\n" % n).encode()
        out += obj_bodies[n]
        out += b"\nendobj\n"

    xref_pos = len(out)
    out += ("xref\n0 %d\n" % (total_objs + 1)).encode()
    out += b"0000000000 65535 f \n"
    for n in range(1, total_objs + 1):
        out += ("%010d 00000 n \n" % offsets[n]).encode()
    out += ("trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF"
            % (total_objs + 1, xref_pos)).encode()

    with open(path, "wb") as f:
        f.write(out)


# ---------------------------------------------------------------------------
# Document builders
# ---------------------------------------------------------------------------

def L(text, size=11, bold=False, gap=0):
    return Line(text, size=size, bold=bold, gap_before=gap)


def para(text, max_chars=95):
    return [L(w) for w in _wrap(text, max_chars)]


def header_block(doc_name, patient_id, date):
    lines = [
        L(doc_name, size=16, bold=True),
        L("Care360 Health System  |  Confidential Clinical Record", size=9, gap=2),
        L(""),
        L("Patient ID: %s" % patient_id, size=11, bold=True),
        L("Date: %s" % date, size=11, bold=True),
        L("-" * 92, size=10),
        L(""),
    ]
    return lines


def section(title):
    return [L(""), L(title, size=12, bold=True, gap=6)]


DOCS = []


def add(subdir, filename, doc_name, patient_id, date, builder):
    DOCS.append((subdir, filename, doc_name, patient_id, date, builder))


# ---- Clinical notes -------------------------------------------------------

def clinical_note_p1007():
    b = []
    b += header_block("Clinical Progress Note", "P1007", "2026-05-14")
    b += section("Section 1: Chief Complaint")
    b += para("Patient P1007 presents for a scheduled follow-up of type 2 diabetes "
              "mellitus and essential hypertension. Reports intermittent morning "
              "fatigue and mild bilateral lower-extremity swelling over the past two weeks.")
    b += section("Section 2: History of Present Illness")
    b += para("62-year-old established patient with a five-year history of type 2 "
              "diabetes (ICD-10 E11.9) and hypertension (ICD-10 I10). Home glucose "
              "logs show fasting values between 140 and 170 mg/dL. Reports adherence "
              "to metformin but occasional missed doses of lisinopril. Denies chest "
              "pain, dyspnea at rest, or visual changes.")
    b += section("Section 3: Objective / Vitals")
    b += para("BP 148/92 mmHg, HR 78 bpm, Temp 98.4 F, RR 16, SpO2 98% on room air. "
              "Weight 91.2 kg, BMI 31.4. Trace pedal edema bilaterally. Cardiac and "
              "pulmonary exam unremarkable.")
    b += section("Section 4: Assessment")
    b += para("1) Type 2 diabetes mellitus, suboptimally controlled - most recent "
              "HbA1c 8.1%. 2) Essential hypertension, above goal. 3) Mild peripheral "
              "edema, likely related to blood pressure control.")
    b += section("Section 5: Plan")
    b += para("Increase metformin to 1000 mg twice daily. Reinforce lisinopril "
              "adherence and increase to 20 mg daily. Order fasting lipid panel and "
              "basic metabolic panel. Diabetic foot exam performed. Follow up in "
              "eight weeks with repeat HbA1c. Patient counseled on diet and daily "
              "home BP monitoring.")
    return b


def discharge_summary_p1007():
    b = []
    b += header_block("Discharge Summary", "P1007", "2026-04-02")
    b += section("Section 1: Admission Details")
    b += para("Patient P1007 admitted 2026-03-29 through the emergency department "
              "with hyperglycemia and dehydration. Discharged 2026-04-02 to home in "
              "stable condition.")
    b += section("Section 2: Hospital Course")
    b += para("Presenting glucose 388 mg/dL without ketoacidosis. Treated with IV "
              "fluids and insulin correction. Blood pressure elevated on admission at "
              "162/98 mmHg, managed with existing oral agents. Renal function "
              "remained stable with creatinine 1.1 mg/dL throughout the stay.")
    b += section("Section 3: Discharge Diagnoses")
    b += para("1) Type 2 diabetes mellitus with hyperglycemia (E11.65). "
              "2) Essential hypertension (I10). 3) Volume depletion, resolved.")
    b += section("Section 4: Discharge Medications")
    b += para("Metformin 1000 mg twice daily. Lisinopril 20 mg daily. "
              "Atorvastatin 40 mg nightly. Aspirin 81 mg daily.")
    b += section("Section 5: Follow-up Instructions")
    b += para("Primary care follow-up within one week. Repeat HbA1c and basic "
              "metabolic panel in four weeks. Return precautions reviewed for "
              "recurrent hyperglycemia, confusion, or persistent vomiting.")
    return b


def medication_review_p1007():
    b = []
    b += header_block("Medication Review", "P1007", "2026-05-14")
    b += section("Section 1: Current Medication List")
    b += para("Metformin 1000 mg PO BID - indication: type 2 diabetes. "
              "Lisinopril 20 mg PO daily - indication: hypertension. "
              "Atorvastatin 40 mg PO nightly - indication: hyperlipidemia. "
              "Aspirin 81 mg PO daily - indication: cardiovascular prophylaxis.")
    b += section("Section 2: Adherence Assessment")
    b += para("Pharmacy refill data indicates approximately 80% adherence to "
              "lisinopril and full adherence to metformin. Patient reports "
              "occasional missed evening statin doses.")
    b += section("Section 3: Identified Gaps")
    b += para("Lisinopril refills remaining: 0 - refill authorization required. "
              "No documented gaps for metformin or atorvastatin. Recommend 90-day "
              "supply to improve adherence.")
    b += section("Section 4: Pharmacist Recommendations")
    b += para("Renew lisinopril and align refill dates across chronic medications. "
              "Consider once-daily combination therapy to reduce pill burden. "
              "Reinforce statin adherence counseling at next visit.")
    return b


# ---- Guidelines -----------------------------------------------------------

def diabetes_guideline():
    b = []
    b += header_block("Type 2 Diabetes Management Guideline 2026", "N/A (Reference)", "2026-01-01")
    b += section("Section 1: Screening and Diagnosis")
    b += para("Diagnose type 2 diabetes with HbA1c >= 6.5%, fasting plasma glucose "
              ">= 126 mg/dL, or a 2-hour plasma glucose >= 200 mg/dL during an oral "
              "glucose tolerance test. Confirm with repeat testing unless "
              "unequivocal hyperglycemia is present.")
    b += section("Section 2: Glycemic Targets")
    b += para("A general HbA1c goal of < 7.0% is recommended for most non-pregnant "
              "adults. Individualize targets to < 8.0% for patients with limited "
              "life expectancy, extensive comorbidities, or history of severe "
              "hypoglycemia.")
    b += section("Section 3: Pharmacologic Therapy")
    b += para("Metformin remains first-line therapy. Add a GLP-1 receptor agonist "
              "or SGLT2 inhibitor for patients with established cardiovascular or "
              "renal disease regardless of HbA1c. Escalate therapy every three "
              "months until targets are met.")
    b += section("Section 4: Monitoring")
    b += para("Measure HbA1c at least twice yearly for patients at goal and "
              "quarterly for those with therapy changes or above target. Perform "
              "annual urine albumin-to-creatinine ratio, eGFR, and comprehensive "
              "foot and dilated eye examinations.")
    return b


def hypertension_guideline():
    b = []
    b += header_block("Hypertension Management Guideline 2026", "N/A (Reference)", "2026-01-01")
    b += section("Section 1: Blood Pressure Classification")
    b += para("Normal: < 120/80 mmHg. Elevated: 120-129/<80 mmHg. Stage 1: "
              "130-139/80-89 mmHg. Stage 2: >= 140/90 mmHg. Diagnosis should be "
              "based on the average of two or more readings on separate occasions.")
    b += section("Section 2: Treatment Thresholds")
    b += para("Initiate pharmacologic therapy at >= 130/80 mmHg for patients with "
              "clinical cardiovascular disease or a 10-year ASCVD risk >= 10%. For "
              "others, treat at >= 140/90 mmHg alongside lifestyle modification.")
    b += section("Section 3: First-Line Agents")
    b += para("Preferred first-line classes include ACE inhibitors, ARBs, "
              "thiazide-type diuretics, and calcium channel blockers. For patients "
              "with diabetes and albuminuria, an ACE inhibitor or ARB is preferred.")
    b += section("Section 4: Follow-up and Monitoring")
    b += para("Reassess blood pressure monthly after initiating or changing therapy "
              "until control is achieved, then every three to six months. Encourage "
              "validated home blood pressure monitoring and review adherence at each "
              "visit.")
    return b


# ---- Regulatory -----------------------------------------------------------

def adverse_event_sop():
    b = []
    b += header_block("Adverse Event Reporting SOP", "N/A (Policy)", "2026-02-15")
    b += section("Section 1: Purpose and Scope")
    b += para("This standard operating procedure defines the process for "
              "identifying, documenting, and reporting adverse events and adverse "
              "drug reactions across all Care360 clinical settings.")
    b += section("Section 2: Definitions")
    b += para("An adverse event is any untoward medical occurrence in a patient "
              "regardless of causal relationship. A serious adverse event results in "
              "death, is life-threatening, requires hospitalization, or causes "
              "persistent disability.")
    b += section("Section 3: Reporting Timelines")
    b += para("Serious adverse events must be reported to the safety officer within "
              "24 hours of discovery. Non-serious events must be documented in the "
              "electronic health record within 72 hours. Regulatory submission "
              "follows applicable local and federal requirements.")
    b += section("Section 4: Documentation Requirements")
    b += para("Each report must include patient identifier, event date, description, "
              "suspected cause, severity, action taken, and outcome. Reference the "
              "source clinical note and any associated medication or lab record.")
    b += section("Section 5: Roles and Responsibilities")
    b += para("Clinicians identify and document events. The safety officer reviews "
              "and classifies reports. Quality committee performs monthly aggregate "
              "review and initiates corrective action where trends are identified.")
    return b


def clinical_documentation_policy():
    b = []
    b += header_block("Clinical Documentation Policy", "N/A (Policy)", "2026-02-15")
    b += section("Section 1: Policy Statement")
    b += para("All clinical care must be documented accurately, completely, and in a "
              "timely manner to support patient safety, continuity of care, and "
              "regulatory compliance.")
    b += section("Section 2: Timeliness")
    b += para("Progress notes must be completed within 24 hours of the encounter. "
              "Discharge summaries must be finalized within 48 hours of discharge. "
              "Verbal orders must be authenticated within 48 hours.")
    b += section("Section 3: Content Standards")
    b += para("Documentation must identify the patient by full name and patient ID, "
              "include the date and time of service, the author, and be legible and "
              "free of unapproved abbreviations. Each entry must support the "
              "diagnoses and services billed.")
    b += section("Section 4: Amendments and Corrections")
    b += para("Corrections must preserve the original entry, be clearly labeled as "
              "an amendment, and include the date, time, and author. Late entries "
              "must be identified as such and reference the original date of service.")
    b += section("Section 5: Confidentiality")
    b += para("All records are confidential and access is limited to authorized "
              "personnel with a legitimate treatment, payment, or operations need. "
              "Access is audited in accordance with privacy regulations.")
    return b


# ---------------------------------------------------------------------------
# Registration + generation
# ---------------------------------------------------------------------------

add("clinical_notes", "CLINICAL_NOTE_P1007.pdf", "Clinical Progress Note", "P1007", "2026-05-14", clinical_note_p1007)
add("clinical_notes", "DISCHARGE_SUMMARY_P1007.pdf", "Discharge Summary", "P1007", "2026-04-02", discharge_summary_p1007)
add("clinical_notes", "MEDICATION_REVIEW_P1007.pdf", "Medication Review", "P1007", "2026-05-14", medication_review_p1007)
add("guidelines", "DIABETES_GUIDELINE_2026.pdf", "Type 2 Diabetes Management Guideline 2026", "N/A", "2026-01-01", diabetes_guideline)
add("guidelines", "HYPERTENSION_GUIDELINE_2026.pdf", "Hypertension Management Guideline 2026", "N/A", "2026-01-01", hypertension_guideline)
add("regulatory", "ADVERSE_EVENT_SOP.pdf", "Adverse Event Reporting SOP", "N/A", "2026-02-15", adverse_event_sop)
add("regulatory", "CLINICAL_DOCUMENTATION_POLICY.pdf", "Clinical Documentation Policy", "N/A", "2026-02-15", clinical_documentation_policy)


def main():
    for sub in ("clinical_notes", "guidelines", "regulatory"):
        os.makedirs(os.path.join(BASE, sub), exist_ok=True)

    for subdir, filename, doc_name, patient_id, date, builder in DOCS:
        lines = builder()
        footer = "%s  |  Patient ID: %s  |  %s" % (doc_name, patient_id, date)
        path = os.path.join(BASE, subdir, filename)
        write_pdf(path, lines, footer)
        print("wrote %s (%d bytes)" % (os.path.relpath(path, BASE), os.path.getsize(path)))


if __name__ == "__main__":
    main()
