# STIG Checklist Automation — Cosmos DB (Database SRG V4R6)

AI-assisted, repeatable STIG compliance assessment of an Azure Cosmos DB account.
Pipeline: **collect evidence → deterministic evaluation → human review**.
Determinism is the goal: the same evidence always yields the same statuses.

## Directory layout

| Path | Purpose |
|---|---|
| `Database Checklist.cklb` | Source unfilled STIG checklist (Database SRG V4R6, 142 rules). **Never modified.** |
| `SV3_CKLB_1_0_JSON_SCHEMA.json` | STIG Viewer 3 checklist JSON schema |
| `scripts/collect_azure.ps1` | az CLI evidence collector → snapshot |
| `scripts/run.ps1` | Evaluator: snapshot + map → filled checklist + review report |
| `rules/rules-map.json` | Deterministic rule → check mappings |
| `rules/rules.md` | Human notes on overrides applied to the map (keep in sync with the map) |
| `snapshot/azure_snapshot.json` | Evidence collected from Azure (az CLI, no secrets) |
| `output/` | **All outputs land here**: filled checklists and reports |

## Workflow (run every assessment)

```powershell
# from the repo root
.\scripts\collect_azure.ps1 -AccountName <cosmos-account> -ResourceGroup <rg> [-Subscription <sub>]
.\scripts\run.ps1
```

Each run consumes the snapshot once: after evaluation the snapshot is archived to
`output\` (timestamped), so an assessment is always backed by exactly one
evidence capture — no repeat runs share stale evidence.

Outputs (defaults, written to `output\`):
- `<ChecklistName>_filled.cklb` — fillable in STIG Viewer 3 (BOM-less UTF-8 JSON)
- `review_report.md` — status summary + rules needing human/AI review
- `azure_snapshot_<timestamp>.json` — the snapshot is **moved** out of `snapshot\`
  after a successful run so stale evidence cannot be reused. Re-collect with
  `collect_azure.ps1` before the next `run.ps1`. Use `-KeepSnapshot` on
  `scripts\run.ps1` to disable archiving.

Optional parameters exist on both scripts (see their param blocks) to target
other checklists/snapshots/output names; defaults are repo-relative.

## Evaluation model

- Rules are mapped in `rules/rules-map.json` with `kind`:
  - `static` — fixed status + reviewable comment (overrides, PaaS architecture rules)
  - `local_auth` / `key_auth_dependent` — NAF/N-A when `disableLocalAuth=true`, open when keys are enabled
  - `public_access` / `tls_version` / `encryption_at_rest` / `key_storage` — account-level evidence checks
  - `audit_generated` / `audit_support` / `diagnostics_to_la` / `diag_dependent` / `no_databases` / `access_control` — snapshot-driven checks
- Evidence, not guesses: every status message includes the exact snapshot path/value.
- Uncertain rules stay `not_reviewed` for a human decision.

## Human review loop

1. Read `output\review_report.md` — status summary + per-rule guidance.
2. Give decisions for each `not_reviewed` rule (NAF / N-A / Open + reasoning,
   e.g. "Inherited by the Cloud Service Provider" or "Govcloud CA accepted").
3. Encode the decision:
   - `static` status → add to `rules/rules-map.json` and note it in `rules/rules.md`.
   - Conditional behavior → add/extend a `kind` in `scripts/run.ps1`.
4. Re-run `scripts\run.ps1`; the decision is now repeatable.

## Conventions to preserve

- `Database Checklist.cklb` is read-only input; outputs always go to `output\`.
- Output JSON must be **BOM-less UTF-8** (PS 5.1 `Set-Content -Encoding UTF8`
  writes a BOM that STIG Viewer 3 rejects; use `[IO.File]::WriteAllText` with
  `UTF8Encoding($false)`).
- Scripts must work from any working directory (they resolve paths from `$PSScriptRoot`).
- Never fabricate a setting absent from the snapshot; treat as unknown/`not_reviewed`.
