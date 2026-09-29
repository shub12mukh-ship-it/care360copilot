# Implementation Plan: PATIENT360 Ingestion Completion

**Branch**: `[005-patient360-ingestion]` | **Date**: 2026-09-28 | **Spec**: [specs/005-patient360-ingestion/spec.md](specs/005-patient360-ingestion/spec.md)

**Input**: Feature specification from `/specs/005-patient360-ingestion/spec.md`

## Summary

Complete the ingestion layer ahead of further curation by standardizing all stage-backed document and image assets into a canonical `PATIENT360.DOCUMENTS` corpus, extracting searchable text where possible, preparing chunked search-ready outputs, and surfacing ingestion quality defects before downstream layers consume those assets.

## Technical Context

**Language/Version**: Snowflake SQL for core ingestion objects; Python 3 with existing project tooling only for optional orchestration or validation helpers

**Primary Dependencies**: Snowflake platform objects under `PATIENT360`, existing RAW stages, existing `streamlit` and `snowflake-snowpark-python` project dependencies, Cortex AI document-processing capabilities, Cortex Search

**Storage**: Snowflake database `PATIENT360` with focus on `RAW` source stages and `DOCUMENTS` ingestion outputs

**Testing**: SQL validation queries documented in `docs/testing.md` and feature quickstart scenarios

**Target Platform**: Snowflake account `JRMWQMS-PA19066` and this repo’s local SQL/docs artifacts

**Project Type**: Snowflake-native data application with SQL-first ingestion and curation layers

**Performance Goals**: Ingestion outputs should support the constitution’s sub-10-second interactive evidence retrieval target by precomputing searchable chunks and preserving direct provenance paths

**Constraints**: Must use `PATIENT360` only; must keep synthetic-data-only assumptions; must prefer SQL-first repository patterns; must use existing RAW stages rather than inventing a replacement source layout; must keep failures visible instead of dropping bad assets silently

**Scale/Scope**: Four primary asset domains already known in RAW stages: clinical note PDFs, lab result PDFs, prescription PDFs, and diagnostic images, plus their patient/report matching context and quality outputs

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- `PATIENT360` naming gate: Pass. The feature uses `PATIENT360` as the only active database identity.
- Product-scope gate: Pass. The feature directly supports the hackathon scope by enabling grounded document evidence and traceable patient context.
- Synthetic-data boundary gate: Pass. The plan assumes only synthetic assets already staged in `PATIENT360.RAW`.
- Snowflake-native architecture gate: Pass. The design keeps storage, extraction, search prep, and quality checks inside Snowflake-native patterns.
- Layered pipeline gate: Pass. The work strengthens the `DOCUMENTS` ingestion layer so curation and analytics can consume standardized outputs rather than bypassing ingestion.
- Evidence-citation gate: Pass. Searchable text, chunk provenance, and quality visibility are all required specifically to support cited evidence later.
- Simplicity gate: Pass. The plan extends the repo’s SQL-first structure and existing document metadata direction instead of introducing a separate service.

## Project Structure

### Documentation (this feature)

```text
specs/005-patient360-ingestion/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── ingestion-entities.md
│   ├── search-corpus.md
│   └── quality-outputs.md
└── tasks.md
```

### Source Code (repository root)

```text
sql/
├── patient360_ingestion.sql          # New ingestion-layer SQL objects
├── patient360_curation.sql           # Existing downstream consumer, may need controlled rewiring later
└── patient360_semantic_prep.sql      # Existing downstream semantic prep, not the primary change target

docs/
├── architecture.md                   # Update ingestion-layer architecture narrative
└── testing.md                        # Add ingestion validation and quality-check queries
```

**Structure Decision**: Keep the feature SQL-first and documentation-backed. Add a dedicated `sql/patient360_ingestion.sql` for canonical ingestion objects rather than overloading curation SQL. Limit plan artifacts to the new ingestion feature folder and update shared docs only where validation and architecture descriptions must reflect the ingestion-first flow.

## Phase 0: Research

### Research Artifact: `specs/005-patient360-ingestion/research.md`

#### Decision 1: Keep existing RAW stages as the source of truth
- **Decision**: Treat `PATIENT360.RAW.CLINICAL_NOTE_PDFS`, `PATIENT360.RAW.LAB_RESULT_PDFS`, `PATIENT360.RAW.PRESCRIPTION_PDFS`, and `PATIENT360.RAW.DIAGNOSTIC_IMAGES` as the authoritative file sources.
- **Rationale**: The user already confirmed the assets exist there and asked for rewiring rather than another upload flow.
- **Alternatives considered**:
  - Create new canonical stages in `DOCUMENTS`: rejected because it duplicates storage responsibility and conflicts with the user’s correction.
  - Ingest directly from local files again: rejected because the data is already present in Snowflake.

