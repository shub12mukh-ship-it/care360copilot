# Feature Specification: PATIENT360 Ingestion Completion

**Feature Branch**: `[005-patient360-ingestion]`

**Created**: 2026-09-28

**Status**: Draft

**Input**: User description: "Complete the PATIENT360 ingestion layer for PDFs, reports, and images: document text extraction, chunking, Cortex Search indexing, image/report OCR if useful, standardized document metadata, and ingestion quality checks for missing files, broken stage references, duplicate assets, unparseable PDFs, and report/image records without matches."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Build Trusted Document Corpus (Priority: P1)

As a data engineer supporting the copilot, I need every staged PDF and image asset in `PATIENT360` to be represented in a standardized ingestion corpus so downstream search and evidence retrieval operate on a complete and traceable document set.

**Why this priority**: Curation, search, and evidence-cited answers all depend on a reliable ingestion layer. If documents are not normalized first, every downstream layer inherits gaps and broken provenance.

**Independent Test**: This can be fully tested by reconciling staged assets against the standardized ingestion outputs and confirming that each eligible file has metadata, extraction status, and a traceable patient/report linkage where available.

**Acceptance Scenarios**:

1. **Given** staged clinical note, lab result, prescription, and diagnostic image assets exist in `PATIENT360.RAW`, **When** the ingestion workflow runs, **Then** each eligible asset is recorded in a standardized document inventory with canonical stage path, document type, source stage, file identity, and ingestion status.
2. **Given** multiple raw asset sources use different naming or metadata conventions, **When** the ingestion workflow standardizes them, **Then** the resulting inventory presents one consistent metadata shape that downstream consumers can query without source-specific branching.

---

### User Story 2 - Make Documents Searchable and Reviewable (Priority: P2)

As a quality or care workflow owner, I need extracted document text and chunked search content so the copilot can retrieve evidence from reports and notes rather than relying only on structured tables.

**Why this priority**: Searchable document text is the core enabler for evidence-cited answers from unstructured data, which is one of the main product promises in the constitution and architecture.

**Independent Test**: This can be fully tested by selecting a known staged PDF or report, confirming extracted text exists, confirming chunk records are created for searchable content, and verifying the search-ready corpus references the originating asset.

**Acceptance Scenarios**:

1. **Given** a parseable PDF or report asset is present in the standardized inventory, **When** ingestion processing runs, **Then** the system stores extracted text, retains provenance to the original asset, and marks the extraction as successful.
2. **Given** extracted text exceeds a single retrieval unit, **When** chunk preparation runs, **Then** the text is split into ordered chunks suitable for search with patient/document metadata preserved on each chunk.
3. **Given** an image or scanned report contains usable text, **When** OCR-capable processing is applied, **Then** the ingestion output records whether usable text was recovered and whether the asset is searchable or metadata-only.

---

### User Story 3 - Surface Ingestion Defects Before Curation (Priority: P3)

As a platform owner, I need ingestion quality checks that expose missing files, broken stage references, duplicates, unparseable documents, and unmatched report/image assets so the team can correct source issues before curation or analytics rely on bad inputs.

**Why this priority**: The user explicitly directed ingestion-first execution. Quality checks are what make the ingestion layer operationally complete rather than just a best-effort extraction pass.

**Independent Test**: This can be fully tested by introducing representative defects into staged assets or metadata and confirming the quality outputs identify each issue category with enough detail to remediate it.

**Acceptance Scenarios**:

1. **Given** a metadata row points to a stage file that no longer exists, **When** ingestion quality checks run, **Then** the asset is flagged as a broken stage reference.
2. **Given** the same underlying asset appears more than once under duplicate-identifying characteristics, **When** quality checks run, **Then** the duplicates are surfaced in a dedicated issue output rather than silently merged.
3. **Given** a PDF cannot be parsed into usable text, **When** ingestion processing completes, **Then** the asset remains in the document inventory with an explicit unparseable status and remediation visibility.
4. **Given** a diagnostic image or report asset has no trustworthy raw-record match to a patient/report context, **When** quality checks run, **Then** the asset is flagged as unmatched instead of being attached to the wrong patient.

---

### Edge Cases

