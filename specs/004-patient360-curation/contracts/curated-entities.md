# Contract: Curated Entities

## Purpose

This contract defines what downstream consumers can rely on from the `PATIENT360` curated layer.

## Guaranteed Behaviors

- Curated outputs are patient-centered rather than raw-table-centered.
- Each curated output preserves source traceability.
- Encounter, medication, lab, claim, note, and imaging/report relationships are explicit.
- Missing data is represented transparently rather than filled with inferred clinical conclusions.

## Contracted Entity Set

- Curated Patient Record
- Encounter Summary
- Medication Evidence Summary
- Lab Monitoring Summary
- Care Gap Signal
- Evidence Asset
- Patient Timeline Event

## Provenance Expectations

- Each entity must expose enough source linkage to identify where the business fact came from.
- Downstream consumers must be able to trace a patient-level summary back to encounter-level or evidence-level origins.

## Scope Rules

- This layer is synthetic-data only.
- This layer must not create diagnosis or treatment recommendations.
- This layer must use `PATIENT360` naming and must not introduce `CARE360_DB` into new artifacts.