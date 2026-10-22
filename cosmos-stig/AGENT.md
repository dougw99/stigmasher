# STIG Checklist Automation — Cosmos DB (Database SRG V4R6)

AI-assisted, repeatable STIG compliance assessment of an Azure Cosmos DB account.
Pipeline: **collect evidence → AI evaluation → human review → map → compose checklist**.
Determinism is the goal: the same evidence always yields the same statuses.

## Directory layout

| Path | Purpose |
|---|---|
| `Context.md` | Stage routing table — start here, then read the stage's `CONTEXT.md` |
| `01_collect\` | Stage 01: run the az CLI collector, validate the snapshot |
| `02_evaluate\` | Stage 02: AI evaluates the snapshot → `evaluation.md` |
| `03_review\` | Stage 03: human decides the `needs_user` rows → `decisions.md` |
| `04_map\` | Stage 04: merge evaluation + decisions → `rules-mapping.json` |
| `05_checklist\` | Stage 05: compose deliverables via `scripts\compose_checklist.ps1` |
| `scripts/collect_azure.ps1` | az CLI evidence collector → snapshot |
| `scripts/compose_checklist.ps1` | Checklist composer: mapping + baseline → filled checklist + report |
| `rules/rules.md` | Key events + decision tables (the core evaluation logic) |
| `snapshot/azure_snapshot.json` | Evidence collected from Azure (az CLI, no secrets) |
| `_config/` | Baseline `Database Checklist.cklb` (never modified), schema, `conventions.md`, `glossary.md`, `overrides.md` |
| `output\` | Final deliverables: filled checklist, review report, archived snapshot |

Each stage folder contains a `CONTEXT.md` (its task contract) and an `output\`
subfolder with its stage artifact.

## Workflow

Start at `CONTEXT.md` (root) — its routing table tells you which stage is next
based on which artifacts exist on disk:

| Signal on disk | Stage | Per |
|---|---|---|
| no `snapshot\azure_snapshot.json` | 01 | `01_collect\CONTEXT.md` |
| snapshot exists, no `02_evaluate\output\evaluation.md` | 02 | `02_evaluate\CONTEXT.md` |
| evaluation has `needs_user` rows, no `03_review\output\decisions.md` | 03 | `03_review\CONTEXT.md` |
| decisions ready, no `04_map\output\rules-mapping.json` | 04 | `04_map\CONTEXT.md` |
| mapping ready, no fresh `output\*_filled.cklb` | 05 | `05_checklist\CONTEXT.md` |

Follow the stage's CONTEXT.md exactly: read only its listed context inputs,
write only its listed outputs, and end with its routing statement. Stages must
never be reordered, skipped, or stacked (e.g. no mapping while evaluation is
missing, no stage 02 on a snapshot stage 05 already archived).

Deliverables (written to `output\` by stage 05):
- `<resource-name>_filled.cklb` — fillable in STIG Viewer 3 (BOM-less UTF-8 JSON)
- `review_report.md` — status summary + rules still `not_reviewed`
- `azure_snapshot_<timestamp>.json` — the snapshot is **moved** out of
  `snapshot\` after a successful run so stale evidence cannot be reused.
  Re-run stage 01 with `collect_azure.ps1` before the next assessment;
  pass `-KeepSnapshot` to `compose_checklist.ps1` to disable archiving.

## Evaluation model

There is no hardcoded evaluator. Judgment lives in stage 02, performed by the
AI guided by `rules/rules.md` (key events + decision tables) and
`_config/overrides.md` (organization decisions that always beat the tables).

- Evidence, not guesses: every status cites the exact snapshot `path=value`.
- Statuses: `not_a_finding`, `open`, `not_applicable`, `needs_user` (stage 02),
  plus `not_reviewed` in the mapping when the user cannot decide (stage 03).
- Ambiguity is deferred to stage 03, never resolved by guessing.

## Human review loop

Stage 03 is the human gate. Questions are batched by cause, never rule-by-rule
(e.g. "Keys are enabled; these 12 rules depend on per-user identity — OPEN, or
enforce Entra ID-only first?"). Organization-level answers are recorded in
`_config/overrides.md` so future runs skip the question; per-rule decisions go
into `03_review\output\decisions.md` with the user's wording kept verbatim.

## Conventions to preserve

- **Never create new PowerShell scripts.** The only scripts in this workspace
  are the two in `scripts\` (`collect_azure.ps1`, `compose_checklist.ps1`).
  All stages 02–04 are AI-performed per their `CONTEXT.md` — do your work
  directly (reading evidence, writing markdown/JSON artifacts), not by
  generating helper `.ps1` files.
- `_config\Database Checklist.cklb` is read-only input; outputs always go to
  `output\` (stage artifacts go inside each stage's `output\` subfolder).
- Output JSON must be **BOM-less UTF-8** (PS 5.1 `Set-Content -Encoding UTF8`
  writes a BOM that STIG Viewer 3 rejects; use `[IO.File]::WriteAllText` with
  `UTF8Encoding($false)`).
- Scripts must work from any working directory (they resolve paths from `$PSScriptRoot`).
- Never fabricate a setting absent from the snapshot; treat as unknown/
  `not_reviewed`.
- Do NOT mix artifacts between workspaces: this workspace's `output\`,
  `snapshot\`, and `_config\` belong to this STIG only.
- On ambiguity not covered by the routing table, report the observed state and
  let the user pick — do not guess.
