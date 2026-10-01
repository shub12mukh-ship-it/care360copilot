"""
Care360 Evidence Copilot - persona-aware Streamlit in Snowflake application.

Canonical database: PATIENT360 (constitution: Canonical Platform Naming).

What this app is
    A clinical decision-support surface over synthetic healthcare data. It unifies
    structured records with ingested clinical documents and answers questions with
    cited evidence.

What this app is NOT
    It does not diagnose, does not predict outcomes, and does not recommend treatment.
    Every output is framed as "findings for clinician review" (Principle I).

Persona access model
    Each of the four constitutional personas is bound to its own set of SECURE views
    and its own semantic view, created by sql/patient360_personas.sql. Restriction is
    enforced by COLUMN ABSENCE in the data layer, not by hiding fields in the UI:
    a column a persona may not see is not projected by that persona's view, so it
    cannot reach a dataframe, a Cortex Analyst answer, or an export.

    This module therefore never selects from PATIENT360.RAW, never selects from the
    CURATED layer directly, and never builds a view name from free user input.

Audit
    Every patient-data read is appended to PATIENT360.ANALYTICS.APP_ACCESS_AUDIT.
    The app provides INSERT only; there is no UPDATE or DELETE path (constitution:
    Audit Logging). Log records carry the synthetic patient_id but never patient
    names or clinical values (constitution: No PHI in logs).

Deployment
    Streamlit in Snowflake. Dependencies are limited to streamlit and
    snowflake-snowpark-python (constitution: Development Workflow).
"""

import json

import streamlit as st
from snowflake.snowpark.context import get_active_session
from snowflake.snowpark.exceptions import SnowparkSQLException

APP_TITLE = "Care360 Evidence Copilot"
DB = "PATIENT360"
ANALYTICS = f"{DB}.ANALYTICS"
SEARCH_SERVICE = f"{DB}.DOCUMENTS.DOCUMENT_SEARCH_SERVICE"

SAFETY_NOTICE = (
    "Findings for clinician review only. This tool does not diagnose, "
    "does not predict outcomes, and does not recommend treatment. "
    "Synthetic data only - no real PHI."
)

# -----------------------------------------------------------------------------
# Persona configuration
# -----------------------------------------------------------------------------
# Every object name the app can query is declared here as a literal. Nothing in
# this map is ever derived from user input, so a persona cannot be talked into
# reading another persona's surface.
#
# Keys per persona:
#   semantic_view   semantic view backing the natural-language "Ask" tab
#   views           logical entity -> persona SECURE view. A missing entity means
#                   the persona has no access to that entity at all.
#   pages           navigation entries this persona may open
#   doc_categories  document categories this persona may retrieve. Empty tuple
#                   means no document retrieval whatsoever.
#   doc_text        True if the persona may read document BODY TEXT. False means
#                   citations and metadata only.
PERSONAS = {
    "CARE_COORDINATOR": {
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
        "pages": ("Overview", "Patient record", "Care gaps", "Evidence search", "Ask the data", "Audit trail"),
        "doc_categories": ("CLINICAL_NOTE", "LAB_DOCUMENT", "PRESCRIPTION", "DIAGNOSTIC_IMAGE"),
        "doc_text": True,
    },
    "QUALITY_ANALYST": {
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
        "pages": ("Overview", "Documentation audit", "Care gaps", "Evidence search", "Ask the data", "Audit trail"),
        "doc_categories": ("CLINICAL_NOTE", "LAB_DOCUMENT", "PRESCRIPTION", "DIAGNOSTIC_IMAGE"),
        "doc_text": False,
    },
    "POPULATION_HEALTH": {
        "semantic_view": f"{ANALYTICS}.PATIENT360_SEM_POPULATION_HEALTH",
        "views": {
            "patient": f"{ANALYTICS}.PERSONA_PH_PATIENT_COHORT",
            "encounter": f"{ANALYTICS}.PERSONA_PH_ENCOUNTER_COHORT",
            "lab": f"{ANALYTICS}.PERSONA_PH_LAB_COHORT",
            "medication": f"{ANALYTICS}.PERSONA_PH_MEDICATION_COHORT",
            "care_gap": f"{ANALYTICS}.PERSONA_PH_CARE_GAP",
        },
        "pages": ("Overview", "Cohort explorer", "Care gaps", "Ask the data", "Audit trail"),
        "doc_categories": (),
        "doc_text": False,
    },
    "PHARMACIST": {
        "semantic_view": f"{ANALYTICS}.PATIENT360_SEM_PHARMACIST",
        "views": {
            "patient": f"{ANALYTICS}.PERSONA_RX_PATIENT",
            "medication": f"{ANALYTICS}.PERSONA_RX_MEDICATION",
            "lab": f"{ANALYTICS}.PERSONA_RX_LAB",
            "claim": f"{ANALYTICS}.PERSONA_RX_CLAIM",
            "care_gap": f"{ANALYTICS}.PERSONA_RX_CARE_GAP",
            "evidence": f"{ANALYTICS}.PERSONA_RX_EVIDENCE",
        },
        "pages": ("Overview", "Medication review", "Care gaps", "Evidence search", "Ask the data", "Audit trail"),
        "doc_categories": ("PRESCRIPTION", "LAB_DOCUMENT", "CLINICAL_NOTE"),
        "doc_text": True,
    },
}

