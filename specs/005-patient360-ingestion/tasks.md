# Tasks: PATIENT360 Ingestion Completion

**Feature**: `specs/005-patient360-ingestion`
**Input**: `specs/005-patient360-ingestion/spec.md`
**Prerequisites**: `plan.md`, `research.md`, `data-model.md`, `contracts/`, `quickstart.md`

## Phase 1: Setup

- [X] T001 Review `specs/005-patient360-ingestion/spec.md`, `specs/005-patient360-ingestion/plan.md`, and `specs/005-patient360-ingestion/research.md` to lock the ingestion-first scope, `PATIENT360` naming boundary, and existing RAW-stage source-of-truth assumptions
- [X] T002 Create `sql/patient360_ingestion.sql` and record the DOCUMENTS-layer object naming strategy for canonical asset inventory, extracted text, search chunks, and quality findings
- [X] T003 Create an ingestion validation skeleton in `docs/testing.md` or `specs/005-patient360-ingestion/quickstart.md` that maps staged-asset reconciliation, extraction success, chunk provenance, and quality findings to concrete review steps

## Phase 2: Foundational

- [X] T004 Define the canonical staged-asset inventory model in `sql/patient360_ingestion.sql` so one eligible staged file appears once in canonical inventory unless intentionally flagged as duplicate-suspect, and so canonical stage path remains queryable and traceable to the originating RAW stage
- [X] T005 Define match-context handling in `sql/patient360_ingestion.sql` so matched context remains explainable from synthetic identifiers, filenames, or source metadata, and ambiguous matches remain unresolved and flagged instead of force-assigned
- [X] T006 Define extraction-status vocabulary and lifecycle rules in `sql/patient360_ingestion.sql` covering successful, pending, metadata-only, duplicate-suspect, broken, unmatched, and unparseable states
- [X] T007 Define chunking rules in `sql/patient360_ingestion.sql` using the constitution's documented defaults of 800-character chunks and 100-character overlap, preserving provenance from chunk to extracted text to canonical asset
- [X] T008 Add governance and boundary validation notes in `docs/testing.md` or `sql/patient360_ingestion.sql` comments proving no new `CARE360_DB` references were introduced and that search-preparation outputs stay in `DOCUMENTS`

## Phase 3: User Story 1 - Build trusted document corpus (Priority: P1)

**Goal**: Normalize staged PDFs and images into one canonical ingestion corpus with stable provenance and patient/report linkage where available.

**Independent Test**: Reconcile staged assets against the standardized ingestion outputs and confirm that each eligible file has metadata, extraction status, and a traceable patient/report linkage where available.

- [X] T009 [US1] Create the canonical ingested-asset view or table set in `sql/patient360_ingestion.sql` with source stage name, canonical stage path, original file name, asset family, document category, patient identifier when matched, visit/report identifier when matched, match confidence or match status, processing status, extraction method classification, and discovery and processing timestamps
- [X] T010 [US1] Implement the standardized source-to-asset normalization logic in `sql/patient360_ingestion.sql` for clinical note PDFs, lab result PDFs, prescription PDFs, diagnostic images, and related report assets so downstream consumers can query one consistent metadata shape
- [X] T011 [P] [US1] Implement the asset match-context output in `sql/patient360_ingestion.sql` with patient identifier, visit identifier, report identifier, source-record type, matching basis summary, confidence or decision status, and unmatched reason when applicable
- [X] T012 [US1] Add validation queries in `docs/testing.md` confirming eligible RAW-stage files reconcile to the canonical ingestion inventory and unmatched assets remain visible instead of being attached speculatively

## Phase 4: User Story 2 - Make documents searchable and reviewable (Priority: P2)

**Goal**: Produce extracted-text and chunked search-ready outputs with honest OCR classification and full provenance.

**Independent Test**: Select known staged PDF or report assets, confirm extracted text exists where expected, confirm chunk records are created for searchable content, and confirm the search-ready corpus references the originating asset.

