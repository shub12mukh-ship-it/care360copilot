# Implementation Plan: Patient360 Curation Logic

**Feature Directory**: `specs/004-patient360-curation`

**Created**: 2026-09-27

**Status**: Draft

## Executive Summary

This plan defines the next implementation phase for the project: building a curated business layer over the existing `PATIENT360` raw dataset so the application can answer persona-specific healthcare questions through stable patient-centered entities, traceable evidence relationships, and semantic-view-ready summaries. The plan intentionally keeps the project within the constitution: synthetic data only, no diagnosis or treatment recommendation, and one canonical database identity (`PATIENT360`).

The curation layer is the bridge between raw healthcare records and the future Streamlit + semantic-view experience. It will organize patients, encounters, medications, labs, claims, notes, and imaging-related evidence into reusable curated entities that support the documented hackathon personas and future document/report analysis.

## Technical Context

### Current System Context

- The project constitution now declares `PATIENT360` as the only canonical database identity.
- Raw synthetic healthcare data and document-linked assets already exist and must be treated as the source material for curation.
- The business problem, personas, and evidence-copilot workflow are documented in `docs/architecture.md`.
- The future application path is a Streamlit app backed by a semantic view, so curated outputs must be business-facing and stable.
- Imaging and report-related assets exist in raw form and need to be represented in a way that supports later analysis even if image-content interpretation is not part of this phase.

### Design Objective

Create a curation design that transforms raw `PATIENT360` data into a patient-centered curated layer that:
- supports the four target personas,
- preserves source traceability,
- provides stable entities and relationships for a future semantic view,
- keeps report and imaging assets analyzable in later phases,
- avoids introducing a second product shape or reviving legacy `CARE360_DB` assumptions.

### Constraints

- Synthetic data only.
- No diagnosis generation, treatment recommendation, or unsupported prediction.
- SQL-first business logic.
- The curated layer must remain within one canonical product and database model.
- Any legacy `CARE360_DB` references are migration debt and must not be copied forward.

## Constitution Check

### Product Scope Canon

Pass with one follow-up requirement. The feature directly serves the stated business problem: fragmented healthcare records must be unified into a patient-centered evidence copilot. The work is still bounded to synthetic data and cited evidence.

### Canonical Platform Naming

Pass with active migration note. The constitution requires `PATIENT360` as the canonical database identity. However, `docs/architecture.md` still contains legacy `CARE360_DB` references. This is not a blocker to planning, but implementation must not copy those names into new artifacts.

### Patient Safety & Evidence Rules

Pass. The planned curation layer supports evidence review and traceability rather than diagnosis or treatment recommendation.

### Layered Data Pipeline

Pass. This feature is specifically about the CURATED layer, which is required by the constitution and is a necessary precursor to ANALYTICS and semantic modeling.

### Development Workflow

Pass. The plan keeps business logic in SQL/data-layer artifacts and does not shift behavior into ad hoc Python transformations.

### Gate Decision

Proceed. No constitutional blocker prevents planning. The only mandatory follow-up is to treat all legacy `CARE360_DB` references in architecture materials as migration debt and avoid reproducing them.

## Phase 0: Research

Create `research.md` to resolve the following planning decisions.

### Research Topic 1: Curated business entities for persona workflows

**Decision to make**: Which curated entities and summaries best support the four target personas while staying close to the raw healthcare model?

**Questions to resolve**:
- What patient-centered summaries are needed for care coordination?
- What evidence and monitoring summaries are needed for compliance and care-gap use cases?
- What medication/lab relationship views are needed for pharmacist review?

**Expected output**:
- A list of curated entities and why each exists.
- A mapping from persona questions to curated outputs.

### Research Topic 2: Imaging and report treatment in the curated layer

**Decision to make**: How should report and imaging-related raw assets be represented in curation when the current phase is not yet doing image-content interpretation?

**Questions to resolve**:
- Which metadata is required now for future analysis?
- Which relationships must be preserved between encounter, patient, report, and imaging asset?
- Which imaging/report values belong in curated summaries vs evidence-asset detail?

**Expected output**:
- A curation rule for image/report evidence assets.
- Alternatives considered for deferring vs partially modeling these assets.

### Research Topic 3: Semantic-view readiness rules

**Decision to make**: What makes the curated layer stable and semantic-ready for the future Streamlit app?

**Questions to resolve**:
- Which entities are stable enough to become semantic view candidates?
- Which aggregations belong in CURATED vs ANALYTICS?
- Which relationship paths should be explicit for downstream text-to-SQL or semantic modeling?

**Expected output**:
- Guidelines for semantic-view-ready entities and relationships.
- Boundaries between CURATED and ANALYTICS.

### Research Topic 4: Traceability and contradiction handling

**Decision to make**: How should the curated layer preserve provenance and expose conflicts across structured and document-linked sources?

**Questions to resolve**:
- Which source identifiers must be carried forward?
- Which curation outputs need explicit source timestamps or last-updated logic?
- How should conflicting records be represented for review rather than silently flattened?

**Expected output**:
- Traceability fields and contradiction-handling rules for curated outputs.

### Research Topic 5: Legacy migration boundaries

