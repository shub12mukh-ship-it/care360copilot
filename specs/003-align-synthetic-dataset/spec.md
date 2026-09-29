# Feature Specification: Align Synthetic Dataset with CARE360 MVP

**Feature Branch**: `[003-align-synthetic-dataset]`

**Created**: 2026-09-27

**Status**: Draft

**Input**: User description: "Now that we have Sreeja's changes, what is next which aligns with our snowflake project?"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Load constitution-compatible synthetic data into the current MVP (Priority: P1)

As a project maintainer, I want the useful portions of the synthetic dataset work
to be aligned to the existing CARE360 MVP so the team can continue building the
Snowflake-native evidence copilot without introducing a second data model or
conflicting product scope.

**Why this priority**: The team already has new synthetic assets in the repository,
but the current constitution and README define a narrower Snowflake Patient 360
MVP. Aligning the data work is the minimum path to continue safely.

**Independent Test**: Can be fully tested by identifying which of Sreeja's assets
map into the current CARE360 data model, loading the compatible subset into the
current Snowflake pipeline, and verifying the existing Patient 360 and document
search workflows still operate on a single coherent model.

**Acceptance Scenarios**:

1. **Given** new synthetic structured data and document assets exist in the repository,
   **When** the alignment workflow is executed, **Then** only constitution-compatible
   data elements are mapped into the existing CARE360 model.
2. **Given** aligned data has been loaded, **When** a maintainer validates the current
   Patient 360 and evidence retrieval flows, **Then** they operate against one
   consistent Snowflake dataset rather than a parallel product model.

---

### User Story 2 - Preserve the hackathon product boundary while reusing useful assets (Priority: P2)

As a product owner, I want the team to reuse the useful parts of Sreeja's work
without drifting into unsupported features such as treatment recommendation,
real-PHI handling, or a separate patient-management platform.

**Why this priority**: The constitution treats the hackathon brief as the product
canon. Reuse is valuable, but only if it stays within the Snowflake-native evidence
copilot scope.

**Independent Test**: Can be tested by reviewing the aligned dataset scope and
confirming that no unsupported entities or workflows are introduced into the MVP
without explicit constitutional amendment.

**Acceptance Scenarios**:

1. **Given** a proposed dataset alignment plan, **When** it is reviewed against the
   constitution, **Then** unsupported scope expansions are excluded or explicitly
   deferred.
2. **Given** synthetic files include additional document or image categories,
   **When** the team decides what to ingest, **Then** only assets that support the
   current personas and evidence-copilot use cases are included in the MVP path.

---

### User Story 3 - Make the next implementation step clear for planning and execution (Priority: P3)

As an engineer, I want a clear feature specification for the next aligned step so
that `/speckit-plan` and `/speckit-tasks` can produce a concrete implementation path.

**Why this priority**: The repository already contains broad plans and generated
assets. The team needs one bounded feature to implement next, not another open-ended
dataset expansion.

**Independent Test**: Can be tested by handing this spec to the planning phase and
confirming the resulting plan stays within the current CARE360 architecture and
business scope.

**Acceptance Scenarios**:

1. **Given** this specification exists, **When** the team runs `/speckit-plan`,
   **Then** the resulting plan focuses on aligning and loading compatible synthetic
   data into CARE360 rather than creating a second independent platform.

---

### Edge Cases

- What happens when Sreeja's data contains entities or relationships that do not
  exist in the current CARE360 schema?
- How does the system handle document assets that are useful for storage or search
  but not yet represented in the current Patient 360 UI?
- What happens when a generated asset is synthetically valid but unnecessary for
  the hackathon personas and current MVP scope?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The project MUST define an alignment workflow that maps constitution-compatible
  portions of Sreeja's synthetic dataset work into the existing CARE360 MVP data model.
- **FR-002**: The alignment workflow MUST preserve the current product boundary:
  Snowflake-native evidence copilot, synthetic data only, no diagnosis, no treatment
  recommendation, and no real-PHI enablement.
- **FR-003**: The team MUST be able to distinguish which new structured files,
  document files, and metadata are in-scope for the current MVP and which are deferred.
- **FR-004**: The aligned dataset MUST continue to support the four target personas:
  Clinical Care Coordinator, Quality & Compliance Analyst, Population Health Manager,
  and Clinical Pharmacist.
- **FR-005**: The aligned dataset MUST preserve evidence traceability so answers can
  still cite source records, documents, and dates.
- **FR-006**: The aligned dataset workflow MUST avoid introducing a second parallel
  database or product model when the existing CARE360 architecture can be extended.
- **FR-007**: The team MUST be able to validate that aligned structured data and
  aligned document metadata load successfully into Snowflake and remain queryable by
  the current Patient 360 and evidence retrieval workflows.
- **FR-008**: Document and image assets that are not yet needed by the current UI or
  evidence-copilot personas MUST be explicitly marked as deferred rather than silently
  included.

### Key Entities *(include if feature involves data)*

- **Aligned Synthetic Dataset**: The subset of Sreeja's structured and unstructured
  synthetic assets that can be used by the current CARE360 MVP without violating the
  constitution.
- **CARE360 Canonical Patient Record**: The patient-centered dataset already used by
  the Patient 360 dashboard and evidence copilot.
- **Deferred Asset**: Any generated file, metadata record, or relationship that is
  synthetically valid but not required for the current MVP scope.
- **Alignment Mapping**: The documented relationship between Sreeja's files and the
  existing CARE360 schemas, tables, document metadata, and search pipeline.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Maintainers can identify, in one pass, which synthetic assets are in-scope
  for the current CARE360 MVP and which are deferred.
- **SC-002**: The aligned synthetic dataset supports the current Patient 360 and evidence
  retrieval workflows without requiring a second independent product/database model.
- **SC-003**: Reviewers can verify that the aligned dataset remains within the hackathon
  problem statement and target-user scope with no unresolved scope violations.
- **SC-004**: The team can proceed to planning with a bounded implementation target instead
  of an open-ended dataset expansion.

## Assumptions

- The existing CARE360 architecture and constitution remain the source of truth for
  the current MVP.
- Sreeja's generated synthetic assets are available locally in the repository and can
  be evaluated for reuse without requiring regeneration.
- A subset of the new dataset work is reusable, but not all of it belongs in the MVP.
- Existing Patient 360 and document-search workflows should be reused rather than replaced.