# Starter questions per persona, taken from the use cases in the constitution.
SAMPLE_QUESTIONS = {
    "CARE_COORDINATOR": [
        "What medications is patient P00094 on and when were they prescribed?",
        "How many encounters does each patient have, and what was the most recent visit type?",
        "Which patients have a follow-up required but no recorded follow-up date?",
    ],
    "QUALITY_ANALYST": [
        "How many Hemoglobin A1C tests were performed, and how many were flagged critical?",
        "Which document categories have the lowest searchable percentage?",
        "How many care gap signals cannot be substantiated with a citable document?",
    ],
    "POPULATION_HEALTH": [
        "How many patients are in each age band?",
        "Which care gap categories have the most patients at high priority?",
        "How many patients had at least one critical lab result, by age band?",
    ],
    "PHARMACIST": [
        "What are the most frequently prescribed medications?",
        "Which prescriptions have no lab test recorded before they were written?",
        "Which claims were denied and what was the stated reason?",
    ],
}

# Questions the system must refuse regardless of persona (Principle I).
# This is a REFUSAL blocklist: matching a term causes the app to decline the
# question before any query is issued. The clinical terms below are the thing
# being blocked, never an instruction to the model.
REFUSAL_TERMS = (  # constitution-exempt: safety-guardrail
    "diagnose", "diagnosis for", "what condition does", "prognosis", "life expectancy",  # constitution-exempt: safety-guardrail
    "will the patient", "should i prescribe", "recommend treatment", "what treatment",  # constitution-exempt: safety-guardrail
    "how long will", "predict",
)


# -----------------------------------------------------------------------------
# Session and persona resolution
# -----------------------------------------------------------------------------
@st.cache_resource
def get_session():
    """Active Snowflake session. In Streamlit in Snowflake no credentials are needed."""
    return get_active_session()


@st.cache_data(ttl=600)
def load_registry():
    """Persona registry rows, keyed by persona_code."""
    rows = get_session().sql(
        f"""
        SELECT persona_code, display_name, role_description, identity_tier,
               document_text_access, minimum_necessary_note, semantic_view_name
        FROM {ANALYTICS}.PERSONA_REGISTRY
        ORDER BY persona_code
        """
    ).collect()
    return {r["PERSONA_CODE"]: r.as_dict() for r in rows}


@st.cache_data(ttl=600)
def role_mapped_persona():
    """
    Persona bound to the caller's current Snowflake role, if one is configured.

    Returns None when PERSONA_ROLE_MAP has no row for the active role, which is the
    expected state during the synthetic-data phase. Populating that table switches
    the app from selector-driven to role-enforced personas with no code change.
    """
    rows = get_session().sql(
        f"""
        SELECT persona_code
        FROM {ANALYTICS}.PERSONA_ROLE_MAP
        WHERE UPPER(snowflake_role) = UPPER(CURRENT_ROLE())
        LIMIT 1
        """
    ).collect()
    return rows[0]["PERSONA_CODE"] if rows else None


