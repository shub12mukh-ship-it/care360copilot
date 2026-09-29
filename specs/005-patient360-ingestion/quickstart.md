# Quickstart Validation Guide: PATIENT360 Ingestion Completion

## Purpose

This guide describes how to validate that the `PATIENT360.DOCUMENTS` ingestion layer is ready
to support search and downstream curation.

## Prerequisites

- staged synthetic assets exist in the expected `PATIENT360.RAW` stages
- canonical ingestion outputs have been created for asset inventory, extracted text, chunks, and quality findings
- validation queries can inspect provenance from stage path through chunk outputs

## Validation Scenario 1: Canonical asset inventory reconciliation

1. List eligible staged files from the targeted RAW stages.
2. Review the canonical ingestion inventory.
3. Confirm every eligible staged asset appears once in the inventory or is explicitly marked duplicate-suspect.
4. Confirm the canonical stage path remains visible for each row.

## Validation Scenario 2: Successful text extraction for representative PDFs

1. Select at least one clinical note PDF, one lab result PDF, and one prescription PDF.
2. Review the extracted-text output for those assets.
3. Confirm each successful extraction retains provenance back to the canonical asset and stage path.
4. Confirm unsuccessful extractions are explicitly classified rather than disappearing.

## Validation Scenario 3: OCR usefulness classification for image or scanned assets

1. Select representative diagnostic images or scanned report assets.
2. Review their processing and extraction classifications.
3. Confirm each asset is marked searchable only when useful text was recovered.
4. Confirm non-searchable assets remain visible as metadata-only or failed-classification records.

## Validation Scenario 4: Search chunk generation and provenance tracing

1. Select a document with successful extracted text.
2. Review its chunk records.
3. Confirm chunk ordering is stable and reconstructs the source document sequence.
4. Confirm each chunk can be traced back to the extracted-text record and canonical asset in under 2 minutes.

## Validation Scenario 5: Quality finding coverage

1. Review the ingestion quality outputs.
2. Confirm the outputs include missing files, broken stage references, duplicate assets, unparseable assets, and unmatched report/image assets.
3. Confirm each finding includes enough detail to remediate the issue without ad hoc repository archaeology.

## Validation Scenario 6: Governance and layer-boundary checks

1. Inspect newly created ingestion artifacts and shared documentation updates.
2. Confirm `PATIENT360` is used consistently and no new `CARE360_DB` references were introduced.
3. Confirm the design keeps search preparation inside `DOCUMENTS` rather than bypassing the ingestion layer through `CURATED` or `ANALYTICS`.

## Expected Outcomes

- a canonical ingestion inventory exists for staged document and image assets
- searchable text and chunked corpus outputs are traceable to original staged assets
- OCR is applied selectively and classified honestly
- ingestion defects are surfaced explicitly before curation consumes the assets
- no constitutional naming violations or layer-boundary violations are introduced