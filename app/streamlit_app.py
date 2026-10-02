"""
Care360 Evidence Copilot — Streamlit in Snowflake application.

Canonical database: PATIENT360.
Synthetic data only — no real PHI.
This tool does not diagnose, does not predict outcomes, and does not recommend treatment.
"""

import json

import streamlit as st
from snowflake.snowpark import Session
from snowflake.snowpark.context import get_active_session
from snowflake.snowpark.exceptions import SnowparkSQLException

DB = "PATIENT360"
ANALYTICS = f"{DB}.ANALYTICS"
SEARCH_SERVICE = f"{DB}.DOCUMENTS.DOCUMENT_SEARCH_SERVICE"

PERSONAS = {
    "CARE_COORDINATOR": {
        "label": "Primary Care Physician",
        "icon": "🩺",
        "desc": "Full patient record, encounters, medications, labs, claims, and clinical documents.",
        "semantic_view": f"{ANALYTICS}.PATIENT360_SEM_CARE_COORDINATOR",
        "views": {
            "patient": f"{ANALYTICS}.PERSONA_CC_PATIENT",
            "encounter": f"{ANALYTICS}.PERSONA_CC_ENCOUNTER",
            "medication": f"{ANALYTICS}.PERSONA_CC_MEDICATION",
            "lab": f"{ANALYTICS}.PERSONA_CC_LAB",
            "claim": f"{ANALYTICS}.PERSONA_CC_CLAIM",
            "care_gap": f"{ANALYTICS}.PERSONA_CC_CARE_GAP",
            "evidence": f"{ANALYTICS}.PERSONA_CC_EVIDENCE",
        },
        "doc_categories": ("CLINICAL_NOTE", "LAB_DOCUMENT", "PRESCRIPTION", "DIAGNOSTIC_IMAGE"),
        "doc_text": True,
    },
    "QUALITY_ANALYST": {
        "label": "Claims Analyst",
        "icon": "📋",
        "desc": "Claims status, documentation audit, lab monitoring, and care gap tracking.",
        "semantic_view": f"{ANALYTICS}.PATIENT360_SEM_QUALITY_ANALYST",
        "views": {
            "patient": f"{ANALYTICS}.PERSONA_QA_PATIENT",
            "encounter": f"{ANALYTICS}.PERSONA_QA_ENCOUNTER",
            "lab": f"{ANALYTICS}.PERSONA_QA_LAB",
            "claim": f"{ANALYTICS}.PERSONA_QA_CLAIM",
            "care_gap": f"{ANALYTICS}.PERSONA_QA_CARE_GAP",
            "evidence": f"{ANALYTICS}.PERSONA_QA_EVIDENCE",
            "pipeline_quality": f"{ANALYTICS}.PERSONA_QA_INGESTION_QUALITY",
        },
        "doc_categories": ("CLINICAL_NOTE", "LAB_DOCUMENT", "PRESCRIPTION", "DIAGNOSTIC_IMAGE"),
        "doc_text": False,
    },
    "PATIENT_SELF": {
        "label": "Patient",
        "icon": "👤",
        "desc": "Your health summary, visit history, medications, labs, and care alerts.",
        "semantic_view": f"{ANALYTICS}.PATIENT360_SEM_PATIENT",
        "views": {
            "patient": f"{ANALYTICS}.PERSONA_PT_PATIENT",
            "encounter": f"{ANALYTICS}.PERSONA_PT_ENCOUNTER",
            "medication": f"{ANALYTICS}.PERSONA_PT_MEDICATION",
            "lab": f"{ANALYTICS}.PERSONA_PT_LAB",
            "care_gap": f"{ANALYTICS}.PERSONA_PT_CARE_GAP",
        },
        "doc_categories": (),
        "doc_text": False,
    },
    "PHARMACIST": {
        "label": "Clinical Pharmacist",
        "icon": "💊",
        "desc": "Medication safety review, drug interactions, lab checks, and prescription history.",
        "semantic_view": f"{ANALYTICS}.PATIENT360_SEM_PHARMACIST",
        "views": {
            "patient": f"{ANALYTICS}.PERSONA_RX_PATIENT",
            "medication": f"{ANALYTICS}.PERSONA_RX_MEDICATION",
            "lab": f"{ANALYTICS}.PERSONA_RX_LAB",
            "claim": f"{ANALYTICS}.PERSONA_RX_CLAIM",
            "care_gap": f"{ANALYTICS}.PERSONA_RX_CARE_GAP",
            "evidence": f"{ANALYTICS}.PERSONA_RX_EVIDENCE",
        },
        "doc_categories": ("PRESCRIPTION", "LAB_DOCUMENT", "CLINICAL_NOTE"),
        "doc_text": True,
    },
}

