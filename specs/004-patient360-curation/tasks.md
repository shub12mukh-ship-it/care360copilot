# Tasks: Patient360 Curation Logic

**Feature**: `specs/004-patient360-curation`
**Input**: `specs/004-patient360-curation/spec.md`
**Prerequisites**: `plan.md`, `research.md`, `data-model.md`, `contracts/`, `quickstart.md`

## Phase 1: Setup

- [X] T001 Review legacy `CARE360_DB` references in `docs/architecture.md`, `docs/testing.md`, `README.md`, and future SQL artifacts; document exact replacement targets for `PATIENT360` and mark any remaining legacy references as migration-only
- [X] T002 Create `sql/patient360_curation.sql` and record the `PATIENT360` CURATED and ANALYTICS object naming strategy, including the boundary that CURATED will hold canonical business entities while ANALYTICS will hold broader cohort metrics
- [X] T003 Create a working validation checklist in `docs/testing.md` or `specs/004-patient360-curation/quickstart.md` that maps the four personas to concrete curation validation scenarios

## Phase 2: Foundational

- [X] T004 Define the canonical source-to-curated mapping for patient, encounter, medication, lab, claim, note, and imaging/report raw entities in `sql/patient360_curation.sql`
- [X] T005 Define provenance fields and traceability rules in `sql/patient360_curation.sql` so every curated fact preserves source identifiers, source timestamps, and source asset linkage
- [X] T006 Define the normalized patient timeline event model in `sql/patient360_curation.sql`, including chronological ordering across visits, labs, medications, claims, notes, and report/image-linked events
- [X] T007 Define imaging/report evidence-asset handling rules in `sql/patient360_curation.sql` so MRI, angiogram, X-ray, abdomen, CT, and other report-linked assets remain connected to patient and encounter context without requiring immediate image-content interpretation
- [X] T008 Add validation queries to `docs/testing.md` or `sql/patient360_curation.sql` comments that prove no new `CARE360_DB` references were introduced in forward-looking curation artifacts

## Phase 3: User Story 1 - Unified curated patient record for clinical review (Priority: P1)

**Goal**: Build the canonical patient-centered curation layer that unifies raw structured and evidence-linked records into a coherent longitudinal patient record.

**Independent Test**: Select a patient with multiple visits, medications, labs, claims, notes, and imaging metadata; confirm curated outputs present one coherent, source-traceable longitudinal record.

- [X] T009 [US1] Create the Curated Patient Record view in `sql/patient360_curation.sql` with patient-centered summary fields and explicit provenance fields
- [X] T010 [US1] Create the Encounter Summary view in `sql/patient360_curation.sql` linking each encounter to diagnoses, medications, labs, claims, notes, and report/image context
- [X] T011 [P] [US1] Create the Patient Timeline Event view in `sql/patient360_curation.sql` so all patient events sort in clinically meaningful chronological order
- [X] T012 [US1] Add validation queries in `docs/testing.md` for curated patient record completeness, encounter linkage, and timeline ordering

## Phase 4: User Story 2 - Persona-aligned curation for business questions (Priority: P1)

**Goal**: Expose business-ready curated relationships and summaries that directly answer the documented target persona questions.

**Independent Test**: Validate at least one concrete query path for each target persona without reconstructing raw joins manually.

- [X] T013 [US2] Create the Medication Evidence Summary view in `sql/patient360_curation.sql` that links medications to encounter context, status history, and supporting evidence
- [X] T014 [US2] Create the Lab Monitoring Summary view in `sql/patient360_curation.sql` that surfaces current and historical monitoring evidence with patient and encounter linkage
- [X] T015 [US2] Create the Care Gap Signal view in `sql/patient360_curation.sql` with explainable gap categories, triggering evidence, and provenance
- [X] T016 [US2] Add persona-driven validation queries to `docs/testing.md` covering medication review, recent visit summary, HbA1c monitoring evidence, missing follow-up signals, and high-utilization patient identification