- What happens when the same document is present in more than one RAW stage with different filenames but identical business identity?
- How does the system handle assets that have metadata but no extractable text and no reliable OCR result?
- What happens when a file path is valid but the asset type cannot be inferred from the stage or filename conventions?
- How does the system behave when a patient-linked raw record exists but multiple candidate staged assets could match it?
- What happens when a document is successfully extracted but contains no clinically useful text beyond boilerplate?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST establish a canonical ingestion inventory for `PATIENT360` document and image assets sourced from the existing RAW stages.
- **FR-002**: The system MUST standardize metadata across clinical note PDFs, lab result PDFs, prescription PDFs, diagnostic images, and related report assets into one queryable shape.
- **FR-003**: Each ingested asset MUST retain provenance including source stage, canonical stage path, source file identity, document category, and ingestion timestamps or lifecycle status markers.
- **FR-004**: The system MUST record whether each asset is text-extracted, OCR-extracted, metadata-only, duplicate-suspect, broken, unmatched, or unparseable.
- **FR-005**: The system MUST extract searchable text from parseable PDF and report assets where usable text is available.
- **FR-006**: The system MUST preserve the extracted text in a form that remains traceable to the original document asset and patient/report context.
- **FR-007**: The system MUST produce ordered search chunks from extracted document text so downstream retrieval can cite specific evidence segments.
- **FR-008**: Each chunk MUST carry enough metadata to support downstream filtering by patient, document type, source asset, and document date when known.
- **FR-009**: The system MUST prepare a search-ready corpus that can be indexed for document retrieval without requiring downstream consumers to reconstruct chunk provenance.
- **FR-010**: The system MUST evaluate image and scanned-report assets for OCR usefulness and classify them as searchable or metadata-only based on whether meaningful text can be recovered.
- **FR-011**: The system MUST flag stage-backed metadata entries whose referenced files are missing or inaccessible.
- **FR-012**: The system MUST detect likely duplicate assets using stable file or business-identity characteristics and surface them as explicit quality findings.
- **FR-013**: The system MUST flag assets that fail parsing or OCR with a reason code or failure category suitable for remediation.
- **FR-014**: The system MUST flag report or image assets that cannot be confidently matched to the expected raw patient/report context.
- **FR-015**: The system MUST expose ingestion quality outputs in a form that can be reviewed before curation logic consumes the underlying assets.
- **FR-016**: The ingestion layer MUST remain aligned with the constitution by operating only under the `PATIENT360` database identity and by preserving synthetic-data-only assumptions.

### Key Entities *(include if feature involves data)*

- **Ingested Asset**: A canonical record for one staged PDF, report, or image file, including identity, type, provenance, status, and matching context.
- **Extracted Document Text**: The recovered text body associated with an ingested asset, including extraction method, completeness status, and document-level provenance.
- **Search Chunk**: A bounded segment of extracted text prepared for retrieval, carrying ordering and filtering metadata tied back to the source asset.
- **Asset Match Context**: The patient/report linkage information used to associate a staged asset with the correct clinical record or to flag it as unmatched.
- **Ingestion Quality Finding**: A reviewable issue record describing missing files, broken references, duplicates, unparseable assets, or unmatched assets.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of eligible files present in the targeted `PATIENT360.RAW` stages appear in the canonical ingestion inventory after an ingestion run.
- **SC-002**: At least 95% of parseable document assets produce a non-empty extracted-text record or an explicit failure classification that explains why searchable text is unavailable.
- **SC-003**: 100% of searchable extracted documents produce chunk records that preserve source-asset provenance and patient/document filtering attributes.
- **SC-004**: All five required ingestion defect categories are surfaced in reviewable quality outputs: missing files, broken stage references, duplicate assets, unparseable documents, and unmatched report/image assets.
- **SC-005**: A reviewer can trace any indexed search chunk back to its originating staged asset and document metadata in under 2 minutes using only ingestion outputs.

## Assumptions

- Existing `PATIENT360.RAW` stages remain the system of record for source PDFs and images; this feature does not introduce a new canonical source stage.
- The ingestion feature may keep some assets as metadata-only when OCR or parsing yields no reliable searchable text.
- Curation and analytics consumers will read only from standardized ingestion outputs rather than directly from stage-specific metadata tables once this feature is complete.
- Matching between staged assets and patient/report context will rely on existing synthetic identifiers, filenames, and available metadata conventions already present in the repository and Snowflake objects.
- Search indexing readiness is in scope for this feature, while persona-facing application behavior remains part of downstream curation and copilot work.