SAMPLE_QUESTIONS = {
    "CARE_COORDINATOR": [
        "What medications is this patient currently on?",
        "Show me the recent visit history",
        "Are there any critical lab results?",
        "What care gaps exist for this patient?",
    ],
    "QUALITY_ANALYST": [
        "How many claims were denied and why?",
        "Which patients are missing follow-up labs?",
        "Show lab monitoring evidence by test type",
        "What is the overall documentation quality?",
    ],
    "PATIENT_SELF": [
        "What medications am I taking?",
        "When was my last visit?",
        "Do I have any upcoming follow-ups?",
        "What lab tests have been done?",
    ],
    "PHARMACIST": [
        "What are the most prescribed medications?",
        "Which prescriptions had no prior lab check?",
        "Show all denied claims with reasons",
        "What critical lab results exist?",
    ],
}

REFUSAL_TERMS = (  # constitution-exempt: safety-guardrail
    "diagnose", "diagnosis for", "what condition does", "prognosis", "life expectancy",  # constitution-exempt: safety-guardrail
    "will the patient", "should i prescribe", "recommend treatment", "what treatment",  # constitution-exempt: safety-guardrail
    "how long will", "predict",
)


# ---------------------------------------------------------------------------
# Session helpers
# ---------------------------------------------------------------------------
@st.cache_resource
def get_session():
    """Return a Snowpark session.

    Inside Streamlit in Snowflake the session already exists. When the app is
    hosted outside Snowflake (for example Streamlit Community Cloud) there is
    no active session, so one is built from st.secrets instead.
    """
    try:
        return get_active_session()
    except Exception:
        pass

    if "snowflake" not in st.secrets:
        st.error(
            "No Snowflake connection available. This app is running outside "
            "Snowflake, so it needs credentials in Streamlit secrets under a "
            "[snowflake] section. See .streamlit/secrets.toml.example."
        )
        st.stop()

    cfg = {k: v for k, v in dict(st.secrets["snowflake"]).items() if k != "pat"}
    try:
        return Session.builder.configs(cfg).create()
    except Exception as exc:
        st.error(f"Could not connect to Snowflake: {exc}")
        st.stop()


def _running_in_snowflake():
    """True when executing inside Streamlit in Snowflake."""
    try:
        import _snowflake  # noqa: F401

        return True
    except ImportError:
        return False


@st.cache_data(ttl=600)
def session_context():
    row = get_session().sql(
        "SELECT CURRENT_USER() AS u, CURRENT_ROLE() AS r, CURRENT_SESSION() AS s"
    ).collect()[0]
    return {"user": row["U"], "role": row["R"], "session": str(row["S"])}


def run_query(sql, params=None):
    try:
        return get_session().sql(sql, params=params or []).to_pandas()
    except SnowparkSQLException as exc:
        st.error(f"Query error: {exc.message}")
        return None


def audit(persona, action, target=None, patient_id=None, question=None, row_count=None, outcome="SUCCESS"):
    ctx = session_context()
    try:
        get_session().sql(
            f"""INSERT INTO {ANALYTICS}.APP_ACCESS_AUDIT
              (session_id, user_identity, active_role, persona_code, persona_resolution,
               action, target_object, patient_id, question_text, row_count, outcome)
            SELECT ?, ?, ?, ?, 'SELECTOR', ?, ?, ?, ?, ?, ?""",
            params=[ctx["session"], ctx["user"], ctx["role"], persona,
                    action, target, patient_id, question, row_count, outcome],
        ).collect()
    except SnowparkSQLException:
        pass