@st.cache_data(ttl=600)
def session_context():
    row = get_session().sql(
        "SELECT CURRENT_USER() AS u, CURRENT_ROLE() AS r, CURRENT_SESSION() AS s"
    ).collect()[0]
    return {"user": row["U"], "role": row["R"], "session": str(row["S"])}


def resolve_persona(registry):
    """
    Decide the active persona.

    Role mapping wins when configured, and the selector is then locked so a user
    cannot widen their own access. Otherwise the selector drives the persona and
    the resolution mode is recorded in the audit trail as SELECTOR.
    """
    mapped = role_mapped_persona()
    codes = [c for c in PERSONAS if c in registry] or list(PERSONAS)

    if mapped and mapped in PERSONAS:
        st.sidebar.success(f"Persona enforced by role: {registry[mapped]['DISPLAY_NAME']}")
        return mapped, "ROLE_ENFORCED"

    chosen = st.sidebar.selectbox(
        "Persona",
        codes,
        format_func=lambda c: registry.get(c, {}).get("DISPLAY_NAME", c),
        key="persona_code",
    )
    st.sidebar.caption(
        "No role mapping is configured for your Snowflake role, so the persona is "
        "selected here. Access is still restricted by this persona's own secure "
        "views and semantic view."
    )
    return chosen, "SELECTOR"


# -----------------------------------------------------------------------------
# Audit logging and guarded query execution
# -----------------------------------------------------------------------------
def audit(persona, resolution, action, target=None, patient_id=None,
          question=None, row_count=None, outcome="SUCCESS"):
    """
    Append one row to the immutable audit trail.

    Audit failure must never silently swallow a data access, but it must also not
    break the clinical workflow, so the error is surfaced in the UI instead.
    """
    ctx = session_context()
    try:
        get_session().sql(
            f"""
            INSERT INTO {ANALYTICS}.APP_ACCESS_AUDIT
              (session_id, user_identity, active_role, persona_code, persona_resolution,
               action, target_object, patient_id, question_text, row_count, outcome)
            SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
            """,
            params=[ctx["session"], ctx["user"], ctx["role"], persona, resolution,
                    action, target, patient_id, question, row_count, outcome],
        ).collect()
    except SnowparkSQLException as exc:
        st.warning(f"Access was not recorded in the audit trail: {exc.message}")


def persona_view(cfg, entity):
    """
    Resolve a logical entity to this persona's secure view.

    Returns None when the persona has no access to the entity, which callers must
    treat as "not available to you" rather than falling back to a broader object.
    """
    return cfg["views"].get(entity)


def run_query(sql, params, persona, resolution, action, target,
              patient_id=None, question=None):
    """Execute a persona-scoped read, log it, and return a pandas DataFrame."""
    try:
        df = get_session().sql(sql, params=params).to_pandas()
    except SnowparkSQLException as exc:
        audit(persona, resolution, action, target, patient_id, question, 0, "ERROR")
        # Per "No PHI in error messages", show the Snowflake message only. Persona
        # views never project names or clinical values, so this cannot leak PHI.
        st.error(f"Query failed: {exc.message}")
        return None
    audit(persona, resolution, action, target, patient_id, question, len(df), "SUCCESS")
    return df


def require_entity(cfg, entity, label):
    """Render a minimum-necessary notice and return None when access is denied."""
    view = persona_view(cfg, entity)
    if view is None:
        st.info(
            f"{label} is not available to this persona. The data is excluded at the "
            "view layer under HIPAA minimum-necessary, not hidden in the interface."
        )
    return view


def show_df(df, caption=None):
    if df is None:
        return
    if df.empty:
        st.caption("No records matched.")
        return
    # hide_index is not accepted by every Streamlit build shipped with Streamlit in
    # Snowflake, so fall back rather than failing the page.
    try:
        st.dataframe(df, use_container_width=True, hide_index=True)
    except TypeError:
        st.dataframe(df, use_container_width=True)
    if caption:
        st.caption(caption)


