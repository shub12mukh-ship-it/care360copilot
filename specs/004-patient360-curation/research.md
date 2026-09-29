# Research: Patient360 Curation Logic

**Feature**: `specs/004-patient360-curation`
**Created**: 2026-09-27

## Decision 1: PATIENT360 is the only valid active database target

**Decision**: All forward-looking curation work will target `PATIENT360` and treat
`CARE360_DB` as legacy migration debt only.

**Rationale**:
- The constitution now explicitly declares `PATIENT360` as the canonical database identity.
- Allowing both `PATIENT360` and `CARE360_DB` to coexist as active targets would create
  drift in SQL, semantic-view design, Streamlit integration, and review rules.
- The user explicitly directed that `CARE360_DB` is old and that future work must use
  `PATIENT360`.

**Alternatives considered**:
- Continue supporting both names in parallel: rejected because it violates the constitution.
- Rename the active feature back to `CARE360_DB`: rejected because the constitution now
  prohibits it.

## Decision 2: The curated layer must be patient-centered and persona-driven

**Decision**: The curation model will be built around a patient-centered longitudinal view,
not raw table mirroring.

**Rationale**:
- The business problem is fragmented healthcare records and time-to-insight.
- The target personas ask patient-review, evidence-monitoring, care-gap, and medication
  safety questions, none of which are well served by raw tables alone.
- A patient-centered curated layer is the correct base for semantic views and Streamlit.

**Alternatives considered**:
- Preserve the raw model and rely on downstream joins: rejected because it pushes business
  logic into the app and semantic layer.
- Build only encounter-level summaries: rejected because personas need both patient-level
  and encounter-level views.

## Decision 3: Imaging and report assets are evidence assets in this phase

**Decision**: Raw MRI, angiogram, X-ray, abdomen, CT, and other report-linked assets will be
represented in curation as patient-linked evidence assets with metadata, provenance, and
encounter context. Full image-content interpretation is deferred.

**Rationale**:
- The user explicitly said the raw layer already contains images and that they will eventually
  be needed for analysis.
- The current phase is curation logic, not computer vision or image-model inference.
- Linking image/report assets now avoids redesign later and keeps the semantic model future-ready.

**Alternatives considered**:
- Ignore imaging until a later feature: rejected because it would weaken the curated model.
- Attempt immediate image-content analysis in this phase: rejected because it expands scope
  beyond the approved feature.

## Decision 4: CURATED and ANALYTICS need a strict boundary

**Decision**: CURATED will hold business-facing, traceable canonical entities and summaries;
ANALYTICS will hold higher-level derived metrics, dashboards, and broader cohort-oriented outputs.

**Rationale**:
- The constitution requires a layered pipeline and discourages collapsing all logic into a
  single layer.
- Semantic-view readiness requires stable entity definitions before higher-level aggregations.
- This keeps the future Streamlit and semantic-layer work grounded in canonical business meaning.

**Alternatives considered**:
- Put all derived logic directly into ANALYTICS: rejected because it bypasses the curation layer.
- Materialize everything in CURATED: rejected because some metrics are better treated as
  downstream analytical outputs.

## Decision 5: Provenance and contradiction visibility are mandatory curation attributes

**Decision**: Each curated entity must preserve source identifiers, source timestamps, and any
meaningful record-status context needed to trace facts back to raw tables or document/report assets.

**Rationale**:
- The product requires cited evidence and explicitly forbids unsupported conclusions.
- Contradictions between structured and unstructured evidence are a core safety concern.
- Future Streamlit and semantic-view consumers must not lose evidence traceability during curation.

**Alternatives considered**:
- Simplify curated entities by dropping provenance: rejected because it undermines evidence traceability.
- Handle contradictions only in the app layer: rejected because the curation layer should expose the
  conditions needed for contradiction review.

## Decision 6: The curation layer should explicitly support the target personas

**Decision**: The curated outputs will be designed around the four documented personas:
Clinical Care Coordinator, Quality & Compliance Analyst, Population Health Manager,
and Clinical Pharmacist.

**Rationale**:
- The constitution says those personas are mandatory and define acceptable product scope.
- The curation layer must answer their core questions without forcing ad hoc raw joins.

**Alternatives considered**:
- Design generic data marts without persona mapping: rejected because it weakens business alignment.
- Optimize for one persona only: rejected because the constitution preserves all four personas.

## Decision 7: Legacy architecture references are migration debt, not blockers

**Decision**: Existing `CARE360_DB` references in `docs/architecture.md` are treated as migration
debt for future cleanup, but they do not block this curation design as long as no new artifacts
copy them forward.

**Rationale**:
- The user asked to move forward on the curation process now.
- The constitution already establishes that new work must use `PATIENT360`.
- The practical risk is propagation of stale names, not the existence of legacy history.

**Alternatives considered**:
- Stop planning until all legacy docs are renamed: rejected because it would block the approved feature.
- Ignore legacy naming entirely: rejected because governance requires it to be tracked and eliminated.