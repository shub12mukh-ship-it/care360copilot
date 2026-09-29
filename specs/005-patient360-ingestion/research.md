# Research: PATIENT360 Ingestion Completion

**Feature**: `specs/005-patient360-ingestion`
**Created**: 2026-09-28

## Decision 1: Keep existing RAW stages as the source of truth

**Decision**: Treat `PATIENT360.RAW.CLINICAL_NOTE_PDFS`, `PATIENT360.RAW.LAB_RESULT_PDFS`, `PATIENT360.RAW.PRESCRIPTION_PDFS`, and `PATIENT360.RAW.DIAGNOSTIC_IMAGES` as the authoritative file sources.

**Rationale**:
- The user already confirmed the assets exist there and asked for rewiring rather than another upload flow.
- Reusing the existing RAW stages preserves the layered pipeline and avoids duplicating storage responsibility.
- Downstream ingestion work should normalize and validate these assets, not invent a second canonical landing zone.

**Alternatives considered**:
- Create new canonical stages in `DOCUMENTS`: rejected because it duplicates storage responsibility and conflicts with the user's correction.
- Ingest directly from local files again: rejected because the data is already present in Snowflake.

## Decision 2: Standardize all assets through one canonical ingestion inventory

**Decision**: Build a canonical asset inventory in `PATIENT360.DOCUMENTS` that normalizes stage path, asset type, source stage, source file identity, patient/report match context, and processing status across all document families.

**Rationale**:
- Downstream search, curation, and quality workflows need one stable entry point instead of per-stage custom joins.
- A unified inventory preserves provenance and removes source-specific branching from every future consumer.
- The feature spec requires one queryable shape across PDFs, reports, and diagnostic images.

**Alternatives considered**:
- Keep separate per-asset metadata tables only: rejected because every consumer would need source-specific branching.
- Push normalization into curation views: rejected because the user explicitly moved ingestion ahead of curation.

## Decision 3: Separate asset inventory, extracted text, chunks, and quality findings into distinct outputs

**Decision**: Model ingestion as four layers of outputs: canonical inventory, extracted-text records, chunk records, and quality findings.

**Rationale**:
- This keeps lifecycle state explicit and makes failures reviewable instead of disappearing into a single wide structure.
- Assets without usable text still need to remain visible for remediation and provenance.
- Search preparation and defect monitoring have different consumers and should not be conflated.

**Alternatives considered**:
- Store everything in one wide table: rejected because it blurs lifecycle state and makes quality reporting harder.
- Materialize only chunks: rejected because metadata-only and failed assets would disappear from operational visibility.

## Decision 4: Use OCR selectively and classify non-searchable assets explicitly

**Decision**: Attempt OCR or text recovery only where meaningful text can be obtained; otherwise keep the asset in metadata-only state with an explicit classification.

**Rationale**:
- Diagnostic images and scans are not uniformly text-bearing, and pretending every image is searchable would create false completeness.
- The feature is about trustworthy ingestion, not optimistic extraction counts.
- The user explicitly asked for OCR "if useful," which means selective use rather than blanket application.

**Alternatives considered**:
- Force OCR across all images: rejected because it adds noise and misleading outputs for non-textual images.
- Ignore images entirely: rejected because the user explicitly included images and report/image matching in scope.

## Decision 5: Quality outputs must block silent failure, not necessarily ingestion completion

**Decision**: Ingestion should preserve bad or unmatched assets in the canonical inventory while surfacing them through quality findings rather than dropping them.

**Rationale**:
- The goal is operational completeness and reviewability before curation. Silent omission would hide exactly the defects the user asked to catch.
- The feature requires issue categories for missing files, broken references, duplicates, unparseable assets, and unmatched records.
- Preserving failed assets keeps remediation traceable over time.

**Alternatives considered**:
- Exclude failed assets from ingestion outputs: rejected because it undermines defect tracking.
- Hard-fail the entire ingestion set on one bad file: rejected because one broken document should not erase visibility into the rest of the corpus.

## Decision 6: Search readiness belongs in DOCUMENTS, not in CURATED

**Decision**: Chunking and search-ready corpus preparation stay in the `DOCUMENTS` layer and feed future retrieval directly.

**Rationale**:
- The constitution defines `DOCUMENTS` as the ingestion pipeline layer for parse, chunk, and index responsibilities.
- Chunks are ingestion artifacts, not patient-facing business entities.
- Keeping them in `DOCUMENTS` preserves a clean boundary before curation and analytics.

**Alternatives considered**:
- Put chunks in `ANALYTICS`: rejected because chunks are ingestion artifacts, not analytical summaries.
- Put chunks in `CURATED`: rejected because chunking is document-processing plumbing, not business curation.