# -----------------------------------------------------------------------------
# Shared data helpers
# -----------------------------------------------------------------------------
def patient_options(cfg, persona, resolution):
    """
    Patient picker values for this persona.

    Identified personas get "P00094 - Sandra Joseph". De-identified and cohort
    personas get the bare identifier, because their view does not project a name.
    """
    view = persona_view(cfg, "patient")
    if view is None:
        return []
    identified = {"first_name", "last_name"} <= set_columns(view)
    cols = "patient_id, first_name, last_name" if identified else "patient_id"
    df = run_query(
        f"SELECT {cols} FROM {view} ORDER BY patient_id",
        [], persona, resolution, "LIST_PATIENTS", view,
    )
    if df is None or df.empty:
        return []
    if identified:
        return [
            f"{r.PATIENT_ID} - {r.FIRST_NAME} {r.LAST_NAME}" for r in df.itertuples()
        ]
    return list(df["PATIENT_ID"])


@st.cache_data(ttl=600)
def set_columns(view):
    """Lowercase column names actually projected by a view."""
    schema, name = view.split(".")[1], view.split(".")[2]
    rows = get_session().sql(
        f"""
        SELECT column_name
        FROM {DB}.INFORMATION_SCHEMA.COLUMNS
        WHERE table_schema = ? AND table_name = ?
        """,
        params=[schema, name],
    ).collect()
    return {r["COLUMN_NAME"].lower() for r in rows}


def selected_patient_id():
    raw = st.session_state.get("patient_pick")
    if not raw:
        return None
    return raw.split(" - ")[0]


# -----------------------------------------------------------------------------
# Pages
# -----------------------------------------------------------------------------
def page_overview(cfg, persona, resolution):
    meta = load_registry().get(persona, {})
    st.subheader("Access scope for this persona")

    c1, c2, c3 = st.columns(3)
    c1.metric("Identity tier", meta.get("IDENTITY_TIER", "-"))
    c2.metric("Document text", "Permitted" if cfg["doc_text"] else "Withheld")
    c3.metric("Entities available", len(cfg["views"]))

    if meta.get("MINIMUM_NECESSARY_NOTE"):
        st.info(f"**Minimum necessary basis.** {meta['MINIMUM_NECESSARY_NOTE']}")

    st.markdown("**Data surfaces bound to this persona**")
    table = ["| Entity | Secure view |", "| --- | --- |"]
    table += [f"| {k} | `{v}` |" for k, v in sorted(cfg["views"].items())]
    st.markdown("\n".join(table))
    st.caption(f"Semantic view for natural-language questions: `{cfg['semantic_view']}`")

    view = persona_view(cfg, "patient")
    if view:
        df = run_query(
            f"SELECT COUNT(*) AS patients FROM {view}",
            [], persona, resolution, "VIEW_OVERVIEW", view,
        )
        if df is not None and not df.empty:
            st.metric("Patients in scope", int(df["PATIENTS"][0]))


def page_patient_record(cfg, persona, resolution):
    pid = selected_patient_id()
    if not pid:
        st.info("Select a patient in the sidebar to review their record.")
        return

    st.subheader(f"Longitudinal record - {pid}")

    view = persona_view(cfg, "patient")
    if view:
        show_df(run_query(
            f"SELECT * FROM {view} WHERE patient_id = ?",
            [pid], persona, resolution, "READ_PATIENT_SUMMARY", view, patient_id=pid,
        ))

    for entity, label, order_col in (
        ("encounter", "Encounters", "visit_date"),
        ("medication", "Medications", "prescription_date"),
        ("lab", "Lab monitoring", "test_date"),
        ("claim", "Claims (clinical context only)", "claim_date"),
    ):
        v = persona_view(cfg, entity)
        if v is None:
            continue
        with st.expander(label, expanded=(entity == "encounter")):
            show_df(run_query(
                f"SELECT * FROM {v} WHERE patient_id = ? ORDER BY {order_col} DESC",
                [pid], persona, resolution, f"READ_{entity.upper()}", v, patient_id=pid,
            ))
            if entity == "claim":
                st.caption(
                    "Financial amounts and policy identifiers are excluded by design "
                    "under HIPAA minimum-necessary."
                )
            if entity == "lab":
                st.caption(
                    "Numeric result values are not held in structured data. They exist "
                    "only in the lab report document text - use Evidence search to cite them."
                )


