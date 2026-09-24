"""
Care360 Patient 360 Evidence Copilot
Streamlit-in-Snowflake application for clinical evidence retrieval with citations.

Screens: Patient Search -> Patient 360 -> Ask Copilot -> Evidence Panel
"""

import streamlit as st
import json
import os
from snowflake.snowpark import Session


@st.cache_resource
def get_snowpark_session():
    try:
        from snowflake.snowpark.context import get_active_session
        return get_active_session()
    except Exception:
        return Session.builder.configs({
            "account": os.environ.get("SNOWFLAKE_ACCOUNT", "JRMWQMS-PA19066"),
            "user": os.environ.get("SNOWFLAKE_USER", "sreejap"),
            "authenticator": "externalbrowser",
            "database": "CARE360_DB",
            "schema": "RAW",
            "warehouse": "CARE360_WH",
        }).create()


session = get_snowpark_session()

# -- Constants --
LLM_MODEL = "llama3.1-70b"
SEARCH_SERVICE = "CARE360_DB.DOCUMENTS.CLINICAL_DOCUMENT_SEARCH"
SEARCH_COLUMNS = [
    "TEXT_CONTENT", "DOCUMENT_TYPE", "PATIENT_ID", "DOCUMENT_NAME",
    "DOCUMENT_DATE", "PAGE_NUMBER", "SECTION_NAME", "CHUNK_ID",
]
NUM_SEARCH_RESULTS = 5

SYSTEM_PROMPT = """You are a clinical evidence assistant for a Patient 360 system.
Your role is to answer questions about patient records using ONLY the evidence provided.

RULES:
1. ONLY state facts that are directly supported by the provided evidence.
2. ALWAYS cite your sources using [Source: <type> | <date> | <detail>] format.
3. If the evidence does not contain enough information to answer, say so explicitly.
4. NEVER make medical predictions, diagnoses, or treatment recommendations.
5. NEVER speculate about information not present in the evidence.
6. If asked to predict outcomes or recommend treatments, politely decline and explain why.
7. Present information in a clear, organized format.
8. When presenting lab values, include the reference range and flag if abnormal.
9. ACTIVELY compare data from multiple sources. If a patient's current medication contradicts
   a guideline, or lab values conflict across visits, include a "Contradiction Detected" section.

REMINDER: This system uses SYNTHETIC data only. Not for clinical decision-making."""

# -- Page config --
st.set_page_config(page_title="Care360 Evidence Copilot", page_icon="🏥", layout="wide")

# -- Session state defaults --
if "screen" not in st.session_state:
    st.session_state.screen = "search"
if "selected_patient_id" not in st.session_state:
    st.session_state.selected_patient_id = None
if "chat_history" not in st.session_state:
    st.session_state.chat_history = []


# =============================================================================
# DATA ACCESS
# =============================================================================

@st.cache_data(ttl=300)
def get_patients():
    return session.sql("""
        SELECT patient_id, first_name, last_name,
               first_name || ' ' || last_name AS full_name,
               date_of_birth, gender, insurance_type, risk_score,
               city, state, pcp_name, smoking_status, bmi
        FROM CARE360_DB.RAW.PATIENTS
        ORDER BY last_name, first_name
    """).to_pandas()


@st.cache_data(ttl=120)
def get_patient_360(patient_id):
    return session.sql(f"""
        SELECT * FROM CARE360_DB.CURATED.PATIENT_360
        WHERE patient_id = '{patient_id}'
    """).to_pandas()


@st.cache_data(ttl=120)
def get_active_medications(patient_id):
    return session.sql(f"""
        SELECT medication_name, generic_name, dosage, frequency, route,
               start_date, end_date, prescribing_provider, indication,
               status, refills_remaining, drug_class
        FROM CARE360_DB.RAW.MEDICATIONS
        WHERE patient_id = '{patient_id}' AND status = 'Active'
        ORDER BY start_date DESC
    """).to_pandas()


