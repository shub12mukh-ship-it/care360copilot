import html
import json
import os
import re
import uuid

import pandas as pd
import streamlit as st

st.set_page_config(page_title="Patient360 Evidence Copilot", page_icon="🩺", layout="wide")

conn = st.connection("snowflake", ttl=os.getenv("SNOWFLAKE_CONNECTION_TTL"))
session = conn.session()

AGENT_FQN = "PATIENT360.ANALYTICS.PATIENT360_EVIDENCE_COPILOT"
GENERAL_OPTION = "General / population question"
HISTORY_TURNS = 10

# Starter questions per persona, scoped to what each persona may see (see PERSONA_REGISTRY).
# "patient" = a patient is selected; "general" = population-level questions.
SAMPLE_QUESTIONS = {
    "CARE_COORDINATOR": {
        "patient": [
            "Summarize this patient's recent visits and open care gaps.",
            "What medications is this patient on, with dosage and when prescribed?",
            "Show the lab report for this patient's most recent critical lab result.",
            "Which of this patient's follow-ups are overdue?",
        ],
        "general": [
            "Which patients have high-priority care gaps?",
            "How many patients have critical lab results?",
            "Which patients have overdue follow-up visits?",
            "Which patients have no searchable evidence documents?",
        ],
    },
    "PHARMACIST": {
        "patient": [
            "List this patient's active medications with dosage, frequency, and refills.",
            "What lab test was performed before each medication was prescribed, and when?",
            "Which of this patient's medications have limited supply remaining?",
            "Do any current medications lack a recent supporting lab result?",
        ],
        "general": [
            "What are the most prescribed medications?",
            "Which patients on Metformin have no lab test before the prescription?",
            "Which patients have critical lab results and active prescriptions?",
            "How many prescriptions have limited supply remaining?",
        ],
    },
    "QUALITY_ANALYST": {
        "patient": [
            "Which claims were denied for this patient, and what was the stated reason?",
            "How long did each of this patient's claim decisions take?",
            "Do this patient's claims have supporting documentation on file?",
            "Which of this patient's claims had coverage friction?",
        ],
        "general": [
            "What are the most common claim denial reasons?",
            "What is the average number of days to a claim decision?",
            "How many claims were flagged for coverage friction?",
            "Which document categories have the most ingestion failures?",
        ],
    },
    "PATIENT_SELF": {
        "patient": [
            "What medications am I taking, and how often?",
            "Do any of my visits need a follow-up, and by what date?",
            "What were my most recent lab results?",
            "Do I have any care alerts I should know about?",
        ],
        "general": [],
    },
}
DEFAULT_QUESTIONS = SAMPLE_QUESTIONS["CARE_COORDINATOR"]

PRIORITY_COLORS = {"HIGH": "red", "MEDIUM": "orange", "LOW": "green"}
COVERAGE_LABELS = {
    "FULL_EVIDENCE_COVERAGE": "Full",
    "PARTIAL_EVIDENCE_COVERAGE": "Partial",
    "NO_SEARCHABLE_EVIDENCE": "None",
}
CITATION_LABELS = {
    "CITABLE": "Supported by source documents",
    "CITABLE_WITH_GAPS": "Some supporting documents missing",
    "NOT_CITABLE": "No supporting documents to cite",
}
CITATION_TOOLTIPS = {
    "CITABLE": "All source documents behind this flag are searchable, so the copilot can cite them in its answers.",
    "CITABLE_WITH_GAPS": "Some of this patient's source documents are missing or could not be read. "
    "Answers may cite only part of the record, so verify against the chart.",
    "NOT_CITABLE": "No searchable source documents support this flag. The copilot can only use structured "
    "records and cannot quote any document.",
}
SENSITIVE_COLUMN_RE = re.compile(r"(FIRST|LAST|FULL|PATIENT|PROVIDER|DOCTOR)_?NAME|DOB|BIRTH|ADDRESS|PHONE|EMAIL", re.I)
DOB_RE = re.compile(r"\b(DOB|Date of Birth)\s*[:\-]\s*[0-9]{1,4}[/\-][0-9]{1,2}[/\-][0-9]{1,4}", re.I)
PROVIDER_RE = re.compile(r"\b(Dr\.|Provider:)\s*[A-Z][a-z]+(\s+[A-Z][a-z]+)?")


