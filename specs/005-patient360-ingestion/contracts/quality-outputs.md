# Contract: Quality Outputs

## Purpose

Define the ingestion-quality review contract that surfaces defects before curation or analytics
consume the document corpus.

## Mandatory Issue Categories

Quality outputs MUST cover at least these categories:

- missing files
- broken stage references
- duplicate assets
- unparseable assets
- unmatched report or image assets

## Required Fields Per Finding

Each quality finding MUST provide:

- quality finding identifier
- affected ingestion asset identifier or issue grouping key
- issue category
- severity or review priority
- issue description
- remediation hint
- first-detected timestamp
- current review status

## Grouping Rules

- Duplicate issues MAY be grouped when multiple rows refer to the same logical duplication set.
- Broken-reference and missing-file findings MUST identify the missing or inaccessible stage path clearly enough for remediation.
- Unmatched findings MUST explain that no confident patient/report assignment was made.

## Deduplication Expectations

- Repeated discovery of the same unresolved issue SHOULD not create indistinguishable duplicate findings.
- Findings must remain stable enough for a reviewer to track whether an issue is new, ongoing, or resolved.

## Readiness Rule For Curation Review

- Curation can proceed only with awareness of all open findings; unresolved findings must remain visible rather than being silently excluded from review.
- Quality outputs are successful when each defect category is reviewable and traceable back to the impacted asset or issue group.