@st.cache_data(ttl=120)
def get_recent_labs(patient_id, limit=20):
    return session.sql(f"""
        SELECT test_name, test_code, result_value, result_unit,
               reference_range_low, reference_range_high,
               abnormal_flag, lab_date, ordering_provider, category
        FROM CARE360_DB.RAW.LABS
        WHERE patient_id = '{patient_id}'
        ORDER BY lab_date DESC
        LIMIT {limit}
    """).to_pandas()


@st.cache_data(ttl=120)
def get_diagnosis_history(patient_id):
    return session.sql(f"""
        SELECT icd10_code, diagnosis_description, diagnosis_type,
               diagnosis_date, diagnosed_by, status, severity, is_chronic
        FROM CARE360_DB.RAW.DIAGNOSIS
        WHERE patient_id = '{patient_id}'
        ORDER BY diagnosis_date DESC
    """).to_pandas()


@st.cache_data(ttl=120)
def get_recent_visits(patient_id, limit=10):
    return session.sql(f"""
        SELECT visit_id, visit_date, visit_type, department, provider_name,
               chief_complaint, diagnosis_desc, discharge_disposition,
               length_of_stay_days
        FROM CARE360_DB.RAW.VISITS
        WHERE patient_id = '{patient_id}'
        ORDER BY visit_date DESC
        LIMIT {limit}
    """).to_pandas()


@st.cache_data(ttl=120)
def get_claims_summary(patient_id):
    return session.sql(f"""
        SELECT claim_id, claim_date, claim_type, cpt_code, cpt_description,
               billed_amount, paid_amount, claim_status, payer_name,
               denial_reason
        FROM CARE360_DB.RAW.CLAIMS
        WHERE patient_id = '{patient_id}'
        ORDER BY claim_date DESC
    """).to_pandas()


@st.cache_data(ttl=120)
def get_medication_gaps(patient_id):
    return session.sql(f"""
        SELECT medication_name, drug_class, dosage, frequency,
               medication_status, gap_type, gap_description, gap_priority,
               start_date, end_date, refills_remaining, indication
        FROM CARE360_DB.CURATED.PATIENT_MEDICATION_GAPS
        WHERE patient_id = '{patient_id}'
        ORDER BY gap_priority
    """).to_pandas()


@st.cache_data(ttl=120)
def get_followup_gaps(patient_id):
    return session.sql(f"""
        SELECT gap_type, gap_description, gap_priority,
               last_relevant_date, source_table
        FROM CARE360_DB.CURATED.PATIENT_FOLLOWUP_GAPS
        WHERE patient_id = '{patient_id}'
        ORDER BY gap_priority
    """).to_pandas()


# =============================================================================
# SEARCH & RAG
# =============================================================================

def search_clinical_docs(query, patient_id=None, limit=NUM_SEARCH_RESULTS):
    filter_obj = {}
    if patient_id:
        filter_obj = {"@eq": {"patient_id": patient_id}}

    query_params = json.dumps({
        "query": query,
        "columns": SEARCH_COLUMNS,
        "filter": filter_obj,
        "limit": limit,
    })
    escaped_params = query_params.replace("'", "''")

    search_sql = f"""
        SELECT PARSE_JSON(
            SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
                '{SEARCH_SERVICE}',
                '{escaped_params}'
            )
        ) AS results
    """
    try:
        result = session.sql(search_sql).collect()
        if result:
            parsed = json.loads(result[0]["RESULTS"])
            return parsed.get("results", [])
    except Exception as e:
        st.warning(f"Search service unavailable: {e}")
    return []