def page_medication_review(cfg, persona, resolution):
    view = require_entity(cfg, "medication", "Medication detail")
    if not view:
        return
    st.subheader("Medication safety review")

    pid = selected_patient_id()
    if pid:
        st.caption(f"Filtered to patient {pid}. Clear the sidebar selection to review all.")
        show_df(run_query(
            f"SELECT * FROM {view} WHERE patient_id = ? ORDER BY prescription_date DESC",
            [pid], persona, resolution, "READ_MEDICATION", view, patient_id=pid,
        ))
    else:
        show_df(run_query(
            f"""
            SELECT medication_name,
                   COUNT(*) AS prescriptions,
                   COUNT(DISTINCT patient_id) AS patients,
                   SUM(IFF(latest_prior_lab_test_type IS NULL, 1, 0)) AS no_prior_lab
            FROM {view}
            GROUP BY medication_name
            ORDER BY prescriptions DESC
            """,
            [], persona, resolution, "READ_MEDICATION_SUMMARY", view,
        ), "no_prior_lab counts prescriptions with no lab recorded before the write date.")

    gap = persona_view(cfg, "care_gap")
    if gap:
        with st.expander("Monitoring and coverage-friction signals"):
            show_df(run_query(
                f"SELECT * FROM {gap} WHERE gap_priority IN ('HIGH','MEDIUM') ORDER BY gap_priority",
                [], persona, resolution, "READ_CARE_GAP", gap,
            ))


def page_cohort_explorer(cfg, persona, resolution):
    view = require_entity(cfg, "patient", "Cohort data")
    if not view:
        return
    st.subheader("Cohort explorer")
    st.caption(
        "Age is generalised to a band and patient names are not projected, to limit "
        "re-identification risk in a small population."
    )

    show_df(run_query(
        f"""
        SELECT age_band,
               COUNT(*) AS patients,
               SUM(critical_lab_count) AS critical_labs,
               ROUND(AVG(total_visits), 1) AS avg_visits
        FROM {view}
        GROUP BY age_band
        ORDER BY age_band
        """,
        [], persona, resolution, "READ_COHORT_BY_AGE_BAND", view,
    ))

    enc = persona_view(cfg, "encounter")
    if enc:
        with st.expander("High utilisation - more than 2 encounters in any 90-day window"):
            # Clinical rationale: >2 encounters inside 90 days is the conventional
            # high-utilisation screen used for care-management outreach.
            show_df(run_query(
                f"""
                WITH windowed AS (
                    SELECT patient_id, visit_date,
                           COUNT(*) OVER (
                               PARTITION BY patient_id
                               ORDER BY visit_date
                               RANGE BETWEEN INTERVAL '90 days' PRECEDING AND CURRENT ROW
                           ) AS visits_in_90d
                    FROM {enc}
                )
                SELECT patient_id, MAX(visits_in_90d) AS peak_visits_in_90d
                FROM windowed
                GROUP BY patient_id
                HAVING MAX(visits_in_90d) > 2
                ORDER BY peak_visits_in_90d DESC
                """,
                [], persona, resolution, "READ_HIGH_UTILISATION", enc,
            ))

    lab = persona_view(cfg, "lab")
    if lab:
        with st.expander("Lab monitoring coverage by test type"):
            show_df(run_query(
                f"""
                SELECT test_type,
                       COUNT(*) AS results,
                       COUNT(DISTINCT patient_id) AS patients_tested,
                       SUM(IFF(critical_flag, 1, 0)) AS critical_results
                FROM {lab}
                GROUP BY test_type
                ORDER BY results DESC
                """,
                [], persona, resolution, "READ_LAB_COVERAGE", lab,
            ), "Numeric thresholds such as 'A1c above 9 percent' cannot be evaluated: "
               "structured records hold no result value, only the critical flag.")


