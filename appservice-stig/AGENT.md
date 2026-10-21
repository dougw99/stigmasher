# appservice-stig — STIG Checklist Automation (ICM workspace)

AI-assisted, repeatable STIG compliance assessment of Azure App Service
resources, structured as an ICM pipeline: numbered stage folders, markdown
contracts, one agent, plain-text handoffs. Determinism is the goal — the same
evidence always yields the same statuses.

## Directory layout

| Path | Purpose |
|---|---|
| `AGENT.md` / `CONTEXT.md` | Workspace routing (you are here — routing only, never stage work) |
| `App Server.cklb` | Unfilled source STIG checklist (Application Server SRG, 137 rules). **Never modified.** |
| `SV3_CKLB_1_0_JSON_SCHEMA.json` | STIG Viewer 3 checklist JSON schema |
| `_config/` | Layer 3 — persistent rules (conventions.md, glossary.md, overrides.md, baseline `.cklb`) |
| `rules/rules.md` | Layer 2 — evaluation knowledge: key events + decision tables; superseded by `_config/overrides.md` |
| `scripts/collect_azure.ps1` | az CLI evidence collector → snapshot |
| `scripts/compose_checklist.ps1` | Applies `rules-mapping.json` to the baseline; no judgment |
| `01_collect/` | Stage contract: snapshot\azure_snapshot.json |
| `02_evaluate/` | Stage contract: output\evaluation.md (AI judgment against tables) |
| `03_review/` | Stage contract: output\decisions.md (user gate; batches questions) |
| `04_map/` | Stage contract: output\rules-mapping.json (merge bookkeeping) |
| `05_checklist/` | Stage contract: output\<resource>_filled.cklb + review_report.md |
| `snapshot/azure_snapshot.json` | Evidence collected from Azure (az CLI, no secrets) |
| `output/` | **All outputs land here**: filled checklists and reports |

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

## Run history

- 2026-10-21: first end-to-end run exercised stages 01–05 against the real
  app `wtsapp` (Free tier, Linux container). Deliverables in `output\`
  (`wtsapp_filled.cklb`, `review_report.md`; 95 NAF / 2 N-A / 35
  not_reviewed / 5 open). Org-level stage-03 answers recorded in
  `_config\overrides.md`; they replay automatically on future runs.
- Stage-05 learnings: the collector now also captures `httpsOnly` from the
  site object (Linux apps keep it out of config-show).

## Next run

Start at `01_collect\CONTEXT.md` as usual — stages 02–05 need no scaffold
work. Expect stage 03 to re-ask only what is not yet in
`_config\overrides.md` (e.g. app-level session/auth design values).