def safe_df(df):
    if df is None or df.empty:
        return False
    try:
        st.dataframe(df, use_container_width=True, hide_index=True)
    except TypeError:
        st.dataframe(df, use_container_width=True)
    return True


def safe_text(text):
    if text:
        st.markdown(text)


@st.cache_data(ttl=600)
def get_patient_list(view):
    df = get_session().sql(f"SELECT patient_id, first_name, last_name FROM {view} ORDER BY patient_id").to_pandas()
    return df


# ---------------------------------------------------------------------------
# Visual dashboard components
# ---------------------------------------------------------------------------
def render_patient_summary(cfg, persona, pid):
    view = cfg["views"].get("patient")
    if not view or not pid:
        return
    df = run_query(f"SELECT * FROM {view} WHERE patient_id = ?", [pid])
    if df is None or df.empty:
        st.warning("No patient record found.")
        return
    audit(persona, "VIEW_PATIENT", view, pid, row_count=1)
    row = df.iloc[0]
    cols = df.columns.tolist()

    name = ""
    if "FIRST_NAME" in cols and "LAST_NAME" in cols:
        name = f"{row.get('FIRST_NAME', '')} {row.get('LAST_NAME', '')}"
    st.subheader(f"Patient {pid}" + (f" — {name}" if name else ""))

    mc = st.columns(4)
    if "TOTAL_VISITS" in cols:
        mc[0].metric("Visits", int(row.get("TOTAL_VISITS", 0)))
    if "TOTAL_PRESCRIPTIONS" in cols:
        mc[1].metric("Medications", int(row.get("TOTAL_PRESCRIPTIONS", 0)))
    if "TOTAL_LABS" in cols:
        mc[2].metric("Lab Results", int(row.get("TOTAL_LABS", 0)))
    if "CRITICAL_LAB_COUNT" in cols:
        mc[3].metric("Critical Labs", int(row.get("CRITICAL_LAB_COUNT", 0)))
    elif "TOTAL_CLAIMS" in cols:
        mc[3].metric("Claims", int(row.get("TOTAL_CLAIMS", 0)))

    if "AGE" in cols and "GENDER" in cols:
        st.caption(f"Age: {row.get('AGE', '-')} | Gender: {row.get('GENDER', '-')}")

    insights = []
    if "TOTAL_VISITS" in cols:
        visits = int(row.get("TOTAL_VISITS", 0) or 0)
        if visits == 0:
            insights.append("No visits are recorded for this patient yet.")
        elif visits <= 2:
            insights.append(f"This patient has a relatively small recorded visit history with {visits} visit(s).")
        else:
            insights.append(f"This patient has an active care history with {visits} recorded visits.")
    if "TOTAL_PRESCRIPTIONS" in cols:
        medications = int(row.get("TOTAL_PRESCRIPTIONS", 0) or 0)
        insights.append(f"{medications} medication record(s) are available for review.")
    if "CRITICAL_LAB_COUNT" in cols:
        critical = int(row.get("CRITICAL_LAB_COUNT", 0) or 0)
        if critical > 0:
            insights.append(f"{critical} lab result(s) were flagged critical and should be reviewed carefully.")
        else:
            insights.append("No critical lab flags are present in the structured lab record.")
    if "EVIDENCE_READINESS_STATUS" in cols:
        readiness = row.get("EVIDENCE_READINESS_STATUS", "")
        if readiness:
            insights.append(f"Document evidence readiness is currently **{readiness.replace('_', ' ').title()}**.")

    if insights:
        st.info(" ".join(insights))