def build_evidence_context(search_results, structured_data=None):
    parts = []
    if structured_data:
        parts.append("=== STRUCTURED RECORDS ===")
        parts.append(structured_data)
    if search_results:
        parts.append("\n=== CLINICAL DOCUMENTS ===")
        for i, r in enumerate(search_results, 1):
            parts.append(
                f"\n[Document {i}] Type: {r.get('document_type', 'N/A')} | "
                f"Name: {r.get('document_name', 'N/A')} | "
                f"Date: {r.get('document_date', 'N/A')} | "
                f"Section: {r.get('section_name', 'N/A')}\n"
                f"{r.get('text_content', '')}"
            )
    return "\n".join(parts)


def format_structured_context(patient_id):
    parts = []
    meds = get_active_medications(patient_id)
    if not meds.empty:
        parts.append("Active Medications:")
        for _, row in meds.iterrows():
            parts.append(
                f"  - {row['MEDICATION_NAME']} {row['DOSAGE']} {row['FREQUENCY']} "
                f"(started {row['START_DATE']}, for {row['INDICATION']}, "
                f"class: {row['DRUG_CLASS']})"
            )

    labs = get_recent_labs(patient_id, limit=15)
    if not labs.empty:
        parts.append("\nRecent Lab Results:")
        for _, row in labs.iterrows():
            flag = ""
            if row["ABNORMAL_FLAG"] and str(row["ABNORMAL_FLAG"]).upper() not in ("N", "NORMAL", "NONE"):
                flag = f" [{row['ABNORMAL_FLAG']}]"
            ref = ""
            if row["REFERENCE_RANGE_LOW"] is not None and row["REFERENCE_RANGE_HIGH"] is not None:
                ref = f" (ref: {row['REFERENCE_RANGE_LOW']}-{row['REFERENCE_RANGE_HIGH']})"
            parts.append(
                f"  - {row['TEST_NAME']}: {row['RESULT_VALUE']} {row.get('RESULT_UNIT', '')}"
                f"{ref} on {row['LAB_DATE']}{flag}"
            )

    dx = get_diagnosis_history(patient_id)
    if not dx.empty:
        parts.append("\nDiagnoses:")
        for _, row in dx.iterrows():
            chronic = " [Chronic]" if str(row.get("IS_CHRONIC", "")).upper() == "TRUE" else ""
            parts.append(
                f"  - {row['DIAGNOSIS_DESCRIPTION']} ({row['ICD10_CODE']}) "
                f"- {row['STATUS']}, {row['SEVERITY']}{chronic} "
                f"diagnosed {row['DIAGNOSIS_DATE']} by {row['DIAGNOSED_BY']}"
            )

    return "\n".join(parts) if parts else None


def generate_answer(question, evidence_context):
    prompt = f"""{SYSTEM_PROMPT}

EVIDENCE:
{evidence_context}

QUESTION: {question}

Provide a clear, evidence-based answer with inline citations. If you detect contradictions
between patient data and clinical guidelines, flag them in a dedicated section."""

    escaped = prompt.replace("'", "''")
    sql = f"SELECT SNOWFLAKE.CORTEX.COMPLETE('{LLM_MODEL}', '{escaped}') AS answer"
    try:
        result = session.sql(sql).collect()
        if result:
            return result[0]["ANSWER"]
    except Exception as e:
        return f"Error generating answer: {e}"
    return "Unable to generate answer."


# =============================================================================
# NAVIGATION
# =============================================================================

def navigate_to(screen, patient_id=None):
    st.session_state.screen = screen
    if patient_id is not None:
        st.session_state.selected_patient_id = patient_id


# =============================================================================
# DISCLAIMER BANNER
# =============================================================================

def show_disclaimer():
    st.warning(
        "**Synthetic Data Only** — This application uses synthetic patient data "
        "for demonstration purposes. It is NOT intended for clinical decision-making. "
        "All patient records, lab values, and clinical documents are artificially generated.",
        icon="⚠️",
    )


# =============================================================================
# SCREEN 1: PATIENT SEARCH
# =============================================================================

