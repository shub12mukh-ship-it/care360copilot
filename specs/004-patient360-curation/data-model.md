# Data Model: Patient360 Curation Logic

## Overview

This document defines the curated business entities for the `PATIENT360` curation layer.
These entities translate raw healthcare records into patient-centered, persona-aligned,
traceable structures suitable for future semantic-view and Streamlit consumption.

## Entity 1: Curated Patient Record

**Purpose**: Present a canonical, longitudinal patient-centered record that unifies the most
important demographic, utilization, care-gap, evidence, and recent-activity context.

**Key fields**:
- patient identifier
- patient demographic summary
- active-care context
- recent visit summary
- active medication summary
- lab monitoring summary
- claim/utilization summary
- evidence coverage indicators
- source provenance fields

**Relationships**:
- one patient to many encounters
- one patient to many medications
- one patient to many labs
- one patient to many claims
- one patient to many evidence assets
- one patient to many timeline events

**Validation rules**:
- patient identifier must map to a valid raw patient
- all derived summaries must preserve source references
- missing domains must be represented transparently, not fabricated

## Entity 2: Encounter Summary

**Purpose**: Represent a clinically meaningful visit or encounter with linked diagnoses,
tests, medications, claims, notes, and report/imaging context.

**Key fields**:
- encounter identifier
- patient identifier
- encounter type and date/time
- encounter reason/chief complaint summary
- linked diagnosis summary
- linked medication actions
- linked labs and results summary
- linked claims/procedures summary
- linked note/report/image evidence
- encounter provenance fields

**Relationships**:
- many encounters belong to one patient
- one encounter may link to many labs, medications, claims, notes, and evidence assets

**Validation rules**:
- encounter must map to a valid patient
- all linked child records must retain raw source references
- event ordering must remain temporally coherent

## Entity 3: Medication Evidence Summary

**Purpose**: Provide a medication-centered view for active, historical, and changed medications,
including the encounter and evidence context needed for clinical review.

**Key fields**:
- medication identifier or canonical medication key
- patient identifier
- encounter linkage
- medication name / class / dosage / route / frequency
- active or inactive status
- start and end/change context
- associated lab or note evidence
- provenance fields

**Relationships**:
- many medication summaries belong to one patient
- medication summaries may connect to one or many encounter summaries
- medication summaries may connect to labs and evidence assets

**Validation rules**:
- medication status must remain consistent with raw source state where available
- medication history must preserve ordering and change context

## Entity 4: Lab Monitoring Summary

**Purpose**: Surface current and historical lab evidence with monitoring context that supports
care coordination, compliance review, and medication safety workflows.

**Key fields**:
- patient identifier
- encounter linkage
- lab test identity and category
- result value and units
- reference range / abnormal status
- result date and recency
- monitoring summary indicators
- provenance fields

**Relationships**:
- many labs belong to one patient
- many labs may be associated with one encounter
- labs may contribute to care-gap signals and medication evidence

**Validation rules**:
- result dates must remain chronologically valid
- abnormal flags and value context must not be lost in summarization

## Entity 5: Care Gap Signal

**Purpose**: Highlight missing evidence, overdue monitoring, or utilization patterns relevant
to compliance, care coordination, and population-health use cases.

**Key fields**:
- patient identifier
- care gap category
- triggering evidence or missing evidence context
- gap status / severity / priority
- related encounter or monitoring window
- provenance fields

**Relationships**:
- many care-gap signals may belong to one patient
- care-gap signals may depend on labs, visits, medications, or claims histories

**Validation rules**:
- each signal must be explainable from raw or curated evidence
- no signal may exist without a traceable basis

## Entity 6: Evidence Asset

**Purpose**: Normalize document, report, and imaging-linked assets into patient-centered evidence
objects that can be cited now and analyzed later.

**Key fields**:
- evidence asset identifier
- patient identifier
- encounter identifier if applicable
- asset type (note, report, lab document, prescription, imaging-related report, image-linked record)
- source filename or document identity
- source date / event date
- evidence summary metadata
- provenance and storage linkage

**Relationships**:
- many evidence assets belong to one patient
- evidence assets may link to encounters, medications, labs, claims, or care-gap signals

**Validation rules**:
- every evidence asset must preserve source linkage
- imaging/report assets must remain connected to patient and encounter context even when full image analysis is deferred

## Entity 7: Patient Timeline Event

**Purpose**: Provide a normalized chronological representation of clinically and operationally
important events across structured and evidence-linked domains.

**Key fields**:
- patient identifier
- event identifier
- event type
- event timestamp/date
- event summary
- linked encounter/evidence context
- provenance fields

**Relationships**:
- many timeline events belong to one patient
- events may derive from encounters, labs, medications, claims, notes, or reports

**Validation rules**:
- events must sort in clinically meaningful chronological order
- event summaries must preserve the underlying source category and linkage

## CURATED vs ANALYTICS Boundary

### CURATED
- canonical patient-centered business entities
- stable encounter, medication, lab, and evidence relationships
- traceable source-aligned summaries
- reusable semantic-view candidate entities

### ANALYTICS
- broader cohort metrics
- dashboard-specific aggregations
- cross-patient derived measures
- operational summaries built on curated entities

## Semantic View Readiness Rules

- entity names must reflect business meaning, not raw ingestion mechanics
- relationship paths must be explicit and stable
- provenance must remain queryable
- curated entities must remain patient-centered and evidence-compatible
- future Streamlit consumers must be able to use these entities without re-deriving raw logic