def render_encounters(cfg, persona, pid):
    view = cfg["views"].get("encounter")
    if not view:
        return
    where = f" WHERE patient_id = ?" if pid else ""
    params = [pid] if pid else []
    df = run_query(f"SELECT * FROM {view}{where} ORDER BY visit_date DESC LIMIT 50", params)
    if df is None or df.empty:
        st.caption("No visit records found.")
        return
    audit(persona, "VIEW_ENCOUNTERS", view, pid, row_count=len(df))

    st.markdown("##### Recent Visits")
    cols = df.columns.tolist()
    if "VISIT_DATE" in cols and "VISIT_TYPE" in cols:
        chart_df = df.groupby("VISIT_TYPE").size().reset_index(name="COUNT")
        if not chart_df.empty:
            st.bar_chart(chart_df, x="VISIT_TYPE", y="COUNT")
            top_visit = chart_df.sort_values("COUNT", ascending=False).iloc[0]
            st.caption(
                f"Most recorded visits are **{top_visit['VISIT_TYPE']}** visits ({int(top_visit['COUNT'])} total)."
            )
    safe_df(df[["VISIT_DATE", "VISIT_TYPE", "DIAGNOSIS_DESCRIPTION"] +
               ([c for c in ["FOLLOW_UP_REQUIRED"] if c in cols])
              ] if "VISIT_DATE" in cols else df)


def render_medications(cfg, persona, pid):
    view = cfg["views"].get("medication")
    if not view:
        return
    where = f" WHERE patient_id = ?" if pid else ""
    params = [pid] if pid else []
    df = run_query(f"SELECT * FROM {view}{where} ORDER BY prescription_date DESC LIMIT 50", params)
    if df is None or df.empty:
        st.caption("No medication records found.")
        return
    audit(persona, "VIEW_MEDICATIONS", view, pid, row_count=len(df))

    st.markdown("##### Medications")
    cols = df.columns.tolist()
    display_cols = [c for c in ["MEDICATION_NAME", "DOSAGE", "FREQUENCY", "PRESCRIPTION_DATE", "MEDICATION_STATUS"] if c in cols]
    if display_cols:
        safe_df(df[display_cols])
    else:
        safe_df(df)

    if "MEDICATION_NAME" in cols:
        med_counts = df["MEDICATION_NAME"].value_counts().reset_index()
        med_counts.columns = ["Medication", "Count"]
        if len(med_counts) > 1:
            st.bar_chart(med_counts, x="Medication", y="Count")
        top_med = med_counts.iloc[0]
        st.caption(
            f"The most common medication in the current view is **{top_med['Medication']}** with {int(top_med['Count'])} record(s)."
        )


def render_labs(cfg, persona, pid):
    view = cfg["views"].get("lab")
    if not view:
        return
    where = f" WHERE patient_id = ?" if pid else ""
    params = [pid] if pid else []
    df = run_query(f"SELECT * FROM {view}{where} ORDER BY test_date DESC LIMIT 100", params)
    if df is None or df.empty:
        st.caption("No lab results found.")
        return
    audit(persona, "VIEW_LABS", view, pid, row_count=len(df))

    st.markdown("##### Lab Results")
    cols = df.columns.tolist()
    display_cols = [c for c in ["TEST_TYPE", "TEST_DATE", "STATUS", "CRITICAL_FLAG"] if c in cols]
    if display_cols:
        safe_df(df[display_cols])
    else:
        safe_df(df)

    if "TEST_TYPE" in cols:
        test_counts = df["TEST_TYPE"].value_counts().reset_index()
        test_counts.columns = ["Test Type", "Count"]
        if len(test_counts) > 1:
            st.bar_chart(test_counts, x="Test Type", y="Count")
        top_test = test_counts.iloc[0]
        st.caption(
            f"The most common lab in this view is **{top_test['Test Type']}** with {int(top_test['Count'])} result(s)."
        )

    if "CRITICAL_FLAG" in cols:
        critical = df["CRITICAL_FLAG"].sum() if df["CRITICAL_FLAG"].dtype == bool else 0
        if critical > 0:
            st.warning(f"{critical} critical lab result(s) found — review recommended.")