def render_patient_search():
    st.title("Care360 Evidence Copilot")
    st.caption("Patient Search")
    show_disclaimer()

    patients_df = get_patients()
    if patients_df.empty:
        st.error("No patients found. Run the data pipeline first (setup.sql, pipeline.sql).")
        st.stop()

    col_search, col_filter = st.columns([2, 1])
    with col_search:
        search_term = st.text_input(
            "Search by Patient ID or Name",
            placeholder="e.g. PAT-001 or Martinez",
            key="patient_search_input",
        )
    with col_filter:
        risk_filter = st.multiselect(
            "Filter by Risk Score",
            options=sorted(patients_df["RISK_SCORE"].dropna().unique()),
            key="risk_filter",
        )

    filtered = patients_df.copy()
    if search_term:
        term = search_term.upper()
        filtered = filtered[
            filtered["PATIENT_ID"].str.upper().str.contains(term, na=False)
            | filtered["FULL_NAME"].str.upper().str.contains(term, na=False)
        ]
    if risk_filter:
        filtered = filtered[filtered["RISK_SCORE"].isin(risk_filter)]

    st.subheader(f"Patients ({len(filtered)})")

    for _, row in filtered.iterrows():
        risk = row.get("RISK_SCORE", "Unknown")
        risk_color = {"High": "red", "Medium": "orange", "Low": "green"}.get(risk, "gray")

        with st.container(border=True):
            c1, c2, c3, c4 = st.columns([2, 2, 1, 1])
            with c1:
                st.markdown(f"**{row['FULL_NAME']}**")
                st.caption(f"{row['PATIENT_ID']} | {row['GENDER']} | DOB: {row['DATE_OF_BIRTH']}")
            with c2:
                st.caption(
                    f"PCP: {row.get('PCP_NAME', 'N/A')} | "
                    f"Insurance: {row.get('INSURANCE_TYPE', 'N/A')}"
                )
                st.caption(
                    f"BMI: {row.get('BMI', 'N/A')} | "
                    f"Smoking: {row.get('SMOKING_STATUS', 'N/A')}"
                )
            with c3:
                st.markdown(f"Risk: :{risk_color}[**{risk}**]")
            with c4:
                if st.button("View 360", key=f"view_{row['PATIENT_ID']}"):
                    navigate_to("dashboard", row["PATIENT_ID"])
                    st.rerun()


# =============================================================================
# SCREEN 2: PATIENT 360 DASHBOARD
# =============================================================================