**Decision to make**: Which legacy names and assumptions from current docs or SQL need to be treated as migration debt before implementation?

**Questions to resolve**:
- Where does `CARE360_DB` still appear in existing reference material?
- Which parts of the architecture doc should be treated as conceptually valid but naming-stale?
- What implementation guardrails prevent new `CARE360_DB` references?

**Expected output**:
- A migration note list for implementation planning.

**Phase 0 Artifact**: `specs/004-patient360-curation/research.md`

## Phase 1: Design & Contracts

### 1. Data Model Design

Create `data-model.md` that defines the curated business model.

#### Core curated entities to design

- **Curated Patient Record**
  - A patient-centered, longitudinal entity that unifies demographics, risk signals, recent activity, and evidence links.
  - Must preserve traceability to raw sources.

- **Encounter Summary**
  - A curated representation of a visit/encounter and its linked diagnoses, medications, labs, claims, notes, and imaging/report assets.
  - Must support timeline and care-review workflows.

- **Medication Evidence Summary**
  - A curated view that relates active and historical medications to encounter context, lab context, and supporting documentation.
  - Must support medication review and answer persona questions about current meds and recent changes.

- **Lab Monitoring Summary**
  - A curated representation of important lab trends and monitoring evidence, with patient-level and encounter-level rollups.
  - Must support HbA1c and follow-up evidence questions.

- **Care Gap Signal**
  - A business-facing indicator for missing evidence, overdue monitoring, or utilization patterns.
  - Must be explainable and traceable.

- **Evidence Asset**
  - A curated representation of notes, reports, and imaging-linked records as analyzable evidence attached to patient and encounter context.
  - Must support current citation use and future image/report analysis.

- **Patient Timeline Event**
  - A normalized chronological event entity representing visits, tests, medication changes, claims milestones, and document/report creation.
  - Must support longitudinal review in the future Streamlit app.

#### Data-model contents

For each entity, define:
- business purpose,
- required attributes,
- upstream raw relationships,
- validation rules,
- provenance requirements,
- whether it is CURATED-only or a candidate input to ANALYTICS/semantic view.

**Phase 1 Artifact**: `specs/004-patient360-curation/data-model.md`

### 2. Interface Contracts

Create a `contracts/` directory because this feature has downstream interfaces even if they are internal to the project.

#### Contract 1: Curated entity contract

Document the expected shape and meaning of the curated outputs consumed by downstream layers:
- patient-centered record contract,
- encounter summary contract,
- care-gap signal contract,
- evidence asset contract,
- timeline event contract.

#### Contract 2: Semantic-view readiness contract

Document what downstream semantic-layer consumers can rely on:
- stable entity names,
- traceable business measures,
- relationship paths,
- source attribution expectations,
- constraints around synthetic-only evidence.

#### Contract 3: Streamlit/read-model contract

Document what the future Streamlit UI expects from the curated layer:
- patient selector support,
- recent visits summary,
- medication/lab evidence summaries,
- care-gap rollups,
- evidence-linked report/image metadata.

**Phase 1 Artifacts**:
- `specs/004-patient360-curation/contracts/curated-entities.md`
- `specs/004-patient360-curation/contracts/semantic-view.md`
- `specs/004-patient360-curation/contracts/streamlit-read-model.md`

### 3. Quickstart Validation Guide

Create `quickstart.md` describing how to validate the curated layer end-to-end.

The quickstart should include:
- prerequisites for validating the raw `PATIENT360` source data,
- the expected curated outputs to inspect,
- validation scenarios for each target persona,
- validation of patient timeline ordering,
- validation of source traceability,
- validation that report/image assets remain linked and analyzable,
- validation that no legacy `CARE360_DB` naming is used in newly created artifacts.

Example validation scenarios:
- review one patient’s unified curated record,
- verify medication + lab evidence path for pharmacist workflow,
- verify HbA1c monitoring evidence path for compliance workflow,
- verify care-gap signal availability for population-health workflow,
- verify report/image evidence asset linkage for future analysis readiness.

**Phase 1 Artifact**: `specs/004-patient360-curation/quickstart.md`

## Artifact Summary

Planning for this feature should produce:
- `specs/004-patient360-curation/research.md`
- `specs/004-patient360-curation/data-model.md`
- `specs/004-patient360-curation/contracts/curated-entities.md`
- `specs/004-patient360-curation/contracts/semantic-view.md`
- `specs/004-patient360-curation/contracts/streamlit-read-model.md`
- `specs/004-patient360-curation/quickstart.md`

## Implementation Guidance For The Next Phase

When this plan moves into execution, the implementation should follow these boundaries:
- build CURATED-layer outputs before adding or revising ANALYTICS outputs,
- preserve provenance and business meaning rather than over-aggregating early,
- treat report and imaging assets as evidence-linked records in this phase,
- avoid immediate image-content interpretation unless a later spec expands scope,
- eliminate new `CARE360_DB` references from all newly produced design and code artifacts.

## Completion Notes

- No extension hooks are configured for `before_plan` or `after_plan`.
- The current architecture document still contains legacy `CARE360_DB` naming; that is noted as migration debt and must not be copied into new implementation artifacts.
- This plan is ready for review and, once approved, the next step is implementation task generation for the curated-layer work.
