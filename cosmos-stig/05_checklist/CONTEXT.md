# Stage 05 — Checklist

## Purpose
Produce the deliverables: a filled STIG checklist and a findings report.
Mechanical only — `compose_checklist.ps1` does the work, you just run and
verify it.

## Role
Publisher. Run the script, verify outputs, report the summary.

## Context to load
- `_config/conventions.md` (UTF-8 rule, output locations)

## Task contract

```powershell
.\scripts\compose_checklist.ps1
# options: -Checklist -Mapping -Snapshot -OutChecklist -Report -KeepSnapshot
```

- Reads: `04_map\output\rules-mapping.json`, `_config\Database Checklist.cklb`
  (read-only baseline),
  `snapshot\azure_snapshot.json` (metadata only)
- Writes: `output\<resource-name>_filled.cklb` + `output\review_report.md`, where
  `<resource-name>` is the assessed resource's name (from the snapshot); the checklist's
  `target_data.host_name` is stamped with the same resource name
- Note: this script DOES NOT evaluate statuses; it only applies the mapping
  values. If it complains, fix stage 04's mapping instead.

## Verification (done by you, after the script)
1. Parse the filled checklist and confirm rule count matches the source.
2. Confirm the report's status-summary table and open-item count.
3. Confirm the snapshot was archived to `output\` (unless `-KeepSnapshot`) so
   stale evidence cannot be reused.

## Definition of done
- Both artifacts exist in `output\`, checklist parses, report reflects the
  mapping
- Next routing statement: "Assessment complete — artifacts in output\."