def render_claims(cfg, persona, pid):
    view = cfg["views"].get("claim")
    if not view:
        return
    where = f" WHERE patient_id = ?" if pid else ""
    params = [pid] if pid else []
    df = run_query(f"SELECT * FROM {view}{where} ORDER BY claim_date DESC LIMIT 50", params)
    if df is None or df.empty:
        st.caption("No claims data found.")
        return
    audit(persona, "VIEW_CLAIMS", view, pid, row_count=len(df))

    st.markdown("##### Claims")
    cols = df.columns.tolist()
    display_cols = [c for c in ["CLAIM_DATE", "PROCEDURE_DESCRIPTION", "CLAIM_STATUS", "DENIAL_REASON"] if c in cols]
    if not display_cols:
        display_cols = [c for c in ["CLAIM_DATE", "PROCEDURE_CODE", "CLAIM_STATUS", "DENIAL_REASON"] if c in cols]
    if display_cols:
        safe_df(df[display_cols])
    else:
        safe_df(df)

    if "CLAIM_STATUS" in cols:
        status_counts = df["CLAIM_STATUS"].value_counts().reset_index()
        status_counts.columns = ["Status", "Count"]
        st.bar_chart(status_counts, x="Status", y="Count")
        if not status_counts.empty:
            top_status = status_counts.iloc[0]
            st.caption(
                f"Most claims in this view are currently **{top_status['Status']}** ({int(top_status['Count'])} claim(s))."
            )


def render_care_gaps(cfg, persona, pid):
    view = cfg["views"].get("care_gap")
    if not view:
        return
    where = f" WHERE patient_id = ?" if pid else ""
    params = [pid] if pid else []
    df = run_query(f"SELECT * FROM {view}{where} ORDER BY gap_priority", params)
    if df is None or df.empty:
        st.caption("No care gaps identified.")
        return
    audit(persona, "VIEW_CARE_GAPS", view, pid, row_count=len(df))

    st.markdown("##### Care Alerts")
    cols = df.columns.tolist()
    display_cols = [c for c in ["GAP_CATEGORY", "GAP_DESCRIPTION", "GAP_PRIORITY"] if c in cols]
    if display_cols:
        safe_df(df[display_cols])

    if "GAP_PRIORITY" in cols:
        priority_counts = df["GAP_PRIORITY"].value_counts().reset_index()
        priority_counts.columns = ["Priority", "Count"]
        st.bar_chart(priority_counts, x="Priority", y="Count")
        if not priority_counts.empty:
            high = priority_counts[priority_counts["Priority"] == "HIGH"]
            if not high.empty:
                st.caption(f"There are {int(high.iloc[0]['Count'])} high-priority care alert(s) in the current view.")


# ---------------------------------------------------------------------------
# Chatbot
# ---------------------------------------------------------------------------
def _analyst_request_in_snowflake(payload):
    """Call Cortex Analyst using the in-Snowflake request bridge."""
    import _snowflake

    resp = _snowflake.send_snow_api_request(
        "POST", "/api/v2/cortex/analyst/message", {}, {},
        payload, None, 60000,
    )
    if resp.get("status") != 200:
        st.error(f"Cortex Analyst error (status {resp.get('status')}).")
        return None
    try:
        return json.loads(resp["content"])
    except (ValueError, KeyError):
        st.error("Could not parse the Cortex Analyst response.")
        return None


def _analyst_request_rest(payload):
    """Call Cortex Analyst over REST when hosted outside Snowflake.

    Requires a programmatic access token (PAT) in st.secrets. A password
    cannot be used here: the Snowflake REST APIs accept PAT, key-pair JWT, or
    OAuth, but not password authentication.
    """
    import requests

    cfg = dict(st.secrets.get("snowflake", {}))
    pat = cfg.get("pat")
    if not pat:
        st.info(
            "Natural-language querying needs a programmatic access token. Add "
            "`pat` to the [snowflake] section of Streamlit secrets to enable "
            "it. Document search below still works without it."
        )
        return None

    account = str(cfg.get("account", "")).strip().lower().replace("_", "-")
    url = f"https://{account}.snowflakecomputing.com/api/v2/cortex/analyst/message"
    try:
        resp = requests.post(
            url,
            headers={
                "Authorization": f"Bearer {pat}",
                "Content-Type": "application/json",
                "Accept": "application/json",
                "X-Snowflake-Authorization-Token-Type": "PROGRAMMATIC_ACCESS_TOKEN",
            },
            json=payload,
            timeout=60,
        )
    except Exception as exc:
        st.error(f"Cortex Analyst request failed: {exc}")
        return None

    if resp.status_code != 200:
        st.error(f"Cortex Analyst error (status {resp.status_code}): {resp.text[:300]}")
        return None
    try:
        return resp.json()
    except ValueError:
        st.error("Could not parse the Cortex Analyst response.")
        return None