# ---------------------------------------------------------------------------
# Data loaders
# ---------------------------------------------------------------------------
@st.cache_data(ttl=600, show_spinner=False)
def load_personas() -> pd.DataFrame:
    return session.sql(
        "SELECT PERSONA_CODE, DISPLAY_NAME, ROLE_DESCRIPTION, IDENTITY_TIER, DOCUMENT_TEXT_ACCESS "
        "FROM PATIENT360.ANALYTICS.PERSONA_REGISTRY ORDER BY DISPLAY_NAME"
    ).to_pandas()


@st.cache_data(ttl=600, show_spinner=False)
def load_role_persona() -> str | None:
    """Persona bound to the active Snowflake role (PERSONA_ROLE_MAP), if any."""
    rows = session.sql(
        "SELECT PERSONA_CODE FROM PATIENT360.ANALYTICS.PERSONA_ROLE_MAP "
        "WHERE SNOWFLAKE_ROLE = CURRENT_ROLE() ORDER BY ASSIGNED_ON DESC LIMIT 1"
    ).collect()
    return rows[0][0] if rows else None


@st.cache_data(ttl=600, show_spinner=False)
def load_patients() -> pd.DataFrame:
    return session.sql(
        "SELECT PATIENT_ID, FIRST_NAME, LAST_NAME, AGE, GENDER, TOTAL_VISITS, TOTAL_LABS, "
        "TOTAL_PRESCRIPTIONS, TOTAL_CLAIMS, CRITICAL_LAB_COUNT, EVIDENCE_READINESS_STATUS "
        "FROM PATIENT360.ANALYTICS.ANALYTICS_PATIENT_EVIDENCE_READINESS ORDER BY PATIENT_ID"
    ).to_pandas()


@st.cache_data(ttl=300, show_spinner=False)
def load_care_gaps(patient_id: str) -> pd.DataFrame:
    return session.sql(
        "SELECT GAP_CATEGORY, GAP_PRIORITY, GAP_DESCRIPTION, CITATION_CAPABILITY "
        "FROM PATIENT360.ANALYTICS.ANALYTICS_CARE_GAP_WITH_EVIDENCE WHERE PATIENT_ID = ?",
        params=[patient_id],
    ).to_pandas()


def clear_data_cache():
    for loader in (load_personas, load_role_persona, load_patients, load_care_gaps):
        loader.clear()


def log_audit(persona_code, resolution, action, patient_id, question, row_count, outcome):
    """Best-effort audit trail; never blocks the user if the insert fails."""
    try:
        session.sql(
            "INSERT INTO PATIENT360.ANALYTICS.APP_ACCESS_AUDIT "
            "(SESSION_ID, USER_IDENTITY, ACTIVE_ROLE, PERSONA_CODE, PERSONA_RESOLUTION, ACTION, "
            "TARGET_OBJECT, PATIENT_ID, QUESTION_TEXT, ROW_COUNT, OUTCOME) "
            "SELECT ?, COALESCE(CURRENT_USER(), 'unknown'), CURRENT_ROLE(), ?, ?, ?, ?, ?, ?, ?, ?",
            params=[
                st.session_state.session_id, persona_code, resolution, action, AGENT_FQN,
                patient_id, question[:2000], row_count, outcome,
            ],
        ).collect()
    except Exception:
        pass


# ---------------------------------------------------------------------------
# De-identification helpers
# ---------------------------------------------------------------------------
def _name_pattern(patients: pd.DataFrame):
    names = {
        f"{r.FIRST_NAME} {r.LAST_NAME}".strip()
        for r in patients.itertuples()
        if r.FIRST_NAME and r.LAST_NAME
    }
    if not names:
        return None
    alternation = "|".join(re.escape(n) for n in sorted(names, key=len, reverse=True))
    return re.compile(rf"\b({alternation})\b", re.I)


def redact_text(text: str, name_re) -> str:
    if not text:
        return text
    if name_re is not None:
        text = name_re.sub("[patient]", text)
    text = DOB_RE.sub(r"\1: [redacted]", text)
    return PROVIDER_RE.sub(r"\1 [redacted]", text)


def redact_table(df: pd.DataFrame, name_re) -> pd.DataFrame:
    df = df.drop(columns=[c for c in df.columns if SENSITIVE_COLUMN_RE.search(str(c))])
    for col in df.select_dtypes(include="object").columns:
        df[col] = df[col].map(lambda v: redact_text(v, name_re) if isinstance(v, str) else v)
    return df