def render_patient_360():
    pid = st.session_state.selected_patient_id
    if not pid:
        navigate_to("search")
        st.rerun()

    p360 = get_patient_360(pid)
    if p360.empty:
        st.error(f"No Patient 360 data found for {pid}. Ensure the CURATED views exist.")
        if st.button("Back to Search"):
            navigate_to("search")
            st.rerun()
        st.stop()

    s = p360.iloc[0]

    # -- Header --
    col_back, col_title = st.columns([1, 8])
    with col_back:
        if st.button("< Back"):
            navigate_to("search")
            st.rerun()
    with col_title:
        st.title(f"{s['FULL_NAME']}")
        st.caption(
            f"{pid} | {s['GENDER']} | Age: {s['AGE']} | "
            f"DOB: {s['DATE_OF_BIRTH']} | Insurance: {s['INSURANCE_TYPE']} | "
            f"Risk: {s.get('CARE_GAP_RISK_LEVEL', 'N/A')}"
        )

    show_disclaimer()

    # -- KPI row --
    k1, k2, k3, k4, k5, k6 = st.columns(6)
    k1.metric("Total Visits", int(s["TOTAL_VISITS"]))
    k2.metric("Active Meds", int(s["ACTIVE_MEDICATION_COUNT"]))
    k3.metric("Abnormal Labs", int(s["ABNORMAL_LAB_COUNT"]))
    k4.metric("Active Diagnoses", int(s["ACTIVE_DIAGNOSIS_COUNT"]))
    k5.metric("Denied Claims", int(s["DENIED_CLAIM_COUNT"]))
    k6.metric("Care Gaps", int(s.get("FOLLOWUP_GAP_COUNT", 0)) + int(s.get("MEDICATION_GAP_COUNT", 0)))

    st.divider()

    # -- Tabs --
    tab_dx, tab_meds, tab_labs, tab_visits, tab_gaps, tab_claims = st.tabs(
        ["Diagnoses", "Medications", "Labs", "Visits", "Care Gaps", "Claims"]
    )

    with tab_dx:
        dx = get_diagnosis_history(pid)
        if dx.empty:
            st.info("No diagnosis records found.")
        else:
            chronic = dx[dx["IS_CHRONIC"].astype(str).str.upper() == "TRUE"]
            if not chronic.empty:
                st.markdown("**Chronic Conditions**")
                for _, row in chronic.iterrows():
                    st.markdown(
                        f"- **{row['DIAGNOSIS_DESCRIPTION']}** ({row['ICD10_CODE']}) "
                        f"— {row['SEVERITY']} | Since {row.get('DIAGNOSIS_DATE', 'N/A')}"
                    )
                st.divider()
            st.markdown("**All Diagnoses**")
            st.dataframe(
                dx[["ICD10_CODE", "DIAGNOSIS_DESCRIPTION", "STATUS", "SEVERITY",
                    "DIAGNOSIS_DATE", "DIAGNOSED_BY"]],
                use_container_width=True, hide_index=True,
            )

    with tab_meds:
        meds = get_active_medications(pid)
        if meds.empty:
            st.info("No active medications.")
        else:
            for _, row in meds.iterrows():
                with st.container(border=True):
                    mc1, mc2 = st.columns([3, 2])
                    with mc1:
                        st.markdown(f"**{row['MEDICATION_NAME']}** ({row['GENERIC_NAME']})")
                        st.caption(
                            f"{row['DOSAGE']} | {row['ROUTE']} | {row['FREQUENCY']}"
                        )
                    with mc2:
                        st.caption(f"For: {row['INDICATION']} | Class: {row['DRUG_CLASS']}")
                        st.caption(
                            f"Since: {row['START_DATE']} | "
                            f"Refills: {row.get('REFILLS_REMAINING', 'N/A')} | "
                            f"Rx: {row['PRESCRIBING_PROVIDER']}"
                        )
            med_gaps = get_medication_gaps(pid)
            if not med_gaps.empty:
                st.divider()
                st.markdown("**Medication Gaps**")
                for _, g in med_gaps.iterrows():
                    icon = {"HIGH": "🔴", "MEDIUM": "🟡"}.get(g["GAP_PRIORITY"], "🟢")
                    st.markdown(f"{icon} **{g['GAP_TYPE']}**: {g['GAP_DESCRIPTION']}")

    with tab_labs:
        labs = get_recent_labs(pid)
        if labs.empty:
            st.info("No lab results found.")
        else:
            abnormal = labs[labs["ABNORMAL_FLAG"].astype(str).str.upper().isin(["HIGH", "H", "HH", "LOW", "L", "LL"])]
            if not abnormal.empty:
                st.markdown(f"**Abnormal Results ({len(abnormal)})**")
                st.dataframe(
                    abnormal[["TEST_NAME", "RESULT_VALUE", "RESULT_UNIT",
                              "REFERENCE_RANGE_LOW", "REFERENCE_RANGE_HIGH",
                              "ABNORMAL_FLAG", "LAB_DATE"]],
                    use_container_width=True, hide_index=True,
                )
                st.divider()
            st.markdown("**All Recent Labs**")
            st.dataframe(
                labs[["TEST_NAME", "RESULT_VALUE", "RESULT_UNIT",
                      "REFERENCE_RANGE_LOW", "REFERENCE_RANGE_HIGH",
                      "ABNORMAL_FLAG", "LAB_DATE", "ORDERING_PROVIDER", "CATEGORY"]],
                use_container_width=True, hide_index=True,
            )

    with tab_visits:
        visits = get_recent_visits(pid)
        if visits.empty:
            st.info("No visits found.")
        else:
            st.dataframe(
                visits[["VISIT_DATE", "VISIT_TYPE", "DEPARTMENT", "PROVIDER_NAME",
                        "CHIEF_COMPLAINT", "DIAGNOSIS_DESC", "DISCHARGE_DISPOSITION"]],
                use_container_width=True, hide_index=True,
            )

    with tab_gaps:
        fu_gaps = get_followup_gaps(pid)
        med_gaps = get_medication_gaps(pid)
        if fu_gaps.empty and med_gaps.empty:
            st.success("No care gaps identified for this patient.")
        else:
            if not fu_gaps.empty:
                st.markdown("**Follow-up Gaps**")
                for _, g in fu_gaps.iterrows():
                    icon = {"HIGH": "🔴", "MEDIUM": "🟡"}.get(g["GAP_PRIORITY"], "🟢")
                    st.markdown(
                        f"{icon} **{g['GAP_TYPE']}**: {g['GAP_DESCRIPTION']} "
                        f"(Last: {g.get('LAST_RELEVANT_DATE', 'N/A')})"
                    )
            if not med_gaps.empty:
                if not fu_gaps.empty:
                    st.divider()
                st.markdown("**Medication Gaps**")
                for _, g in med_gaps.iterrows():
                    icon = {"HIGH": "🔴", "MEDIUM": "🟡"}.get(g["GAP_PRIORITY"], "🟢")
                    st.markdown(f"{icon} **{g['GAP_TYPE']}**: {g['GAP_DESCRIPTION']}")

    with tab_claims:
        claims = get_claims_summary(pid)
        if claims.empty:
            st.info("No claims found.")
        else:
            denied = claims[claims["CLAIM_STATUS"].astype(str).str.upper() == "DENIED"]
            if not denied.empty:
                st.markdown(f"**Denied Claims ({len(denied)})**")
                st.dataframe(
                    denied[["CLAIM_DATE", "CPT_CODE", "CPT_DESCRIPTION",
                            "BILLED_AMOUNT", "CLAIM_STATUS", "DENIAL_REASON"]],
                    use_container_width=True, hide_index=True,
                )
                st.divider()
            st.markdown("**All Claims**")
            st.dataframe(
                claims[["CLAIM_DATE", "CLAIM_TYPE", "CPT_CODE", "CPT_DESCRIPTION",
                        "BILLED_AMOUNT", "PAID_AMOUNT", "CLAIM_STATUS", "PAYER_NAME"]],
                use_container_width=True, hide_index=True,
            )

    st.divider()

    if st.button("Ask the Copilot a Question About This Patient", type="primary", use_container_width=True):
        navigate_to("copilot")
        st.rerun()


