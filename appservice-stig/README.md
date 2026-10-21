# Azure App Service STIG Checklist Automation (stigmasher)

AI-assisted, repeatable STIG compliance assessment for Azure App Service
(web/function apps), based on the **Application Server SRG** (137 rules),
structured as an ICM pipeline.

## Overview

The pipeline assesses one app per run, always the same way:

1. **Collect** evidence from Azure via the `az` CLI (secret-free)
   → `snapshot\azure_snapshot.json`.
2. **Evaluate** the snapshot against `rules\rules.md` (8 key events +
   decision tables distilled from the checklist's `check_content`)
   → stage 02 first-pass statuses.
3. **Review** — the human gate (stage 03) resolves the org/tenant rules in
   batched questions; decisions are recorded verbatim in `03_review\output`
   and organization-level ones in `_config\overrides.md`.
4. **Map** (stage 04) merges evaluations + decisions into one machine-readable
   `rules-mapping.json`; **Compose** (stage 05) applies it to the baseline
   checklist.

Determinism is the goal: the same evidence + decisions always yield the same
statuses.

### Stage walkthrough

| Stage | Folder | Reads | Writes |
|---|---|---|---|
| 01 collect | `01_collect\` (script) | live Azure subscription | `snapshot\azure_snapshot.json` |
| 02 evaluate | `02_evaluate\` (AI) | snapshot, `rules\rules.md`, `_config\overrides.md` | `02_evaluate\output\evaluation.md` |
| 03 review | `03_review\` (user gate) | evaluation.md | `03_review\output\decisions.md` + `_config\overrides.md` |
| 04 map | `04_map\` (merge) | evaluation.md + decisions.md | `04_map\output\rules-mapping.json` |
| 05 checklist | `05_checklist\` (script) | mapping + baseline checklist | `output\<app>_filled.cklb`, `output\review_report.md` |

### What you get after a run

| Output | Description |
|---|---|
| `output\<app>_filled.cklb` | Checklist fillable in STIG Viewer 3 (BOM-less UTF-8), `host_name` stamped with the app name |
| `output\review_report.md` | Status summary + fix list of `open` items |
| `output\azure_snapshot_<timestamp>.json` | The snapshot, archived after each run |

After a successful stage-05 run the snapshot is **moved** out of `snapshot\`
so stale evidence can never be reused; re-run `collect_azure.ps1` before any
further run.

## Directory layout

| Path | Purpose |
|---|---|
| `_config\App Server.cklb` | Unfilled baseline checklist (Application Server SRG). **Never modified.** |
| `_config\conventions.md` / `glossary.md` | Hard rules (BOM-less UTF-8, paths) and the legal status vocabulary |
| `_config\overrides.md` | Organization-level decisions (supersede the decision tables) |
| `rules\rules.md` | Evaluation guide: 8 key events + decision tables covering all 137 rules |
| `scripts\collect_azure.ps1` | az CLI evidence collector → snapshot |
| `scripts\compose_checklist.ps1` | Applies `rules-mapping.json` to the baseline; no judgment |
| `snapshot\azure_snapshot.json` | Evidence collected from Azure (consumed once) |
| `output\` | Final deliverables |

Stage contracts live in each `01_collect`–`05_checklist` folder's `CONTEXT.md`.

## Requirements

- Windows PowerShell 5.1
- [Azure CLI](https://aka.ms/azure-cli) (`az`) logged in (`az login`) and pointed
  at the subscription containing the app
- A web app (`-Type webapp`) or function app (`-Type functionapp`)

## Quick start

```powershell
.\scripts\collect_azure.ps1 -AppName <webapp> -ResourceGroup <rg> [-Subscription <sub>]
# stages 02–04: follow each stage folder's CONTEXT.md (the AI agent owns these)
.\scripts\compose_checklist.ps1 -Checklist "_config\App Server.cklb"
```

Then:

1. Open the filled checklist (`output\<app>_filled.cklb`) in
   [STIG Viewer 3](https://public.cyber.mil/stigs/stig-viewing-tools/), or read
   `output\review_report.md` (open items are your fix list).
2. For `not_reviewed` rules, the named gap in the comment tells you what
   evidence or decision is missing.
3. Repeat per assessment — each run consumes exactly one fresh snapshot.

## Workflow with an AI agent (OpenCode, Claude Code, Copilot agent mode)

Point the agent at the workspace folder — it reads `AGENT.md`/`CLAUDE.md`
automatically and routes through stages 01–05 per each `CONTEXT.md` contract.

Useful prompts:

- "Run the assessment for app X / resource group Y."
- "Continue the pipeline."
- "Why is V-204717 open?" (answer from `02_evaluate\output\evaluation.md`)

User interaction is deliberately limited to **stage 03**; org-level answers
are recorded in `_config\overrides.md`, so future runs skip repeated
questions.

## Key events (what the evaluation reduces to)

| # | Key event | Snapshot evidence |
|---|---|---|
| K1 | Inbound locked to approved TLS | `httpsOnly`, `minTlsVersion`, `scmMinTlsVersion` |
| K2 | FTP locked | `ftpsState` |
| K3 | Dev endpoints closed | `remoteDebuggingEnabled` |
| K4 | Audit pipeline to central logs | `diagnostic_settings[]` categories + `workspaceId` |
| K5 | Network exposure restricted | IP restrictions / VNet integration / public access |
| K6 | No app-managed credentials | managed identity / EasyAuth |
| K7 | File + IP-limited audit on | `AppServiceFileAuditLogs`, `AppServiceIPSecAuditLogs` |
| K8 | Managed platform facts | static `platform_facts` block emitted by the collector |

Full decision tables are in `rules\rules.md`.

## Conventions preserved by the pipeline

- `_config\App Server.cklb` is read-only input — outputs always go to `output\`.
- Output JSON is BOM-less UTF-8 (STIG Viewer 3 rejects BOM'd files; the
  scripts use `[IO.File]::WriteAllText` with `UTF8Encoding($false)`).
- Scripts work from any working directory (paths resolve from `$PSScriptRoot`).
- Never fabricate settings absent from the snapshot — unknown rules stay
  `not_reviewed` with the gap named.
- No stage crosses workspace boundaries: `snapshot\`, `output\`, `_config\`
  belong to this STIG only (see the root `README.md` for the sibling
  `cosmos-stig\` workspace).