def call_cortex_analyst(question, semantic_view):
    payload = {
        "messages": [{"role": "user", "content": [{"type": "text", "text": question}]}],
        "semantic_view": semantic_view,
    }

    if _running_in_snowflake():
        content = _analyst_request_in_snowflake(payload)
    else:
        content = _analyst_request_rest(payload)

    if not content:
        return None

    sql_text, parts = None, []
    for item in content.get("message", {}).get("content", []):
        if item.get("type") == "text":
            parts.append(item.get("text", ""))
        elif item.get("type") == "sql":
            sql_text = item.get("statement")
    return sql_text, "\n\n".join(p for p in parts if p)


def search_documents(question, categories, pid=None):
    request = {
        "query": question,
        "columns": ["chunk_text", "patient_id", "document_category",
                     "original_file_name", "source_event_date"],
        "limit": 6,
    }
    scope = [{"@eq": {"document_category": c}} for c in categories]
    cat_filter = scope[0] if len(scope) == 1 else {"@or": scope}
    if pid:
        request["filter"] = {"@and": [cat_filter, {"@eq": {"patient_id": pid}}]}
    else:
        request["filter"] = cat_filter

    try:
        raw = get_session().sql(
            "SELECT SNOWFLAKE.CORTEX.SEARCH_PREVIEW(?, ?) AS r",
            params=[SEARCH_SERVICE, json.dumps(request)],
        ).collect()[0]["R"]
        return json.loads(raw).get("results", [])
    except SnowparkSQLException:
        return []


def render_chat(cfg, persona, pid):
    st.markdown("### Ask a Question")
    st.caption("Ask questions in natural language. Answers stay within the data this role is allowed to view.")

    history_key = f"chat_history_{persona}_{pid or 'all'}"
    if history_key not in st.session_state:
        st.session_state[history_key] = []

    suggestions = SAMPLE_QUESTIONS.get(persona, [])
    if not st.session_state[history_key] and suggestions:
        st.caption("Suggested questions")
        for q in suggestions[:4]:
            st.markdown(f"- {q}")

    with st.form(key=f"chat_form_{persona}_{pid or 'all'}", clear_on_submit=True):
        question = st.text_area(
            "Question",
            height=100,
            placeholder="Ask about visits, medications, labs, claims, or care alerts...",
        )
        submitted = st.form_submit_button("Ask")

    if submitted and question.strip():
        lowered = question.lower()
        if any(term in lowered for term in REFUSAL_TERMS):
            response = (
                "I can only provide findings from the available health records. "
                "I cannot make clinical assessments, predictions, or treatment recommendations."
            )
            audit(persona, "CHAT_REFUSED", cfg["semantic_view"], pid, question, 0, "REFUSED")
            st.session_state[history_key].append({"question": question, "answer": response, "rows": None})
        else:
            response_parts = []
            rows = None
            result = call_cortex_analyst(question, cfg["semantic_view"])
            if result:
                sql_text, interpretation = result
                if interpretation:
                    response_parts.append(interpretation)
                if sql_text:
                    df = run_query(sql_text)
                    if df is not None and not df.empty:
                        rows = df
                        audit(persona, "CHAT_QUERY", cfg["semantic_view"], pid, question, len(df))
                        response_parts.append(build_result_summary(df, persona, pid))
                    elif not interpretation:
                        response_parts.append("I found a query for that question, but it returned no rows.")

            if cfg["doc_categories"] and cfg["doc_text"]:
                docs = search_documents(question, cfg["doc_categories"], pid)
                if docs:
                    audit(persona, "CHAT_DOC_SEARCH", SEARCH_SERVICE, pid, question, len(docs))
                    # Constitution Principle II: every factual claim must cite its
                    # source record. Each citation names the source document and
                    # its date so the reader can trace the claim back.
                    doc_lines = ["**Citations — source documents behind this answer:**"]
                    for i, d in enumerate(docs[:3], 1):
                        fname = d.get("original_file_name", "Unknown")
                        dt = d.get("source_event_date", "")
                        snippet = d.get("chunk_text", "")[:180].replace("\n", " ")
                        doc_lines.append(f"{i}. Cited source: {fname} ({dt}) — {snippet}...")
                    response_parts.append("\n".join(doc_lines))

            if not response_parts:
                response_parts.append(
                    "I couldn't find a strong answer for that question yet. Try naming a specific patient, medication, lab test, visit, claim, or care alert."
                )
            st.session_state[history_key].append(
                {"question": question, "answer": "\n\n".join(response_parts), "rows": rows}
            )

    if st.button("Clear chat", key=f"clear_chat_{persona}_{pid or 'all'}"):
        st.session_state[history_key] = []

    for item in reversed(st.session_state[history_key]):
        with st.container():
            st.markdown(f"**You**: {item['question']}")
            st.markdown(f"**Care360 Copilot**: {item['answer']}")
            if item["rows"] is not None:
                safe_df(item["rows"])
            st.markdown("---")


