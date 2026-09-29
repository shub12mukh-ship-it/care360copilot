# Data Model: PATIENT360 Ingestion Completion

## Overview

This document defines the canonical ingestion entities for the `PATIENT360.DOCUMENTS` layer.
These entities normalize staged PDFs, reports, and diagnostic images into traceable ingestion
records that support extraction, chunking, quality review, and later evidence retrieval.

## Entity 1: Canonical Ingested Asset

**Purpose**: Represent every eligible staged PDF, report, or image as one canonical ingestion record.

**Key fields**:
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

**Relationships**:
- one canonical asset may have zero or one extracted-text record
- one canonical asset may have zero or many search chunks
- one canonical asset may have zero or many quality findings
- one canonical asset may have zero or one match-context record

**Validation rules**:
- every eligible staged file appears once in canonical inventory unless intentionally flagged as duplicate-suspect
- canonical stage path must remain queryable and traceable to the originating RAW stage
- unmatched assets remain visible rather than being attached speculatively

## Entity 2: Extracted Document Text

**Purpose**: Preserve the recovered text body for assets where parsing or OCR yields usable content.

**Key fields**:
- ingestion asset identifier
- extraction record identifier
- extraction mode
- extracted text body
- text length and completeness indicators
- extraction outcome status
- failure reason when applicable
- provenance back to canonical asset

**Relationships**:
- each extracted-text record belongs to one canonical asset
- one extracted-text record may generate many search chunks

**Validation rules**:
- every successful extraction links to exactly one canonical asset
- failed extraction attempts retain failure classification
- textless but valid assets must be classified explicitly as metadata-only or unusable for search

## Entity 3: Search Chunk

**Purpose**: Represent ordered, search-ready chunks derived from extracted document text.

**Key fields**:
- chunk identifier
- ingestion asset identifier
- source extraction identifier
- chunk order
- chunk text
- patient identifier when available
- document category
- source date and stage metadata
- chunk eligibility status for indexing

**Relationships**:
- many search chunks may belong to one canonical asset
- many search chunks may belong to one extracted-text record

**Validation rules**:
- chunk order must reconstruct the source document sequence
- every chunk must link back to a canonical asset
- only assets with usable text generate searchable chunks

## Entity 4: Asset Match Context

**Purpose**: Track how a staged asset maps to patient, visit, report, or raw-record context.

**Key fields**:
- ingestion asset identifier
- patient identifier
- visit identifier
- report identifier
- source-record type
- matching basis summary
- confidence or decision status
- unmatched reason when applicable

**Relationships**:
- each match-context record belongs to one canonical asset
- match context may reference one patient and optionally one visit or report record

**Validation rules**:
- matched context must be explainable from synthetic identifiers, filenames, or source metadata
- ambiguous matches must remain unresolved and flagged instead of force-assigned

## Entity 5: Ingestion Quality Finding

**Purpose**: Surface remediable ingestion issues before curation proceeds.

**Key fields**:
- quality finding identifier
- ingestion asset identifier or issue grouping key
- issue category
- severity or review priority
- issue description
- remediation hint
- first-detected timestamp
- status for review lifecycle

**Relationships**:
- many quality findings may belong to one canonical asset
- some quality findings may exist at grouped issue level rather than a single asset row

**Validation rules**:
- issue categories must at minimum cover missing files, broken stage references, duplicates, unparseable assets, and unmatched assets
- findings must point back to the affected asset or issue group clearly enough for remediation

## DOCUMENTS Layer Boundary

### DOCUMENTS responsibilities
- canonical asset inventory for stage-backed files
- extracted text and OCR outcome tracking
- search chunk preparation and search-readiness metadata
- ingestion quality findings and remediation visibility

### Not part of this feature
- business-facing patient curation outputs
- cohort metrics or dashboard summaries
- clinical inference, diagnosis, or treatment recommendation logic

## Readiness Rules For Downstream Consumers

- downstream curation should read standardized ingestion outputs rather than raw stage-specific metadata tables
- provenance from chunk to extracted text to canonical asset must remain queryable
- unmatched and failed assets must remain reviewable before any downstream assumption of completeness
- document search readiness must be separable from metadata-only asset presence