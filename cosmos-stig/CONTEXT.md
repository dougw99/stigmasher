# Workspace routing

## The one question
"Where in the pipeline is this project right now?" — answer it, then route.

## Routing table

| Signal on disk | Stage | Action |
|---|---|---|
| no `snapshot\azure_snapshot.json` | 01 | run collector per `01_collect\CONTEXT.md` |
| snapshot exists, no `02_evaluate\output\evaluation.md` | 02 | evaluate per `02_evaluate\CONTEXT.md` |
| evaluation has `needs_user` rows, no `03_review\output\decisions.md` | 03 | ask user per `03_review\CONTEXT.md` |
| decisions ready, no `04_map\output\rules-mapping.json` | 04 | build mapping per `04_map\CONTEXT.md` |
| mapping ready, no fresh `output\*_filled.cklb` | 05 | run `scripts\compose_checklist.ps1` |

## Never routes
- Stages out of order, or skip stacks (e.g., mapping while evaluation is missing).
- Stage 02 using a snapshot that stage 05 already archived (timestamps prove
  freshness; when in doubt, re-run stage 01).

## On ambiguity
Any signal not covered above (stale/mixed artifacts, partial re-runs):
report the observed state and let the user pick, rather than guessing.
