# Contract: Semantic View Readiness

## Purpose

This contract defines what the future semantic view can depend on from the curated layer.

## Semantic Readiness Requirements

- Business entities must have stable names and meanings.
- Relationship paths between patient, encounter, medication, lab, claim, and evidence asset must be explicit.
- Measures and summaries must be explainable to business users and reviewers.
- Evidence-linked fields must remain traceable to source records and documents.

## Expected Semantic Inputs

- patient-centered summary entities
- encounter-centered detail entities
- medication/lab relationship summaries
- care-gap indicators
- evidence asset metadata suitable for cited responses
- timeline-oriented event records where relevant

## Constraints

- The semantic view must inherit the constitution: synthetic-only, no unsupported prediction, no treatment recommendation.
- The semantic layer must not compensate for missing curated relationships by rebuilding raw joins ad hoc.

## Naming Governance

- Semantic artifacts must use `PATIENT360` as the canonical database identity.
- Legacy `CARE360_DB` naming must be treated as migration debt only.