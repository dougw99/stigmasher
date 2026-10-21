# Cosmos DB STIG Checklist Automation (stigmasher)

AI-assisted, repeatable STIG compliance assessment for Azure Cosmos DB, based on the
Database SRG V4R6 (142 rules).

## Overview

This project turns a manual STIG checklist effort into a deterministic pipeline:

1. **Collect** evidence from Azure via the `az` CLI (no secrets).
2. **Evaluate** the evidence with a fixed, deterministic rules map.
3. **Review** — open the report, resolve any `not_reviewed` items, and encode
   those decisions back into the rules map so the next run is repeatable.

Everything is snapshot-driven: the JSON snapshot captured from Azure is the single
input for the evaluation, so the same evidence always yields the same statuses.

### What you get

| Output | Description |
|---|---|
| `output\<ChecklistName>_filled.cklb` | Checklist fillable in STIG Viewer 3 (BOM-less UTF-8) |
| `output\review_report.md` | Status summary + rules needing human/AI review |
| `output\azure_snapshot_<timestamp>.json` | The snapshot, archived after each run |

After a successful run the snapshot is **moved** out of `snapshot\` so a stale
capture can never be reused. Re-run `collect_azure.ps1` before the next run.

## Directory layout

| Path | Purpose |
|---|---|
| `Database Checklist.cklb` | Source unfilled STIG checklist (Database SRG V4R6). **Never modified.** |
| `SV3_CKLB_1_0_JSON_SCHEMA.json` | STIG Viewer 3 checklist JSON schema |
| `scripts\collect_azure.ps1` | az CLI evidence collector → snapshot |
| `scripts\run.ps1` | Evaluator: snapshot + rules map → filled checklist + review report |
| `rules\rules-map.json` | Deterministic rule → check mappings |
| `rules\rules.md` | Human notes on overrides (keep in sync with the map) |
| `snapshot\azure_snapshot.json` | Evidence collected from Azure |
| `output\` | All outputs (filled checklists and reports) |

## Requirements

- Windows PowerShell 5.1
- [Azure CLI](https://aka.ms/azure-cli) (`az`) logged in (`az login`) and pointed
  at the subscription containing the Cosmos DB account
- A Cosmos DB account (SQL API)

## Quick start

```powershell
# from the repo root
.\scripts\collect_azure.ps1 -AccountName <cosmos-account> -ResourceGroup <rg> [-Subscription <sub>]
.\scripts\run.ps1
```

Then:

1. Open the filled checklist (`output\Database Checklist_filled.cklb`) in
   [STIG Viewer 3](https://public.cyber.mil/stigs/stig-viewing-tools/) or review
   `output\review_report.md`.
2. Resolve any `not_reviewed` rules (see below).
3. Repeat per assessment — each run consumes exactly one fresh snapshot.

## Workflow with an AI agent (Claude Code, OpenCode, GitHub Copilot)

The pipeline is designed so an AI agent can own both maintenance and review:

### Point the agent at the guide

Give the agent the repo and tell it to read `AGENTS.md` / `CLAUDE.md` (same
instructions, agent-specific filenames). It describes the layout, workflow,
evaluation model, and conventions the agent must preserve. Example prompts:

- Claude Code: just open the repo — it picks up `CLAUDE.md` automatically.
- OpenCode: just open the repo — it reads `AGENT.md`/`AGENTS.md` automatically.
- GitHub Copilot Chat (agent mode): open the workspace and mention `AGENT.md`.

Useful prompts:

- "Read AGENT.md, then run the assessment for account X / resource group Y."
- "Read output\review_report.md and propose evidence-based statuses for the
  not_reviewed rules using snapshot\azure_snapshot.json."
- "Encode my decision for V-206559 (N-A, inherited by CSP) into rules-map.json
  and rules.md, then re-run."

### The review loop (human + AI)

`scripts\run.ps1` leaves rules it cannot evidence confidently as `not_reviewed`:

1. Agent reads `output\review_report.md` and proposes evidence-based statuses
   (NAF / N-A / Open) for each `not_reviewed` rule — e.g. "Inherited by the
   Cloud Service Provider" for platform-managed behavior, or an evidence check
   against the snapshot.
2. Human approves or edits the proposals.
3. Agent encodes each decision:
   - Fixed status → `static` entry + status in `rules\rules-map.json`, noted in
     `rules\rules.md`.
   - Conditional behavior → extend/add a `kind` in `scripts\run.ps1`.
4. Re-run `scripts\run.ps1` — the decision is now repeatable and deterministic.

### Evaluation model

Rules in `rules\rules-map.json` carry a `kind` that drives the check:

- `static` — fixed status + comment (overrides, PaaS architecture rules)
- `local_auth` / `key_auth_dependent` — keyed on `disableLocalAuth`
- `public_access` / `tls_version` / `encryption_at_rest` / `key_storage` —
  account-level evidence checks
- `audit_generated` / `audit_support` / `diagnostics_to_la` / `diag_dependent` /
  `no_databases` / `access_control` — snapshot-driven checks

Every status message cites the exact snapshot path/value used as evidence.
Rules that can't be evaluated confidently stay `not_reviewed` for a human.

## Conventions preserved by the pipeline

- `Database Checklist.cklb` is read-only input — outputs always go to `output\`.
- Output JSON is BOM-less UTF-8 (STIG Viewer 3 rejects BOM'd files; the scripts
  use `[IO.File]::WriteAllText` with `UTF8Encoding($false)`).
- Scripts work from any working directory (paths resolve from `$PSScriptRoot`).
- Never fabricate settings absent from the snapshot — unknown rules stay
  `not_reviewed` rather than guessed.