def deid_age(age) -> str:
    """Exact age for de-identified views; ages 90+ are aggregated per HIPAA Safe Harbor."""
    if pd.isna(age):
        return "age unknown"
    years = int(age)
    return "90+ yrs" if years >= 90 else f"{years} yrs"


def full_age(age) -> str:
    return "age unknown" if pd.isna(age) else f"{int(age)} yrs"


def pretty(code) -> str:
    return str(code or "").replace("_", " ").strip().capitalize()


# ---------------------------------------------------------------------------
# Agent response handling
# ---------------------------------------------------------------------------
def _extract_table(block: dict):
    """Agent 'table' blocks carry an inline result set -- no extra query needed."""
    tbl = block.get("table", {}) or {}
    result_set = tbl.get("result_set", {}) or {}
    rows = result_set.get("data", []) or []
    row_type = (result_set.get("resultSetMetaData", {}) or {}).get("rowType", []) or []
    cols = [c.get("name") for c in row_type]
    if not rows or not cols:
        return None
    df = pd.DataFrame(rows, columns=cols)
    # Only convert genuinely numeric columns so codes like NDC/ICD keep leading zeros.
    for meta in row_type:
        if str(meta.get("type", "")).lower() in ("fixed", "real"):
            df[meta["name"]] = pd.to_numeric(df[meta["name"]], errors="coerce")
    return {"title": tbl.get("title") or "", "df": df}


def _clean_snippet(text: str) -> str:
    text = re.sub(r"^#+\s*", "", str(text or ""), flags=re.M)
    text = re.sub(r"\s+", " ", text).strip()
    return text[:300] + ("…" if len(text) > 300 else "")


def parse_agent_response(resp: dict):
    """Return the final answer (no intermediate 'thinking out loud'), tables, citations, suggestions."""
    blocks = [b for b in (resp.get("content") or []) if isinstance(b, dict)]
    last_tool_idx = max(
        (i for i, b in enumerate(blocks) if b.get("type") in ("tool_use", "tool_result")), default=-1
    )
    text_idx = [i for i, b in enumerate(blocks) if b.get("type") == "text" and b.get("text")]
    final_idx = [i for i in text_idx if i > last_tool_idx] or text_idx[-1:]

    text_parts, citations, tables, suggestions, seen = [], [], [], [], set()
    for i, block in enumerate(blocks):
        btype = block.get("type")
        if btype == "text":
            if i in final_idx:
                text_parts.append(block.get("text", ""))
            for ann in block.get("annotations", []) or []:
                if ann.get("type") != "cortex_search_citation":
                    continue
                key = ann.get("doc_title") or ann.get("doc_id")
                if key in seen:
                    continue
                seen.add(key)
                citations.append(
                    {"file": ann.get("doc_title") or ann.get("doc_id") or "document", "snippet": _clean_snippet(ann.get("text"))}
                )
        elif btype == "table":
            extracted = _extract_table(block)
            if extracted is not None:
                tables.append(extracted)
        elif btype == "suggested_queries":
            suggestions = [q.get("query") for q in block.get("suggested_queries", []) or [] if q.get("query")]

    answer = "\n\n".join(t for t in text_parts if t).strip()
    if not answer:
        answer = "I couldn't find a clear answer in the available evidence for that question."
    return answer, tables, citations[:8], suggestions[:3]


def build_context(persona_row, patient_row) -> str:
    deidentified = persona_row.IDENTITY_TIER == "DEIDENTIFIED"
    ctx = (
        f"Session context -- viewing persona: {persona_row.DISPLAY_NAME} "
        f"({persona_row.PERSONA_CODE}, identity tier {persona_row.IDENTITY_TIER})."
    )
    if patient_row is not None:
        if deidentified:
            ctx += f" Selected patient: {patient_row.PATIENT_ID} (age {deid_age(patient_row.AGE)}, {patient_row.GENDER})."
        else:
            ctx += (
                f" Selected patient: {patient_row.PATIENT_ID} ({patient_row.FIRST_NAME} {patient_row.LAST_NAME}, "
                f"age {full_age(patient_row.AGE)})."
            )
        ctx += " Answer specifically about this patient unless the question is clearly general."
    else:
        ctx += " No specific patient is selected -- treat this as a general or population-level question."
    if deidentified:
        ctx += (
            " The viewer is authorized for DE-IDENTIFIED data only: refer to patients by PATIENT_ID only and do not "
            "include names, dates of birth, addresses, phone numbers, or provider names."
        )
    if not bool(persona_row.DOCUMENT_TEXT_ACCESS):
        ctx += " The viewer may not see clinical document text: summarize findings, do not quote document text."
    return ctx