#### Decision 2: Standardize all assets through one canonical ingestion inventory
- **Decision**: Build a canonical asset inventory in `PATIENT360.DOCUMENTS` that normalizes stage path, asset type, source stage, source file identity, patient/report match context, and processing status across all document families.
- **Rationale**: Downstream search, curation, and quality workflows need one stable entry point instead of per-stage custom joins.
- **Alternatives considered**:
  - Keep separate per-asset metadata tables only: rejected because every consumer would need source-specific branching.
  - Push normalization into curation views: rejected because the user explicitly moved ingestion ahead of curation.

#### Decision 3: Separate asset inventory, extracted text, chunks, and quality findings into distinct outputs
- **Decision**: Model ingestion as four layers of outputs: canonical inventory, extracted-text records, chunk records, and quality findings.
- **Rationale**: This makes failures visible, keeps provenance explicit, and allows partially successful ingestion runs without losing track of bad assets.
- **Alternatives considered**:
  - Store everything in one wide table: rejected because it blurs lifecycle state and makes quality reporting harder.
  - Materialize only chunks: rejected because metadata-only and failed assets would disappear from operational visibility.

#### Decision 4: Use OCR selectively and classify non-searchable assets explicitly
- **Decision**: Attempt OCR or text recovery only where meaningful text can be obtained; otherwise keep the asset in metadata-only state with an explicit classification.
- **Rationale**: Diagnostic images and scans are not uniformly text-bearing, and pretending every image is searchable would create false completeness.
- **Alternatives considered**:
  - Force OCR across all images: rejected because it adds noise and misleading outputs for non-textual images.
  - Ignore images entirely: rejected because the user explicitly included images and report/image matching in scope.

#### Decision 5: Quality outputs must block silent failure, not necessarily ingestion completion
- **Decision**: Ingestion should preserve bad or unmatched assets in the canonical inventory while surfacing them through quality findings rather than dropping them.
- **Rationale**: The goal is operational completeness and reviewability before curation. Silent omission would hide exactly the defects the user asked to catch.
- **Alternatives considered**:
  - Exclude failed assets from ingestion outputs: rejected because it undermines defect tracking.
  - Hard-fail the entire ingestion set on one bad file: rejected because one broken document should not erase visibility into the rest of the corpus.

#### Decision 6: Search readiness belongs in DOCUMENTS, not in CURATED
- **Decision**: Chunking and search-ready corpus preparation stay in the `DOCUMENTS` layer and feed future retrieval directly.
- **Rationale**: The constitution defines `DOCUMENTS` as the ingestion pipeline layer for parse, chunk, and index responsibilities.
- **Alternatives considered**:
  - Put chunks in `ANALYTICS`: rejected because chunks are ingestion artifacts, not analytical summaries.
  - Put chunks in `CURATED`: rejected because chunking is document-processing plumbing, not business curation.

## Phase 1: Design & Contracts

### Data Model Artifact: `specs/005-patient360-ingestion/data-model.md`

#### Entity 1: Canonical Ingested Asset
- **Purpose**: Represent every eligible staged PDF, report, or image as one canonical ingestion record.
- **Key fields**:
  - ingestion asset identifier
  - source stage name
  - canonical stage path
  - original file name
  - asset family and document category
  - patient identifier when matched
  - visit/report identifier when matched
  - match confidence or match status
  - processing status
  - extraction method classification
  - discovery and processing timestamps
- **Validation rules**:
  - every eligible staged file appears once in canonical inventory unless intentionally flagged as duplicate-suspect
  - canonical stage path must remain queryable and traceable to the originating RAW stage
  - unmatched assets remain visible rather than being attached speculatively

#### Entity 2: Extracted Document Text
- **Purpose**: Preserve the recovered text body for assets where parsing or OCR yields usable content.
- **Key fields**:
  - ingestion asset identifier
  - extraction record identifier
  - extraction mode
  - extracted text body
  - text length and completeness indicators
  - extraction outcome status
  - failure reason when applicable
  - provenance back to canonical asset
- **Validation rules**:
  - every successful extraction links to exactly one canonical asset
  - failed extraction attempts retain failure classification
  - textless but valid assets must be classified explicitly as metadata-only or unusable for search

