# appservice-stig — STIG Checklist Automation (ICM workspace)

AI-assisted, repeatable STIG compliance assessment of Azure App Service
resources, structured as an ICM pipeline: numbered stage folders, markdown
contracts, one agent, plain-text handoffs. Determinism is the goal — the same
evidence always yields the same statuses.

## Workspace map

```
AGENT.md / CONTEXT.md      ← you are here (routing only, never stage work)
_config/                   Layer 3 — persistent rules
  conventions.md             hard project rules (encoding, paths, evidence)
  glossary.md                status vocabulary + checklist fields
  overrides.md               organization decisions (user-owned)
  (TODO: baseline .cklb)     unfilled App Service STIG checklist — READ-ONLY
rules/rules.md             Layer 2 — evaluation knowledge (TODO: build)
  key events + decision tables; superseded by _config/overrides.md
01_collect/  → snapshot\azure_snapshot.json           (script TODO)
02_evaluate/ → output\evaluation.md                   (AI judgment against tables)
03_review/   → output\decisions.md                    (user gate; batches questions)
04_map/      → output\rules-mapping.json              (merge bookkeeping)
05_checklist/→ output\<resource>_filled.cklb + review_report.md (script-driven)
scripts/     collect_azure.ps1 (TODO) · compose_checklist.ps1 (generic, ready)
output/                    final deliverables only
```

## Pipeline flow

1. Start at `01_collect\CONTEXT.md`. Do its task; route to the next stage by
   its "definition of done" statement.
2. Never skip stages or run them out of order. Each stage's CONTRACT (input /
   output / rules of engagement) is in its `CONTEXT.md`.
3. If a stage output is missing or malformed, stop and report — never
   backfill decisions into an earlier stage's artifact.

## Ask vs. decide

The only stage allowed to consult the user is `03_review`. Stages 02 and 04
express uncertainty as rows/questions, not as user prompts. If the user is
asked outside stage 03, the contract was violated.

## Conventions that always apply

- The baseline `.cklb` in `_config\` is never modified.
- All output is BOM-less UTF-8 (see `_config\conventions.md`).
- Never fabricate evidence; missing setting = `not_reviewed` + the gap named.
- Scripts work from any CWD (paths resolve from `$PSScriptRoot`).

## Scaffold status (before first real use)

1. Put the unfilled App Service STIG checklist into `_config\` (read-only).
2. Distill `rules\rules.md`: key events from the checklist's check_content,
   then decision tables per evidence area (pattern: cosmos-stig\rules\rules.md).
3. Implement `scripts\collect_azure.ps1` evidence collection for those key events.
