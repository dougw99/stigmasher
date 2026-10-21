# Stigmasher — STIG Checklist Automation (ICM workspaces)

Each subfolder is a complete, self-contained ICM workspace for one STIG.
This root is a router only — it holds no pipeline logic.

## Workspaces

| Folder | STIG | Status |
|---|---|---|
| `cosmos-stig\` | Azure Cosmos DB (Database SRG V4R6, 142 rules) | production — see `cosmos-stig\AGENT.md` |
| `appservice-stig\` | Azure App Service (App Server SRG, 137 rules) | production — see `appservice-stig\AGENT.md` |

Per-workspace stage-01 collectors (the only differing command):

| Workspace | Stage-01 collector |
|---|---|
| `cosmos-stig\` | `.\scripts\collect_azure.ps1 -AccountName <account> -ResourceGroup <rg> [-Subscription <sub>]` |
| `appservice-stig\` | `.\scripts\collect_azure.ps1 -AppName <app> -ResourceGroup <rg> [-Subscription <sub>] [-Type webapp|functionapp]` |

## Routine

1. Re-read this file to see which workspaces exist and their status.
2. Open the chosen workspace folder and continue per its own
   `AGENT.md` → `CONTEXT.md` routing table.
3. Do NOT mix block-level artifacts between workspaces — each `output\`,
   `snapshot\`, and `_config\` belongs to exactly one STIG.

## Adding a new workspace

Clone a production one (e.g. `cosmos-stig\` or `appservice-stig\`) into
`<name>-stig\`, delete its run artifacts (`output\`, `snapshot\`, stage
`output\` subfolders), then replace its STIG-specific pieces: baseline `.cklb`
in `_config\`, the key-event/decision-table guide in `rules\rules.md`, and the
stage-01 collector. The stage contracts (`0N_*\CONTEXT.md`) and
`_config\conventions.md`/`glossary.md` are generic and can stay as-is.
