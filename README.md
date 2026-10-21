# Stigmasher

AI-assisted, repeatable **STIG compliance assessment** — one self-contained
workspace per STIG target, orchestrated as an **ICM pipeline**
(Interpretable Context Methodology): numbered stage folders, markdown
contracts, one AI agent, plain-text handoffs. Determinism is the goal: the
same evidence always yields the same statuses.

## Workspaces

| Folder | STIG | Status |
|---|---|---|
| [`cosmos-stig\`](cosmos-stig) | Azure Cosmos DB (Database SRG V4R6, 142 rules) | Production |
| [`appservice-stig\`](appservice-stig) | Azure App Service (App Server SRG, 137 rules) | Production |

Both workspaces follow the identical 5-stage ICM pipeline below and never
share run artifacts (`output\`, `snapshot\`, `_config\` are private to each).

## How a workspace is structured

```
<stig-workspace>\
├── AGENT.md / CONTEXT.md        workspace map + stage routing (agent entry point)
├── _config\                     Layer 3 — persistent, STIG-specific
│   │     .cklb                  READ-ONLY baseline: unfilled STIG checklist
│   ├── conventions.md           hard rules: BOM-less UTF-8, paths, evidence integrity
│   ├── glossary.md              status vocabulary + checklist fields
│   └── overrides.md             organization decisions (supersede decision tables)
├── rules\rules.md               Layer 2 — key events + decision tables (the "engine")
├── 01_collect\  →  snapshot\azure_snapshot.json          collect evidence (script)
├── 02_evaluate\ →  output\evaluation.md                  AI judgment vs. decision tables
├── 03_review\   →  output\decisions.md                   user gate (batched questions)
├── 04_map\      →  output\rules-mapping.json             merged machine-readable mapping
├── 05_checklist\→  output\<resource>_filled.cklb                           + report
├── scripts\                     collect_azure.ps1 · compose_checklist.ps1 (mechanical only)
├── output\                      final deliverables (git-ignored)
└── snapshot\                    evidence from Azure, consumed once (git-ignored)
```

Each stage folder's `CONTEXT.md` is its **contract**: role, context to load,
input, output, and a "definition of done" routing statement. The AI agent is
the *evaluation engine* (stages 02–04); scripts do only mechanical work
(collect, format, stamp) — never judgment.

## Usage

### With an AI agent (OpenCode, Claude Code, Copilot agent mode)

Open the repo root; the agent auto-reads `AGENT.md`/`CLAUDE.md`, picks the
workspace, and walks the pipeline stage by stage:

- "Run the assessment pipeline for account X / resource group Y."
  (`cosmos-stig` targets a Cosmos DB account; `appservice-stig` targets an
  App Service web/function app.)
- "Continue the pipeline." (routing follows the workspace's `CONTEXT.md`)
- "Why is V-206553 open?" (explain from `02_evaluate\output\evaluation.md`)

User interaction is deliberately limited to **stage 03**, where ambiguous
rules are batched into few questions; decided answers are recorded verbatim
and reflected in the final checklist.

### Manual (PowerShell only)

Each workspace ships its own stage-01 collector; the other scripts are
stage-agnostic:

```powershell
# Cosmos DB (Database SRG)
cd cosmos-stig
.\scripts\collect_azure.ps1 -AccountName <account> -ResourceGroup <rg> [-Subscription <sub>]

# App Service (App Server SRG)
cd appservice-stig
.\scripts\collect_azure.ps1 -AppName <app> -ResourceGroup <rg> [-Subscription <sub>] [-Type webapp|functionapp]

# stages 02–04: follow each stage folder's CONTEXT.md contract by hand
.\scripts\compose_checklist.ps1 -Checklist "_config\<stig> Checklist.cklb"
```

Artifacts: `output\<resource>_filled.cklb` (open in
[STIG Viewer 3](https://public.cyber.mil/stigs/stig-viewing-tools/)) and
`output\review_report.md` (status summary + fix list of `open` items).

## Key behaviors worth knowing

- **One evidence capture per assessment** — stage 05 *moves* the snapshot to
  `output\` (timestamped) after success; re-run stage 01 before any re-run so
  stale evidence can never be reused.
- **Resource-stamped outputs** — the filled checklist is named after the
  assessed resource (e.g. `wtsdbstig_filled.cklb`) and its
  `target_data.host_name` is set to the resource name.
- **BOM-less UTF-8** — STIG Viewer 3 rejects BOM'd JSON; every writer uses
  `[IO.File]::WriteAllText(...) UTF8Encoding($false)`.
- **Overrides win** — organization-level answers recorded in
  `_config\overrides.md` supersede decision tables on future runs.
- **No fabricated evidence** — a setting absent from the snapshot means
  `not_reviewed`, with the gap named.

## Adding a new STIG workspace

1. Clone a production workspace folder into `<name>-stig\`.
2. Delete run artifacts (`output\`, `snapshot\`, stage `output\` subfolders).
3. Replace the STIG-specific pieces (see `cosmos-stig\` and
   `appservice-stig\` for two completed examples):
   - `_config\<stig> Checklist.cklb` — unfilled baseline (read-only)
   - `rules\rules.md` — key events + decision tables distilled from the
     checklist's `check_content`
   - `scripts\collect_azure.ps1` — az CLI evidence collection mapped to those
     key events
4. Register the workspace in the root `AGENT.md` table.

Stage contracts (`0N_*\CONTEXT.md`), `conventions.md`, and `glossary.md` are
STIG-agnostic and stay as-is.

## Environment

- Windows PowerShell 5.1 (scripts resolve all paths from `$PSScriptRoot`)
- [Azure CLI](https://aka.ms/azure-cli) (`az`) logged in, pointed at the
  subscription containing the target resource
- A target resource matching the workspace's STIG (e.g. SQL API Cosmos DB
  account for `cosmos-stig`, web/function app for `appservice-stig`)
