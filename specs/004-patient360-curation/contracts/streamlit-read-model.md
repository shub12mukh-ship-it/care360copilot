# Contract: Streamlit Read Model

## Purpose

This contract defines the expectations the future Streamlit app can place on the curated layer.

## Required Read Patterns

- patient selector support with patient summary context
- recent-visit and timeline review
- current and historical medication review
- lab monitoring evidence review
- care-gap visibility
- citation-ready evidence asset access
- report and imaging-linked evidence context for later analysis flows

## UX-Oriented Guarantees

- The read model must support persona questions without forcing the UI to manually reassemble raw joins.
- The read model must preserve enough evidence context for citation panels and source drill-down.
- The read model must support future semantic-view-backed query patterns.

## Explicit Non-Goals

- The read model does not authorize diagnosis generation.
- The read model does not authorize treatment recommendation.
- The read model does not assume real PHI.