#### Entity 3: Search Chunk
- **Purpose**: Represent ordered, search-ready chunks derived from extracted document text.
- **Key fields**:
  - chunk identifier
  - ingestion asset identifier
  - source extraction identifier
  - chunk order
  - chunk text
  - patient identifier when available
  - document category
  - source date and stage metadata
  - chunk eligibility status for indexing
- **Validation rules**:
  - chunk order must reconstruct the source document sequence
  - every chunk must link back to a canonical asset
  - only assets with usable text generate searchable chunks

#### Entity 4: Asset Match Context
- **Purpose**: Track how a staged asset maps to patient, visit, report, or raw-record context.
- **Key fields**:
  - ingestion asset identifier
  - patient identifier
  - visit identifier
  - report identifier
  - source-record type
  - matching basis summary
  - confidence or decision status
  - unmatched reason when applicable
- **Validation rules**:
  - matched context must be explainable from synthetic identifiers, filenames, or source metadata
  - ambiguous matches must remain unresolved and flagged instead of force-assigned

#### Entity 5: Ingestion Quality Finding
- **Purpose**: Surface remediable ingestion issues before curation proceeds.
- **Key fields**:
  - quality finding identifier
  - ingestion asset identifier or issue grouping key
  - issue category
  - severity or review priority
  - issue description
  - remediation hint
  - first-detected timestamp
  - status for review lifecycle
- **Validation rules**:
  - issue categories must at minimum cover missing files, broken stage references, duplicates, unparseable assets, and unmatched assets
  - findings must point back to the affected asset or issue group clearly enough for remediation

### Contract Artifacts

#### `specs/005-patient360-ingestion/contracts/ingestion-entities.md`
Define the stable query-facing contract for canonical inventory and extracted-text outputs:
- canonical asset inventory fields expected by downstream consumers
- extraction-status vocabulary
- patient/report matching fields and nullability rules
- provenance expectations for every row

#### `specs/005-patient360-ingestion/contracts/search-corpus.md`
Define the search-ready contract:
- chunk-level required metadata
- ordering expectations
- eligibility rules for indexing
- traceability requirement from chunk to extracted text to canonical asset

#### `specs/005-patient360-ingestion/contracts/quality-outputs.md`
Define the ingestion-quality review contract:
- mandatory issue categories
- required columns for remediation and triage
- grouping and deduplication expectations for findings
- readiness rule for proceeding into curation review

### Quickstart Artifact: `specs/005-patient360-ingestion/quickstart.md`
Include end-to-end validation scenarios covering:
1. Canonical asset inventory reconciliation against RAW stages.
2. Successful text extraction for representative PDF assets.
3. OCR usefulness classification for representative image/report assets.
4. Search chunk generation and provenance tracing.
5. Quality finding detection for broken references, duplicates, unparseable assets, and unmatched assets.
6. Governance validation confirming no new `CARE360_DB` references and no bypass of the `DOCUMENTS` layer.

## Planned Repository Changes

### New artifacts
- `specs/005-patient360-ingestion/plan.md`
- `specs/005-patient360-ingestion/research.md`
- `specs/005-patient360-ingestion/data-model.md`
- `specs/005-patient360-ingestion/contracts/ingestion-entities.md`
- `specs/005-patient360-ingestion/contracts/search-corpus.md`
- `specs/005-patient360-ingestion/contracts/quality-outputs.md`
- `specs/005-patient360-ingestion/quickstart.md`
- `sql/patient360_ingestion.sql`

### Expected follow-on updates during implementation
- `docs/architecture.md`
- `docs/testing.md`
- potentially downstream SQL references once curation is rewired to consume the new ingestion outputs deliberately rather than ad hoc stage metadata

## Post-Design Constitution Check

- `PATIENT360` naming: Pass.
- Product-scope alignment: Pass; the design directly supports evidence-cited patient workflows.
- Synthetic-only boundary: Pass; no real-PHI path introduced.
- Snowflake-native architecture: Pass; design remains in Snowflake SQL, documents, and platform-native processing.
- Layered pipeline integrity: Pass; `DOCUMENTS` is strengthened as an explicit ingestion layer before curation.
- Simplicity and local-pattern fit: Pass; design adds one dedicated ingestion SQL module and feature-local plan artifacts instead of a new service tier.

## Complexity Tracking

No constitutional violations or exceptional complexity justifications are required at plan time. The implementation should stay within the existing SQL-first repository pattern and avoid introducing a separate orchestration service unless a later blocker proves the platform-native approach insufficient.