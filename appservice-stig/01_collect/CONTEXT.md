# Stage 01 — Collect

## Purpose
Collect Azure App Service configuration evidence into a snapshot JSON.
This stage is mechanical: a local script does all the work, no AI judgment here.

## Role
Driver/executor. You run the collector and validate the output shape. You do
not evaluate anything.

## Context to load
- `_config/conventions.md` (paths, evidence rules)
- Nothing else. Do not load `rules/rules.md`.

## Task contract

```powershell
.\scripts\collect_azure.ps1 -AppName <app> -ResourceGroup <rg> [-Subscription <sub>] [-Type webapp|functionapp]
```

- Reads: live Azure subscription (az CLI, secret-free)
- Writes: `snapshot\azure_snapshot.json` (overwrites any stale snapshot)

## Validation (before declaring done)
The snapshot must contain all fields:
`collected_utc, source, subscription, resource_id, site, identity,
network, diagnostic_settings, platform_facts`.

`site` must embed the resource configuration (`config` object with
`httpsOnly`, `minTlsVersion`, `scmMinTlsVersion`, `ftpsState`,
`remoteDebuggingEnabled`) — this is what the K-events in `rules\rules.md`
key off.

If `site` is present but other fields are missing or the file fails to
parse, do not proceed to stage 02 — fix collection first.

## Definition of done
- `snapshot\azure_snapshot.json` exists, parses as JSON, has all fields
- You have printed the one-line resource id and `collected_utc` timestamp
- Next routing statement: "Snapshot ready. Route to 02_evaluate."