def run_agent(question: str, context: str, history: list) -> dict:
    # Keep only completed user->assistant pairs; failed turns are dropped entirely.
    pairs = [
        (u, a)
        for u, a in zip(history[::2], history[1::2])
        if u["role"] == "user" and a["role"] == "assistant" and not a.get("error")
    ]
    messages = [
        {"role": m["role"], "content": [{"type": "text", "text": m["content"]}]}
        for pair in pairs
        for m in pair
    ][-HISTORY_TURNS:]
    # Agent conversations must start with a user turn.
    while messages and messages[0]["role"] != "user":
        messages.pop(0)
    messages.append({"role": "user", "content": [{"type": "text", "text": f"{context}\n\nQuestion: {question}"}]})

    row = session.sql(
        "SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(?, ?)",
        params=[AGENT_FQN, json.dumps({"messages": messages, "stream": False})],
    ).collect()
    return json.loads(row[0][0])


def queue_prompt(q: str):
    st.session_state.pending_prompt = q


def render_assistant_payload(msg: dict, msg_key: str, show_snippets: bool):
    st.markdown(msg["content"])
    for t in msg.get("tables") or []:
        if t["title"]:
            st.caption(t["title"])
        st.dataframe(t["df"], width="stretch", hide_index=True)
    citations = msg.get("citations") or []
    if citations:
        with st.expander(f"📄 {len(citations)} source document(s)"):
            for c in citations:
                if show_snippets and c["snippet"]:
                    st.markdown(f"**{c['file']}**")
                    st.caption(c["snippet"])
                else:
                    st.markdown(f"- **{c['file']}**")
    if msg.get("warnings"):
        st.caption("⚠️ " + "; ".join(msg["warnings"]))
    if msg.get("error_detail"):
        with st.expander("Technical details"):
            st.code(msg["error_detail"], language=None)
    suggestions = msg.get("suggestions") or []
    if suggestions:
        st.caption("Follow up:")
        cols = st.columns(len(suggestions))
        for i, (col, q) in enumerate(zip(cols, suggestions)):
            col.button(q, width="stretch", key=f"{msg_key}_sugg_{i}", on_click=queue_prompt, args=(q,))


def new_conversation():
    st.session_state.messages = []
    st.session_state.pop("pending_prompt", None)


# ---------------------------------------------------------------------------
# Session state
# ---------------------------------------------------------------------------
st.session_state.setdefault("messages", [])
st.session_state.setdefault("session_id", str(uuid.uuid4()))

# ---------------------------------------------------------------------------
# Load reference data
# ---------------------------------------------------------------------------
try:
    with st.spinner("Loading patient context..."):
        personas_df = load_personas()
        patients_df = load_patients()
        try:
            role_persona = load_role_persona()
        except Exception:
            role_persona = None
except Exception as exc:
    st.error("Couldn't load reference data from Snowflake. Check the app's role and warehouse, then retry.")
    with st.expander("Technical details"):
        st.code(str(exc), language=None)
    st.button("Retry", on_click=clear_data_cache)
    st.stop()

if personas_df.empty:
    st.error("No personas are configured in PATIENT360.ANALYTICS.PERSONA_REGISTRY.")
    st.stop()