# =============================================================================
# SCREEN 3: ASK COPILOT + SCREEN 4: EVIDENCE PANEL
# =============================================================================

def render_copilot():
    pid = st.session_state.selected_patient_id
    if not pid:
        navigate_to("search")
        st.rerun()

    p360 = get_patient_360(pid)
    patient_name = p360.iloc[0]["FULL_NAME"] if not p360.empty else pid

    # -- Header --
    col_back, col_title = st.columns([1, 8])
    with col_back:
        if st.button("< Dashboard"):
            navigate_to("dashboard")
            st.rerun()
    with col_title:
        st.title("Clinical Evidence Copilot")
        st.caption(f"Patient: {patient_name} ({pid})")

    show_disclaimer()

    # -- Example questions --
    examples = [
        "Summarize this patient's active diagnoses and recent lab trends",
        "What medications is this patient on and are there any gaps or concerns?",
        "Show recent lab results and flag anything abnormal with reference ranges",
        "What did the clinical documents say about follow-up care?",
        "Are there any contradictions between current medications and lab results?",
    ]
    with st.expander("Example questions", expanded=False):
        for q in examples:
            if st.button(q, key=f"ex_{q[:20]}"):
                st.session_state.copilot_question = q
                st.rerun()

    # -- Question input --
    question = st.chat_input("Ask a clinical question about this patient...")

    if "copilot_question" in st.session_state:
        question = st.session_state.pop("copilot_question")

    # -- Chat history --
    for entry in st.session_state.chat_history:
        if entry["patient_id"] == pid:
            with st.chat_message("user"):
                st.markdown(entry["question"])
            with st.chat_message("assistant"):
                st.markdown(entry["answer"])
                if entry.get("contradictions"):
                    st.error(entry["contradictions"], icon="⚠️")
                if entry.get("citations"):
                    render_evidence_panel(entry["citations"])
                st.caption("_Based on synthetic data and cited evidence only. Not a clinical recommendation._")

    if question:
        with st.chat_message("user"):
            st.markdown(question)

        with st.chat_message("assistant"):
            with st.spinner("Searching evidence and generating answer..."):
                search_results = search_clinical_docs(question, patient_id=pid)
                structured_context = format_structured_context(pid)
                evidence = build_evidence_context(search_results, structured_context)
                answer = generate_answer(question, evidence)

            st.markdown(answer)

            # -- Contradiction detection --
            contradiction_text = None
            if any(phrase in answer.lower() for phrase in [
                "contradiction", "conflict", "inconsisten", "discrepan",
                "contraindicated", "does not align",
            ]):
                contradiction_text = (
                    "**Potential contradictions detected in the response above.** "
                    "A clinician should review the flagged items before taking action."
                )
                st.error(contradiction_text, icon="⚠️")

            # -- Evidence panel --
            if search_results:
                render_evidence_panel(search_results)

            st.caption("_Based on synthetic data and cited evidence only. Not a clinical recommendation._")

            st.session_state.chat_history.append({
                "patient_id": pid,
                "question": question,
                "answer": answer,
                "citations": search_results if search_results else None,
                "contradictions": contradiction_text,
            })


