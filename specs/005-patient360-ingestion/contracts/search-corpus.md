# Contract: Search Corpus

## Purpose

Define the search-ready contract for chunked ingestion outputs that support future evidence
retrieval and citation.

## Search Chunk Contract

Each chunk row MUST provide the following logical fields:

- chunk identifier
- ingestion asset identifier
- extraction record identifier
- chunk order
- chunk text
- patient identifier when available
- document category
- source date when known
- source stage name
- canonical stage path
- chunk eligibility status

## Ordering Rules

- `chunk order` MUST preserve the original document sequence.
- Chunks from the same source asset MUST be reconstructable into document order without guessing.

## Eligibility Rules

- Only assets with usable extracted text may produce index-eligible chunks.
- Metadata-only assets MUST NOT emit searchable chunks.
- Failed or ambiguous extraction outcomes MUST leave the asset visible in the inventory without creating misleading search chunks.

## Traceability Rules

- Every chunk MUST trace to one extraction record and one canonical asset.
- Every chunk MUST retain enough metadata to support patient, document-category, and source-asset filtering.
- A reviewer MUST be able to move from chunk to extracted text to canonical stage path without consulting external notes.

## Downstream Readiness Rule

- The search corpus is considered ready only when chunk rows preserve provenance, sequence, and filtering metadata required for evidence-cited retrieval.