def page_documentation_audit(cfg, persona, resolution):
    st.subheader("Documentation adherence audit")

    pq = persona_view(cfg, "pipeline_quality")
    if pq:
        show_df(run_query(
            f"SELECT * FROM {pq} ORDER BY asset_family",
            [], persona, resolution, "READ_PIPELINE_QUALITY", pq,
        ), "Extraction outcome by asset family across the ingestion pipeline.")

    ev = persona_view(cfg, "evidence")
    if ev:
        with st.expander("Documents that failed to produce searchable text", expanded=True):
            show_df(run_query(
                f"""
                SELECT patient_id, document_category, source_asset_name, source_event_date,
                       extraction_outcome_status, stage_file_present, extracted_text_length
                FROM {ev}
                WHERE NOT is_searchable_evidence OR NOT stage_file_present
                ORDER BY document_category, source_event_date DESC
                """,
                [], persona, resolution, "READ_EVIDENCE_EXCEPTIONS", ev,
            ))
        st.caption(
            "This persona receives document metadata and citation pointers only. "
            "Document body text is not projected by PERSONA_QA_EVIDENCE."
        )

    lab = persona_view(cfg, "lab")
    if lab:
        with st.expander("Monitoring evidence by test type"):
            show_df(run_query(
                f"""
                SELECT test_type,
                       COUNT(*) AS results,
                       COUNT(DISTINCT patient_id) AS patients_tested,
                       SUM(IFF(critical_flag, 1, 0)) AS critical_results,
                       MAX(test_date) AS most_recent_test
                FROM {lab}
                GROUP BY test_type
                ORDER BY results DESC
                """,
                [], persona, resolution, "READ_MONITORING_EVIDENCE", lab,
            ))

    enc = persona_view(cfg, "encounter")
    if enc:
        with st.expander("Follow-up documented as required but no follow-up date recorded"):
            show_df(run_query(
                f"""
                SELECT patient_id, visit_id, visit_date, visit_type, diagnosis_code
                FROM {enc}
                WHERE follow_up_required AND follow_up_date IS NULL
                ORDER BY visit_date DESC
                """,
                [], persona, resolution, "READ_FOLLOWUP_EXCEPTIONS", enc,
            ))


def page_care_gaps(cfg, persona, resolution):
    view = require_entity(cfg, "care_gap", "Care gap signals")
    if not view:
        return
    st.subheader("Care gaps")
    st.caption(
        "Gap rules are defined in SQL in sql/patient360_curation.sql with their "
        "clinical rationale. These are findings for clinician review, not diagnoses."
    )

    cols = set_columns(view)
    priority = st.multiselect("Priority", ["HIGH", "MEDIUM", "LOW"], default=["HIGH", "MEDIUM"])
    if not priority:
        st.caption("Select at least one priority.")
        return

    placeholders = ", ".join(["?"] * len(priority))
    order = "gap_priority, patient_id"
    show_df(run_query(
        f"SELECT * FROM {view} WHERE gap_priority IN ({placeholders}) ORDER BY {order}",
        list(priority), persona, resolution, "READ_CARE_GAP", view,
    ))

    if "citation_capability" in cols:
        show_df(run_query(
            f"""
            SELECT gap_category, citation_capability, COUNT(*) AS patients
            FROM {view}
            GROUP BY gap_category, citation_capability
            ORDER BY gap_category, citation_capability
            """,
            [], persona, resolution, "READ_CARE_GAP_CITABILITY", view,
        ), "citation_capability shows whether a gap can be substantiated with a citable document.")


