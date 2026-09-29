# Contract: Ingestion Entities

## Purpose

Define the stable query-facing contract for canonical ingestion inventory and extracted-text
outputs produced by the PATIENT360 ingestion layer.

## Canonical Asset Inventory Contract

Each canonical asset row MUST provide the following logical fields:

- ingestion asset identifier
- source stage name
- canonical stage path
- original file name
- asset family
- document category
- patient identifier when matched
- visit identifier when matched
- report identifier when matched
- match status
- processing status
- extraction mode classification
- discovery timestamp
- latest processing timestamp

## Required Semantic Guarantees

- One row represents one eligible staged asset in the canonical inventory.
- `canonical stage path` MUST preserve a direct path back to the originating RAW stage.
- Match fields MAY be null only when the asset is still unmatched or cannot be matched confidently.
- Processing status MUST distinguish successful, pending, metadata-only, duplicate-suspect, broken, unmatched, and unparseable states.

## Extracted Text Contract

Each extracted-text row MUST provide:

- extraction record identifier
- ingestion asset identifier
- extraction mode
- extraction outcome status
- extracted text body when successful
- failure reason when unsuccessful
- text length or completeness indicator
- provenance back to the canonical asset row

## Nullability Rules

- `extracted text body` MAY be null only when extraction fails or the asset is intentionally metadata-only.
- `failure reason` MUST be populated when extraction outcome is unsuccessful.
- patient or report linkage fields MAY remain null only when the asset is explicitly marked unmatched or ambiguous.

## Consumer Expectations

- Downstream consumers can read canonical inventory without stage-specific branching.
- Consumers can determine whether an asset is searchable, metadata-only, or remediable from status fields alone.
- Consumers can trace any extraction record directly back to the source asset and RAW-stage path.