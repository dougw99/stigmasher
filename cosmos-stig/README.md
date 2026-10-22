# Cosmos DB STIG Checklist Automation (stigmasher)

AI-assisted, repeatable STIG compliance assessment for Azure Cosmos DB, based on the
Database SRG V4R6 (142 rules).

## Overview

This project turns a manual STIG checklist effort into a deterministic, 5-stage pipeline:

1. **Collect** evidence from Azure via the `az` CLI (no secrets) into a snapshot.
2. **Evaluate** the evidence — the AI reasons over the snapshot guided by
   `rules\rules.md` decision tables and `_config\overrides.md`.
3. **Review** — the human resolves the `needs_user` rules the evaluation deferred.
4. **Map** — evaluation + decisions merge into one machine-read mapping.
5. **Checklist** — a script applies the mapping to the STIG Viewer 3 baseline.

Everything is snapshot-driven: the JSON snapshot captured from Azure is the single
input for the evaluation, so the same evidence always yields the same statuses.

### What you get

| Output | Description |
|---|---|
| `output\<resource-name>_filled.cklb` | Checklist fillable in STIG Viewer 3 (BOM-less UTF-8) |
| `output\review_report.md` | Status summary + rules still `not_reviewed` |
| `output\azure_snapshot_<timestamp>.json` | The snapshot, archived after each assessment |

After a successful run the snapshot is **moved** out of `snapshot\` so a stale
capture can never be reused. Re-run the collector before the next assessment.

## Directory layout

| Path | Purpose |
|---|---|
| `CONTEXT.md` | Stage routing table — tells you which stage comes next |
| `01_collect\` … `05_checklist\` | One folder per stage, each with a `CONTEXT.md` task contract and an `output\` subfolder |
| `scripts\collect_azure.ps1` | az CLI evidence collector → snapshot |
| `scripts\compose_checklist.ps1` | Checklist composer: mapping + baseline → filled checklist + report |
| `rules\rules.md` | Key events + decision tables (the core evaluation logic) |
| `_config\Database Checklist.cklb` | Baseline unfilled STIG checklist. **Never modified.** |
| `_config\overrides.md` | Organization decisions that supersede the decision tables |
| `snapshot\azure_snapshot.json` | Evidence collected from Azure |
| `output\` | Final deliverables (filled checklists, report, archived snapshots) |

## Requirements

- Windows PowerShell 5.1
- [Azure CLI](https://aka.ms/azure-cli) (`az`) logged in (`az login`) and pointed
  at the subscription containing the Cosmos DB account
- A Cosmos DB account (SQL API)

## Quick start

Run the collector, then follow the pipeline stage by stage (each stage's
`CONTEXT.md` defines its inputs, outputs, and hand-off):

```powershell
# from the workspace root
.\scripts\collect_azure.ps1 -AccountName <cosmos-account> -ResourceGroup <rg> [-Subscription <sub>]
```

Stages 02–04 are performed by the AI agent per the stage `CONTEXT.md` files
(evaluation → review → mapping). Stage 05 produces the deliverables:

```powershell
.\scripts\compose_checklist.ps1
# options: -Checklist -Mapping -Snapshot -OutChecklist -Report -KeepSnapshot
```

Then open `output\<resource-name>_filled.cklb` in
[STIG Viewer 3](https://public.cyber.mil/stigs/stig-viewing-tools/) or review
`output\review_report.md`. Each assessment consumes exactly one fresh snapshot.

## Workflow with an AI agent (Claude Code, OpenCode, GitHub Copilot)

The pipeline is designed so an AI agent can drive every stage.

### Point the agent at the guide

Give the agent the workspace and tell it to read `AGENT.md` / `CLAUDE.md` (same
instructions, agent-specific filenames). Routing across stages goes through the
root `CONTEXT.md` table; each stage has its own `CONTEXT.md` contract. Useful prompts:

- "Read AGENT.md and CONTEXT.md, then run the assessment for account X /
  resource group Y." — the agent routes itself: collect → evaluate, and stops
  at stage 03 to ask you about ambiguous rules.
- "Resolve my stage 03 decisions, then continue to the final checklist."

### The review loop (human + AI)

Stage 02 hands rules it cannot decide to stage 03 as `needs_user` rows
(with the exact reason). Stage 03:

1. Batches the questions by cause, not rule-by-rule (e.g. "Keys are enabled;
   these 12 rules depend on per-user identity — OPEN, or enforce Entra
   ID-only first?").
2. Records each answer in `03_review\output\decisions.md` with your wording kept
   verbatim.
3. If your answer is an organization-level rule ("we always inherit X for
   PaaS"), the agent also appends it to `_config\overrides.md` so future
   assessments skip the question.

Stage 05 composes the checklist from the mapping; it never invents statuses.

### Evaluation model

There is no hardcoded evaluator. The stage-02 AI applies:

> Note: running this pipeline does **not** create any new PowerShell scripts.
> The only scripts are `scripts\collect_azure.ps1` and
> `scripts\compose_checklist.ps1`; every other stage is performed by the AI
> agent directly per its `CONTEXT.md`.

- Key events from the snapshot (e.g. `disableLocalAuth=true/false`) +
  decision tables in `rules\rules.md`.
- `_config\overrides.md` — organization decisions that always beat the tables.
- Evidence, not guesses: every proposed status cites the exact snapshot
  `path=value` or a `rules\rules.md` table row — never both, never neither.
- Rules that can't be evaluated confidently are deferred as `needs_user`
  (stage 02) and stay `not_reviewed` if the user can't decide (stage 03).

## Conventions preserved by the pipeline

- `_config\Database Checklist.cklb` is read-only input — deliverables always go
  to `output\`, stage artifacts to each stage's `output\` subfolder.
- Output JSON is BOM-less UTF-8 (STIG Viewer 3 rejects BOM'd files; the scripts
  use `[IO.File]::WriteAllText` with `UTF8Encoding($false)`).
- Scripts work from any working directory (paths resolve from `$PSScriptRoot`).
- Never fabricate settings absent from the snapshot — unknown rules stay
  `not_reviewed` rather than guessed.