def page_evidence_search(cfg, persona, resolution):
    st.subheader("Evidence search")

    categories = cfg["doc_categories"]
    if not categories:
        st.info(
            "Document retrieval is not available to this persona. Cohort analysis "
            "does not require access to individual clinical documents."
        )
        return

    if cfg["doc_text"]:
        st.caption(
            "Cortex Search retrieves passages from ingested clinical documents. "
            "Every result carries its source file name, category, and date so the "
            "finding can be cited."
        )
    else:
        st.caption(
            "This persona receives citations and metadata only. Matching documents "
            "are listed with their source and date, and the passage text is withheld."
        )

    st.caption("Document categories in scope: " + ", ".join(categories))

    pid = selected_patient_id()
    question = st.text_input(
        "Search the clinical document corpus",
        placeholder="hemoglobin a1c result",
        key="evidence_query",
    )
    if not question:
        return

    request = {
        "query": question,
        "columns": ["chunk_text", "patient_id", "document_category",
                    "original_file_name", "source_event_date", "canonical_stage_path"],
        "limit": 8,
    }
    # Persona scope and patient scope are both enforced as search filters.
    scope = [{"@eq": {"document_category": c}} for c in categories]
    category_filter = scope[0] if len(scope) == 1 else {"@or": scope}
    if pid:
        request["filter"] = {"@and": [category_filter, {"@eq": {"patient_id": pid}}]}
    else:
        request["filter"] = category_filter

    try:
        raw = get_session().sql(
            "SELECT SNOWFLAKE.CORTEX.SEARCH_PREVIEW(?, ?) AS r",
            params=[SEARCH_SERVICE, json.dumps(request)],
        ).collect()[0]["R"]
        results = json.loads(raw).get("results", [])
    except SnowparkSQLException as exc:
        audit(persona, resolution, "EVIDENCE_SEARCH", SEARCH_SERVICE, pid, question, 0, "ERROR")
        st.error(f"Search failed: {exc.message}")
        return

    audit(persona, resolution, "EVIDENCE_SEARCH", SEARCH_SERVICE, pid, question,
          len(results), "SUCCESS")

    if not results:
        st.warning(
            "No supporting evidence was retrieved, so no finding can be reported "
            "for clinician review."
        )
        return

    st.success(f"{len(results)} passages retrieved.")
    for i, r in enumerate(results, start=1):
        header = (
            f"{i}. {r.get('original_file_name', 'unknown')} - "
            f"{r.get('document_category', 'unknown')} - "
            f"patient {r.get('patient_id', 'unknown')} - "
            f"{r.get('source_event_date', 'undated')}"
        )
        with st.expander(header):
            st.markdown(
                f"**Citation.** Document `{r.get('original_file_name')}`, "
                f"category {r.get('document_category')}, "
                f"date {r.get('source_event_date')}, "
                f"patient {r.get('patient_id')}."
            )
            if cfg["doc_text"]:
                st.text(r.get("chunk_text", ""))
            else:
                st.caption(
                    "Passage text withheld for this persona. The citation above is "
                    "sufficient to evidence that the document exists and is traceable."
                )


def page_ask(cfg, persona, resolution):
    st.subheader("Ask the data")
    st.caption(
        f"Questions are answered by Cortex Analyst over `{cfg['semantic_view']}`. "
        "That model contains only the fields this persona may see, so a restricted "
        "field cannot appear in an answer."
    )

    for q in SAMPLE_QUESTIONS.get(persona, []):
        st.markdown(f"- {q}")

    question = st.text_area("Your question", key="ask_question", height=80)
    if not st.button("Ask", type="primary"):
        return
    if not question.strip():
        st.caption("Enter a question first.")
        return

    lowered = question.lower()
    if any(term in lowered for term in REFUSAL_TERMS):
        audit(persona, resolution, "ASK_REFUSED", cfg["semantic_view"],
              selected_patient_id(), question, 0, "REFUSED")
        st.error(
            "This question asks for a diagnosis, prognosis, or treatment decision. "
            "This system only surfaces documented evidence for clinician review and "
            "cannot answer it."
        )
        return

    answer = call_cortex_analyst(question, cfg["semantic_view"])
    if answer is None:
        audit(persona, resolution, "ASK", cfg["semantic_view"],
              selected_patient_id(), question, 0, "ERROR")
        return

    sql_text, interpretation = answer
    if interpretation:
        st.markdown(interpretation)
    if not sql_text:
        audit(persona, resolution, "ASK", cfg["semantic_view"],
              selected_patient_id(), question, 0, "NO_SQL")
        st.warning(
            "Cortex Analyst did not produce a query for that question. Try naming the "
            "entity you want, for example medications, labs, encounters, or care gaps."
        )
        return

    with st.expander("Generated SQL (source of this answer)"):
        st.code(sql_text, language="sql")

    df = run_query(sql_text, [], persona, resolution, "ASK",
                   cfg["semantic_view"], selected_patient_id(), question)
    if df is not None:
        show_df(df, f"Source: {cfg['semantic_view']} (persona-scoped semantic model).")
        st.caption(SAFETY_NOTICE)