# ---------------------------------------------------------------------------
# Sidebar: persona + patient context
# ---------------------------------------------------------------------------
with st.sidebar:
    st.markdown("### 🩺 Patient360 Copilot")
    st.caption("Evidence-cited answers for clinician review only. Synthetic data.")

    persona_labels = personas_df["DISPLAY_NAME"].tolist()
    role_locked = role_persona in set(personas_df["PERSONA_CODE"])
    if role_locked:
        locked_label = personas_df.loc[personas_df["PERSONA_CODE"] == role_persona, "DISPLAY_NAME"].iloc[0]
        persona_label = st.selectbox("Viewing as", [locked_label], disabled=True)
        persona_resolution = "ROLE_MAP"
        st.caption("🔒 Persona is set by your Snowflake role.")
    else:
        persona_label = st.selectbox("Viewing as", persona_labels, key="persona_select")
        persona_resolution = "SELECTOR"
        st.caption("⚠️ Demo mode: your role isn't mapped to a persona, so you can switch freely.")

    persona_row = personas_df[personas_df["DISPLAY_NAME"] == persona_label].iloc[0]
    deidentified = persona_row.IDENTITY_TIER == "DEIDENTIFIED"
    show_snippets = bool(persona_row.DOCUMENT_TEXT_ACCESS)
    st.caption(persona_row.ROLE_DESCRIPTION)
    if deidentified:
        st.info("De-identified view: names, dates of birth and provider names are hidden.", icon="🛡️")

    def patient_label(r) -> str:
        if deidentified:
            return f"{r.PATIENT_ID} · {deid_age(r.AGE)} · {r.GENDER}"
        return f"{r.PATIENT_ID} — {r.FIRST_NAME} {r.LAST_NAME}"

    labels_by_id = {r.PATIENT_ID: patient_label(r) for r in patients_df.itertuples()}
    is_patient_self = persona_row.PERSONA_CODE == "PATIENT_SELF"
    options = list(labels_by_id) if is_patient_self else [GENERAL_OPTION] + list(labels_by_id)
    # Remember the chosen patient ourselves so it survives persona switches on every Streamlit version
    # (options/labels change per persona, which makes Streamlit treat this as a new widget).
    preferred = st.session_state.get("preferred_patient")
    choice = st.selectbox(
        "Patient",
        options,
        index=options.index(preferred) if preferred in options else 0,
        format_func=lambda v: labels_by_id.get(v, v),
        help="Type to search by patient ID.",
    )
    if preferred in options or choice != options[0]:  # don't overwrite with an automatic fallback
        st.session_state.preferred_patient = choice
    if is_patient_self:
        st.caption("Patient self-service is limited to a single patient record.")
    selected_patient_id = None if choice == GENERAL_OPTION else choice
    patient_row = (
        patients_df[patients_df["PATIENT_ID"] == selected_patient_id].iloc[0] if selected_patient_id else None
    )

    st.divider()
    st.button("🧹 New conversation", width="stretch", on_click=new_conversation)
    st.button("🔄 Refresh data", width="stretch", on_click=clear_data_cache, help="Reload personas and patients.")

# Start a fresh conversation whenever persona or patient changes, so context never leaks across them.
current_ctx = (persona_row.PERSONA_CODE, selected_patient_id)
if st.session_state.get("chat_context") != current_ctx:
    if st.session_state.get("chat_context") is not None and st.session_state.messages:
        st.toast("Context changed — started a new conversation.", icon="🔄")
    new_conversation()
    st.session_state.chat_context = current_ctx

name_re = _name_pattern(patients_df) if deidentified else None

# ---------------------------------------------------------------------------
# Main: title + contextual patient snapshot
# ---------------------------------------------------------------------------
st.title("Patient360 Evidence Copilot")
st.caption(f"Viewing as **{persona_row.DISPLAY_NAME}** · Findings for clinician review only.")

if patient_row is not None:
    with st.container(border=True):
        # Wider first column so the patient's name never truncates; metrics share the rest.
        c1, c2, c3, c4, c5, c6 = st.columns([2.6, 1, 1, 1.1, 1.2, 1.4], vertical_alignment="center")
        with c1:
            st.caption("Patient")
            if deidentified:
                st.markdown(f"#### {patient_row.PATIENT_ID}")
                st.caption(f"{deid_age(patient_row.AGE)} · {patient_row.GENDER}")
            else:
                st.markdown(f"#### {patient_row.FIRST_NAME} {patient_row.LAST_NAME}")
                st.caption(f"{patient_row.PATIENT_ID} · {full_age(patient_row.AGE)} · {patient_row.GENDER}")
        c2.metric("Visits", int(patient_row.TOTAL_VISITS or 0))
        c3.metric("Labs", int(patient_row.TOTAL_LABS or 0))
        critical = int(patient_row.CRITICAL_LAB_COUNT or 0)
        c4.metric("Critical labs", f"🔴 {critical}" if critical else "0")
        c5.metric("Medications", int(patient_row.TOTAL_PRESCRIPTIONS or 0))
        c6.metric(
            "Evidence coverage",
            COVERAGE_LABELS.get(patient_row.EVIDENCE_READINESS_STATUS, pretty(patient_row.EVIDENCE_READINESS_STATUS)),
            help="How much of this patient's record has searchable source documents the copilot can cite. "
            "Full = all documents searchable; Partial = some missing or failed; None = nothing to cite.",
        )

        try:
            gaps_df = load_care_gaps(selected_patient_id)
        except Exception:
            gaps_df = pd.DataFrame()
            st.caption("Care-gap signals are unavailable right now.")
        if not gaps_df.empty:
            st.markdown(
                "**Open care-gap signals**",
                help="Automated flags for items in this patient's record that may need clinician review. "
                "The color shows priority; the evidence note shows whether the copilot can back it with documents.",
            )
            for g in gaps_df.itertuples():
                color = PRIORITY_COLORS.get(str(g.GAP_PRIORITY).upper(), "gray")
                evidence = CITATION_LABELS.get(g.CITATION_CAPABILITY, "")
                tooltip = CITATION_TOOLTIPS.get(g.CITATION_CAPABILITY, "")
                evidence_html = (
                    f' &nbsp;<span title="{html.escape(tooltip, quote=True)}" style="color:gray;font-style:italic;'
                    f'cursor:help;border-bottom:1px dotted gray">{html.escape(evidence)} ⓘ</span>'
                    if evidence
                    else ""
                )
                st.markdown(
                    f":{color}-badge[{pretty(g.GAP_CATEGORY)} · {pretty(g.GAP_PRIORITY)} priority] "
                    f"{html.escape(str(g.GAP_DESCRIPTION or ''))}{evidence_html}",
                    unsafe_allow_html=True,
                )