def build_result_summary(df, persona, pid):
    row_count = len(df)
    column_names = list(df.columns)
    summaries = [f"I found {row_count} matching record(s)."]

    if "PATIENT_ID" in column_names and not pid:
        unique_patients = df["PATIENT_ID"].nunique()
        summaries.append(f"The results cover {unique_patients} patient(s).")

    if "CLAIM_STATUS" in column_names:
        top_status = df["CLAIM_STATUS"].value_counts().idxmax()
        top_count = int(df["CLAIM_STATUS"].value_counts().max())
        summaries.append(f"The most common claim status is **{top_status}** with {top_count} record(s).")

    if "MEDICATION_NAME" in column_names:
        top_med = df["MEDICATION_NAME"].value_counts().idxmax()
        summaries.append(f"The most frequent medication in the result is **{top_med}**.")

    if "TEST_TYPE" in column_names:
        top_test = df["TEST_TYPE"].value_counts().idxmax()
        summaries.append(f"The most common lab test in the result is **{top_test}**.")

    if "GAP_PRIORITY" in column_names:
        priorities = ", ".join(df["GAP_PRIORITY"].astype(str).unique().tolist())
        summaries.append(f"The result includes care alert priorities: {priorities}.")

    return " ".join(summaries)


# ---------------------------------------------------------------------------
# Main application
# ---------------------------------------------------------------------------
def main():
    st.set_page_config(page_title="Care360 Copilot", page_icon="🏥", layout="wide")

    st.markdown("""
    <style>
    [data-testid="stSidebar"] { min-width: 280px; }
    .stMetric { background: rgba(255,255,255,0.05); border-radius: 8px; padding: 12px; }
    </style>
    """, unsafe_allow_html=True)

    st.sidebar.image("https://upload.wikimedia.org/wikipedia/commons/thumb/2/22/Snowflake_Logo.svg/200px-Snowflake_Logo.svg.png", width=120)
    st.sidebar.title("Care360 Copilot")
    st.sidebar.caption("Synthetic healthcare data — POC only")
    st.sidebar.divider()

    st.sidebar.markdown("**Select your role**")
    persona_codes = list(PERSONAS.keys())
    persona = st.sidebar.radio(
        "Role",
        persona_codes,
        format_func=lambda c: f"{PERSONAS[c]['icon']} {PERSONAS[c]['label']}",
        key="persona_select",
        label_visibility="collapsed",
    )
    cfg = PERSONAS[persona]
    st.sidebar.caption(cfg["desc"])
    st.sidebar.divider()

    pid = None
    patient_view = cfg["views"].get("patient")
    if patient_view:
        try:
            patients_df = get_patient_list(patient_view)
            if patients_df is not None and not patients_df.empty:
                cols_available = patients_df.columns.tolist()
                if "FIRST_NAME" in cols_available and "LAST_NAME" in cols_available:
                    options = ["All patients"] + [
                        f"{r.PATIENT_ID} — {r.FIRST_NAME} {r.LAST_NAME}" for r in patients_df.itertuples()
                    ]
                else:
                    options = ["All patients"] + list(patients_df["PATIENT_ID"])
                pick = st.sidebar.selectbox("Select Patient", options, key=f"pt_{persona}")
                if pick != "All patients":
                    pid = pick.split(" — ")[0] if " — " in pick else pick
        except SnowparkSQLException:
            pass

    st.sidebar.divider()
    ctx = session_context()
    st.sidebar.caption(f"Logged in as: {ctx['user']}")

    # -- Main content --
    header_col1, header_col2 = st.columns([3, 1])
    with header_col1:
        st.title(f"{cfg['icon']} {cfg['label']} Dashboard")
    with header_col2:
        if pid:
            st.info(f"Patient: **{pid}**")

    st.caption("Findings for review only. This is synthetic data — not for clinical use.")

    tab_names = ["📊 Overview"]
    if cfg["views"].get("claim"):
        tab_names.insert(1, "📋 Claims")
    if cfg["doc_categories"] and cfg["doc_text"]:
        tab_names.append("📄 Documents")

    main_col, chat_col = st.columns([2.1, 1], gap="large")

    with main_col:
        tabs = st.tabs(tab_names)

        # -- Overview tab --
        with tabs[0]:
            render_patient_summary(cfg, persona, pid)
            st.divider()

            overview_intro = []
            if pid:
                overview_intro.append(f"You are currently looking at the record for **{pid}**.")
            else:
                overview_intro.append("You are viewing the broader role-based summary across the currently accessible patients.")
            overview_intro.append("Use the visuals to spot patterns quickly, and read the captions below each chart for plain-language takeaways.")
            st.success(" ".join(overview_intro))

            col1, col2 = st.columns(2)
            with col1:
                render_encounters(cfg, persona, pid)
            with col2:
                render_medications(cfg, persona, pid)

            st.divider()
            col3, col4 = st.columns(2)
            with col3:
                render_labs(cfg, persona, pid)
            with col4:
                render_care_gaps(cfg, persona, pid)

        # -- Claims tab (if available) --
        tab_idx = 1
        if cfg["views"].get("claim"):
            with tabs[tab_idx]:
                st.info("This view explains claim status, denials, and claim-related friction in plain terms for the selected role.")
                render_claims(cfg, persona, pid)
            tab_idx += 1

        # -- Documents tab (if available) --
        if cfg["doc_categories"] and cfg["doc_text"]:
            with tabs[tab_idx]:
                st.markdown("### Document Search")
                st.caption("Search across clinical notes, lab reports, and prescriptions.")
                q = st.text_input("Search documents", placeholder="e.g. hemoglobin a1c results", key="doc_search")
                if q:
                    docs = search_documents(q, cfg["doc_categories"], pid)
                    audit(persona, "DOC_SEARCH", SEARCH_SERVICE, pid, q, len(docs))
                    if docs:
                        st.success(f"{len(docs)} document(s) found")
                        st.caption("These documents are the strongest text matches for your search and can provide evidence behind the structured visuals.")
                        for i, d in enumerate(docs, 1):
                            with st.expander(f"{d.get('original_file_name', 'Unknown')} — {d.get('source_event_date', '')}"):
                                st.markdown(f"**Category:** {d.get('document_category', '')}")
                                st.markdown(f"**Patient:** {d.get('patient_id', '')}")
                                st.text(d.get("chunk_text", "")[:800])
                    else:
                        st.info("No matching documents found. Try different search terms.")

    with chat_col:
        st.markdown("## Care360 Assistant")
        st.caption("Ask questions at any time while you review the visuals.")
        render_chat(cfg, persona, pid)


main()