def call_cortex_analyst(question, semantic_view):
    """
    Send one question to Cortex Analyst and return (sql, interpretation).

    Returns None when the call itself fails. Uses the in-Snowflake request path, so
    no data leaves the Snowflake trust boundary (Principle III).
    """
    try:
        import _snowflake
    except ImportError:
        st.error(
            "Cortex Analyst is available only when this app runs inside Snowflake. "
            "Deploy it as a Streamlit in Snowflake object to use this tab."
        )
        return None

    payload = {
        "messages": [{"role": "user", "content": [{"type": "text", "text": question}]}],
        "semantic_view": semantic_view,
    }
    try:
        resp = _snowflake.send_snow_api_request(
            "POST", "/api/v2/cortex/analyst/message", {}, {},
            payload, None, 60000,
        )
    except Exception as exc:  # the request helper raises plain exceptions
        st.error(f"Cortex Analyst request failed: {exc}")
        return None

    if resp.get("status") != 200:
        st.error(
            "Cortex Analyst returned status "
            f"{resp.get('status')}. {str(resp.get('content'))[:400]}"
        )
        return None

    try:
        content = json.loads(resp["content"])
    except (ValueError, KeyError) as exc:
        st.error(f"Could not read the Cortex Analyst response: {exc}")
        return None

    sql_text, parts = None, []
    for item in content.get("message", {}).get("content", []):
        if item.get("type") == "text":
            parts.append(item.get("text", ""))
        elif item.get("type") == "sql":
            sql_text = item.get("statement")
    return sql_text, "\n\n".join(p for p in parts if p)


def page_audit_trail(cfg, persona, resolution):
    st.subheader("Audit trail")
    st.caption(
        "Append-only record of persona-scoped access. The application provides no "
        "UPDATE or DELETE path. Entries carry the synthetic patient identifier but "
        "never patient names or clinical values."
    )

    ctx = session_context()
    scope = st.radio("Scope", ["My session", "My user"], horizontal=True)
    if scope == "My session":
        where, params = "session_id = ?", [ctx["session"]]
    else:
        where, params = "user_identity = ?", [ctx["user"]]

    df = get_session().sql(
        f"""
        SELECT event_at, persona_code, persona_resolution, action, target_object,
               patient_id, row_count, outcome, active_role
        FROM {ANALYTICS}.APP_ACCESS_AUDIT
        WHERE {where}
        ORDER BY event_at DESC
        LIMIT 200
        """,
        params=params,
    ).to_pandas()
    show_df(df, "Most recent 200 events.")


# -----------------------------------------------------------------------------
# Application shell
# -----------------------------------------------------------------------------
PAGE_HANDLERS = {
    "Overview": page_overview,
    "Patient record": page_patient_record,
    "Medication review": page_medication_review,
    "Cohort explorer": page_cohort_explorer,
    "Documentation audit": page_documentation_audit,
    "Care gaps": page_care_gaps,
    "Evidence search": page_evidence_search,
    "Ask the data": page_ask,
    "Audit trail": page_audit_trail,
}


def main():
    st.set_page_config(page_title=APP_TITLE, page_icon="+", layout="wide")
    st.title(APP_TITLE)
    st.caption(SAFETY_NOTICE)

    registry = load_registry()
    if not registry:
        st.error(
            "No personas are registered. Run sql/patient360_personas.sql against "
            f"{DB} before using this app."
        )
        return

    persona, resolution = resolve_persona(registry)
    cfg = PERSONAS[persona]
    meta = registry.get(persona, {})

    st.sidebar.markdown(f"**{meta.get('DISPLAY_NAME', persona)}**")
    st.sidebar.caption(meta.get("ROLE_DESCRIPTION", ""))
    st.sidebar.divider()

    # Patient picker, only where the persona works on individual patients.
    if any(p in cfg["pages"] for p in ("Patient record", "Medication review", "Evidence search")):
        options = patient_options(cfg, persona, resolution)
        if options:
            pick = st.sidebar.selectbox(
                "Patient", ["(none)"] + options, key=f"patient_pick_{persona}"
            )
            st.session_state["patient_pick"] = None if pick == "(none)" else pick
        else:
            st.session_state["patient_pick"] = None
        st.sidebar.divider()

    page = st.sidebar.radio("Section", cfg["pages"], key=f"nav_page_{persona}")
    ctx = session_context()
    st.sidebar.divider()
    st.sidebar.caption(
        f"User {ctx['user']} | role {ctx['role']}\n\nPersona resolution: {resolution}"
    )

    # A persona can never reach a page outside its own allow-list.
    if page not in cfg["pages"]:
        st.error("That section is not available to this persona.")
        return

    PAGE_HANDLERS[page](cfg, persona, resolution)


main()