# ---------------------------------------------------------------------------
# Chat
# ---------------------------------------------------------------------------
def render_sample_questions(container):
    persona_questions = SAMPLE_QUESTIONS.get(persona_row.PERSONA_CODE, DEFAULT_QUESTIONS)
    scope = "patient" if patient_row is not None else "general"
    samples = persona_questions.get(scope) or DEFAULT_QUESTIONS[scope]
    container.markdown(
        f"**Try asking** · _suggested for {persona_row.DISPLAY_NAME}"
        + (f", about {selected_patient_id}_" if patient_row is not None else ", across all patients_")
    )
    cols = container.columns(2)
    for i, q in enumerate(samples):
        cols[i % 2].button(
            q, width="stretch", key=f"sample_{persona_row.PERSONA_CODE}_{scope}_{i}",
            on_click=queue_prompt, args=(q,), icon="💬",
        )


if not st.session_state.messages:
    render_sample_questions(st)
else:
    render_sample_questions(st.expander("💡 Suggested questions", expanded=False))

for i, msg in enumerate(st.session_state.messages):
    with st.chat_message(msg["role"]):
        if msg["role"] == "user":
            st.markdown(msg["content"])
        else:
            render_assistant_payload(msg, f"m{i}", show_snippets)

prompt = st.chat_input("Ask about a patient, claim, medication, lab, or care gap...")
prompt = st.session_state.pop("pending_prompt", None) or prompt

if prompt and prompt.strip():
    prompt = prompt.strip()
    history = list(st.session_state.messages)
    st.session_state.messages.append({"role": "user", "content": prompt})
    with st.chat_message("user"):
        st.markdown(prompt)

    assistant_msg = {"role": "assistant"}
    with st.chat_message("assistant"):
        with st.spinner("Reviewing records and evidence... this can take up to a minute."):
            try:
                resp = run_agent(prompt, build_context(persona_row, patient_row), history)
                answer, tables, citations, suggestions = parse_agent_response(resp)
                if deidentified:
                    answer = redact_text(answer, name_re)
                    tables = [{"title": redact_text(t["title"], name_re), "df": redact_table(t["df"], name_re)} for t in tables]
                    citations = [{"file": c["file"], "snippet": redact_text(c["snippet"], name_re)} for c in citations]
                    suggestions = [redact_text(s, name_re) for s in suggestions]
                warnings = [w.get("message", "") for w in (resp.get("warnings") or []) if isinstance(w, dict)]
                assistant_msg.update(
                    content=answer, tables=tables, citations=citations, suggestions=suggestions,
                    warnings=[w for w in warnings if w],
                )
                outcome, row_count = "SUCCESS", sum(len(t["df"]) for t in tables)
            except Exception as exc:
                assistant_msg.update(
                    content="Sorry — I couldn't get an answer from the copilot just now. Please try again in a moment.",
                    error=True,
                    error_detail=str(exc)[:1000],
                )
                outcome, row_count = f"ERROR: {type(exc).__name__}", 0
    log_audit(persona_row.PERSONA_CODE, persona_resolution, "ASK_AGENT", selected_patient_id, prompt, row_count, outcome)

    st.session_state.messages.append(assistant_msg)
    # Re-render from history so follow-up buttons get stable keys and work on the first click.
    st.rerun()
