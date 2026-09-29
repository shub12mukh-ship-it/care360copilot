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

**Target Platform**: Snowflake account `JRMWQMS-PA19066` and this repo's local SQL/docs artifacts

**Project Type**: Snowflake-native data application with SQL-first ingestion and curation layers

**Performance Goals**: Ingestion outputs should support the constitution's sub-10-second interactive evidence retrieval target by precomputing searchable chunks and preserving direct provenance paths

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
- Simplicity gate: Pass. The plan extends the repo's SQL-first structure and existing document metadata direction instead of introducing a separate service.

## Project Structure

### Documentation (this feature)

```text
specs/005-patient360-ingestion/
|-- plan.md
|-- research.md
|-- data-model.md
|-- quickstart.md
|-- contracts/
|   |-- ingestion-entities.md
|   |-- search-corpus.md
|   `-- quality-outputs.md
`-- tasks.md
```

### Source Code (repository root)

```text
sql/
|-- patient360_ingestion.sql          # New ingestion-layer SQL objects
|-- patient360_curation.sql           # Existing downstream consumer, may need controlled rewiring later
`-- patient360_semantic_prep.sql      # Existing downstream semantic prep, not the primary change target

docs/
|-- architecture.md                   # Update ingestion-layer architecture narrative
`-- testing.md                        # Add ingestion validation and quality-check queries
```

**Structure Decision**: Keep the feature SQL-first and documentation-backed. Add a dedicated `sql/patient360_ingestion.sql` for canonical ingestion objects rather than overloading curation SQL. Limit plan artifacts to the new ingestion feature folder and update shared docs only where validation and architecture descriptions must reflect the ingestion-first flow.

## Complexity Tracking

No constitutional violations or exceptional complexity justifications are required at plan time. The implementation should stay within the existing SQL-first repository pattern and avoid introducing a separate orchestration service unless a later blocker proves the platform-native approach insufficient.