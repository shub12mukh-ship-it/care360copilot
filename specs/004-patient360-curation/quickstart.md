# Quickstart Validation Guide: Patient360 Curation Logic

## Purpose

This guide describes how to validate that the curated `PATIENT360` layer is ready for the
future semantic-view and Streamlit experience.

## Prerequisites

- raw `PATIENT360` data exists and is queryable
- curated outputs have been created for the entities defined in `data-model.md`
- validation queries can inspect source traceability and patient-linked evidence relationships

## Validation Scenario 1: Unified patient record

1. Select a patient with multiple encounters.
2. Review the curated patient record.
3. Confirm it includes a coherent summary of visits, medications, labs, claims, and evidence assets.
4. Confirm source linkage exists for each major summary area.

## Validation Scenario 2: Persona support

Validate at least one representative question path for each persona:

- Clinical Care Coordinator: medication and recent-visit summary
- Quality & Compliance Analyst: evidence of monitoring and missing follow-up signals
- Population Health Manager: care-gap or utilization-oriented signals
- Clinical Pharmacist: medication review linked to labs and supporting evidence

Expected outcome: the curated layer supports these paths without reconstructing raw joins manually.

## Validation Scenario 3: Timeline coherence

1. Review a patient’s timeline events.
2. Confirm events are chronologically meaningful.
3. Confirm events include structured and evidence-linked domains where applicable.

## Validation Scenario 4: Report and imaging readiness

1. Select a patient with report or imaging-linked raw assets.
2. Confirm the curated layer links those assets to patient and encounter context.
3. Confirm the evidence asset metadata is sufficient for future analysis workflows.

## Validation Scenario 5: Semantic-view readiness

1. Review the curated entity set and relationships.
2. Confirm there are stable patient-centered and encounter-centered entities.
3. Confirm care-gap, medication, lab, and evidence relationships are explicit enough for semantic modeling.

## Validation Scenario 6: Governance and naming

1. Inspect newly created planning and design artifacts.
2. Confirm `PATIENT360` is used consistently.
3. Confirm no new `CARE360_DB` references were introduced.

## Expected Outcomes

- a patient-centered curated layer exists in design form
- persona-aligned query paths are supported
- source traceability is preserved
- report/image assets are linked for future analysis
- semantic-view planning can proceed without redefining core business entities
- no constitutional naming violations are introduced