## Phase 5: User Story 3 - Semantic view readiness for the Streamlit app (Priority: P2)

**Goal**: Make curated outputs stable and explicit enough to serve as the basis for a future semantic view and Streamlit read model.

**Independent Test**: Review the curated layer and confirm business entities, relationships, and summaries are clear enough for semantic modeling without re-deriving raw logic.

- [X] T017 [US3] Create semantic-view candidate summaries in `sql/patient360_semantic_prep.sql` that expose stable patient-centered and encounter-centered entities without bypassing CURATED
- [X] T018 [US3] Add relationship validation queries in `docs/testing.md` confirming semantic-view candidate entities preserve explicit links across patient, encounter, medication, lab, claim, and evidence asset domains
- [X] T019 [US3] Document the Streamlit read-model assumptions in `README.md` or `docs/architecture.md` so future app work consumes curated entities instead of raw joins

## Phase 6: User Story 4 - Future analysis readiness for reports and imaging assets (Priority: P3)

**Goal**: Preserve report and image-related raw assets as analyzable evidence with stable metadata and patient/encounter linkage for later analysis phases.

**Independent Test**: Select a patient with report or imaging-linked assets and confirm those assets are available as patient-linked evidence with future-analysis-ready metadata.

- [X] T020 [US4] Create the Evidence Asset view in `sql/patient360_curation.sql` that normalizes document, report, lab document, prescription, and imaging-linked assets into one patient-linked evidence model
- [X] T021 [US4] Add explicit imaging/report metadata fields in `sql/patient360_curation.sql` so modality, body part, study/report type, source date, and encounter linkage remain queryable for later analysis
- [X] T022 [US4] Add validation queries in `docs/testing.md` confirming report/image assets are linked to patient and encounter context and remain citation/evidence ready

## Phase 7: Polish & Cross-Cutting Concerns

- [ ] T023 [P] Update `docs/architecture.md` to replace forward-looking `CARE360_DB` references with `PATIENT360` while preserving valid business and workflow content
- [ ] T024 [P] Update `README.md` to reflect the active `PATIENT360` curation and semantic-view direction where current documentation still implies older database assumptions
- [ ] T025 Reconcile future semantic-layer and application object references in documentation and SQL so they do not point at deprecated naming or stale schema assumptions
- [ ] T026 Run and record the end-to-end validation scenarios from `specs/004-patient360-curation/quickstart.md` in `docs/testing.md` or the relevant curation SQL comments

## Dependencies & Execution Order

### Phase Dependencies

- Phase 1 (Setup) must complete before Phase 2
- Phase 2 (Foundational) must complete before any user story phase
- Phase 3 (US1) is the MVP foundation for all later stories
- Phase 4 (US2) depends on US1 curated patient and encounter views
- Phase 5 (US3) depends on US1 and US2 outputs being stable
- Phase 6 (US4) depends on the foundational evidence-asset rules plus US1 patient/encounter linkage
- Phase 7 (Polish) follows all user story phases

### User Story Dependency Graph

- **US1**: Independent after foundations; recommended MVP
- **US2**: Depends on US1
- **US3**: Depends on US1 and benefits from US2
- **US4**: Depends on foundations and US1 linkage

## Parallel Execution Opportunities

- T011 can run in parallel with T009/T010 once the core curated patient and encounter mapping is stable
- T023 and T024 can run in parallel during the polish phase
- T013 and T014 can be developed in parallel after the foundational mapping and provenance rules are complete

## Implementation Strategy

### MVP First

1. Complete Setup and Foundational phases
2. Deliver US1 to establish the canonical curated patient record
3. Deliver US2 to satisfy the core persona questions
4. Add US3 semantic-view readiness
5. Add US4 imaging/report future-analysis readiness
6. Finish with naming cleanup and end-to-end validation

### Suggested MVP Scope

The recommended MVP is **User Story 1** plus the foundational phases. That yields a
coherent curated patient record and patient timeline that all later work can build on.