- [X] T013 [US2] Create the extracted-document-text output in `sql/patient360_ingestion.sql` with ingestion asset identifier, extraction record identifier, extraction mode, extracted text body, text length and completeness indicators, extraction outcome status, failure reason when applicable, and provenance back to the canonical asset
- [X] T014 [US2] Implement selective OCR or text-recovery classification logic in `sql/patient360_ingestion.sql` so image and scanned-report assets are marked searchable only when meaningful text can be recovered, otherwise remaining metadata-only with explicit classification
- [X] T015 [P] [US2] Create the search-chunk output in `sql/patient360_ingestion.sql` with chunk identifier, ingestion asset identifier, source extraction identifier, chunk order, chunk text, patient identifier when available, document category, source date and stage metadata, and chunk eligibility status for indexing; preserve the rule that chunk order must reconstruct the source document sequence and only assets with usable text generate searchable chunks
- [X] T016 [US2] Add validation queries in `docs/testing.md` for representative PDF extraction success, OCR usefulness classification, chunk ordering, and traceability from chunk to extracted text to canonical asset

## Phase 5: User Story 3 - Surface ingestion defects before curation (Priority: P3)

**Goal**: Expose operational ingestion defects explicitly so curation does not consume a silently incomplete or misleading document corpus.

**Independent Test**: Introduce or inspect representative defects and confirm quality outputs identify missing files, broken stage references, duplicates, unparseable documents, and unmatched report/image assets with enough detail to remediate them.

- [X] T017 [US3] Create the ingestion-quality-finding output in `sql/patient360_ingestion.sql` with quality finding identifier, ingestion asset identifier or issue grouping key, issue category, severity or review priority, issue description, remediation hint, first-detected timestamp, and status for review lifecycle
- [X] T018 [US3] Implement broken-reference and missing-file detection in `sql/patient360_ingestion.sql` so quality findings clearly identify inaccessible or absent stage paths
- [X] T019 [P] [US3] Implement duplicate-asset and unmatched-asset detection in `sql/patient360_ingestion.sql` so repeated logical assets can be grouped while ambiguous patient/report matches remain unresolved and reviewable
- [ ] T020 [US3] Implement unparseable-asset detection in `sql/patient360_ingestion.sql` so failed parsing or OCR outcomes remain visible in canonical inventory and produce explicit remediation-oriented quality findings
- [X] T021 [US3] Add quality-validation queries in `docs/testing.md` covering all five mandatory defect categories and confirming curation can review open findings rather than assuming silent completeness

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T022 [P] Update `docs/architecture.md` to document the ingestion-first `PATIENT360.DOCUMENTS` flow, existing RAW stages as the source of truth, and the separation of canonical inventory, extracted text, search chunks, and quality findings
- [X] T023 [P] Update `docs/testing.md` to include the end-to-end quickstart validation scenarios for reconciliation, extraction, OCR classification, chunk provenance, and quality findings
- [ ] T024 Reconcile any downstream references in `sql/patient360_curation.sql`, `sql/patient360_semantic_prep.sql`, `docs/architecture.md`, or `README.md` that still imply direct stage-specific metadata consumption instead of planned standardized ingestion outputs
- [ ] T025 Run and record the end-to-end validation scenarios from `specs/005-patient360-ingestion/quickstart.md` in `docs/testing.md` or `sql/patient360_ingestion.sql` comments so the ingestion feature has a documented review path

## Dependencies & Execution Order

### Phase Dependencies

- Phase 1 (Setup) must complete before Phase 2
- Phase 2 (Foundational) must complete before any user story phase
- Phase 3 (US1) is the MVP foundation for all later stories
- Phase 4 (US2) depends on US1 canonical inventory and match-context outputs
- Phase 5 (US3) depends on US1 inventory status fields and benefits from US2 extraction outcomes
- Phase 6 (Polish) follows all user story phases

### User Story Dependency Graph

- **US1**: Independent after foundations; recommended MVP
- **US2**: Depends on US1
- **US3**: Depends on US1 and benefits from US2

## Parallel Execution Opportunities

- T011 can run in parallel with T009/T010 once the canonical inventory shape is stable
- T015 can run in parallel with T013/T014 once extraction fields and chunking rules are defined
- T019 can run in parallel with T018/T020 once the quality-finding output shape is established
- T022 and T023 can run in parallel during the polish phase

## Implementation Strategy

### MVP First

1. Complete Setup and Foundational phases
2. Deliver US1 to establish the canonical ingestion inventory and match context
3. Deliver US2 to make the document corpus searchable and reviewable
4. Deliver US3 to surface ingestion defects before curation
5. Finish with architecture, validation, and downstream reference cleanup

### Suggested MVP Scope

The recommended MVP is **User Story 1** plus the foundational phases. That yields a stable,
traceable ingestion corpus that later extraction, chunking, and quality work can build on.