def render_evidence_panel(citations):
    with st.expander(f"Cited Evidence ({len(citations)} sources)", expanded=False):
        for i, r in enumerate(citations, 1):
            st.markdown(
                f"**[{i}] {r.get('document_type', 'N/A')}** — "
                f"{r.get('document_name', 'N/A')}"
            )
            st.caption(
                f"Date: {r.get('document_date', 'N/A')} | "
                f"Section: {r.get('section_name', 'N/A')} | "
                f"Page: {r.get('page_number', 'N/A')}"
            )
            st.text(str(r.get("text_content", ""))[:600])
            if i < len(citations):
                st.divider()


# =============================================================================
# SIDEBAR NAVIGATION
# =============================================================================

with st.sidebar:
    st.markdown("### Care360 Copilot")
    st.divider()

    if st.button("Patient Search", use_container_width=True):
        navigate_to("search")
        st.rerun()

    pid = st.session_state.selected_patient_id
    if pid:
        st.caption(f"Selected: **{pid}**")
        if st.button("Patient 360", use_container_width=True):
            navigate_to("dashboard")
            st.rerun()
        if st.button("Ask Copilot", use_container_width=True):
            navigate_to("copilot")
            st.rerun()

    st.divider()
    st.caption(
        "Powered by Snowflake Cortex\n\n"
        "LLM: mistral-large2\n\n"
        "Search: Cortex Search"
    )


# =============================================================================
# ROUTER
# =============================================================================

screen = st.session_state.screen
if screen == "search":
    render_patient_search()
elif screen == "dashboard":
    render_patient_360()
elif screen == "copilot":
    render_copilot()
else:
    render_patient_search()
