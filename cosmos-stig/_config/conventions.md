# Conventions

Hard, non-negotiable project rules. Loaded by every stage.

## Files
- `_config\Database Checklist.cklb` is the **read-only baseline**: the reusable
  configuration template every filled checklist is built from. Never write to
  it; stage 05 reads it and writes the result to `output\`.
- All final deliverables go to `output\`. Stage intermediates stay in each
  stage's `output\` subfolder (`02_evaluate\output\`, etc.).
- Snapshots always land in `snapshot\`. A snapshot is consumed once: stage 05
  archives it to `output\` (timestamped) unless `-KeepSnapshot`.

## Encoding
- All `.cklb` and `.json` output must be **BOM-less UTF-8**.
- PowerShell 5.1 `Set-Content -Encoding UTF8` writes a BOM that STIG Viewer 3
  rejects. Use:
  `[IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding($false)))`
- ConvertTo-Json output must be round-trip verified (`ConvertFrom-Json` on the
  written string) before declaring success.

## Scripts
- **Never create new script files.** The only scripts are
  `scripts\collect_azure.ps1` and `scripts\compose_checklist.ps1`; stages
  02–04 are performed directly by the AI per their `CONTEXT.md`.
- `scripts\*.ps1` must work from any working directory: resolve paths from
  `$PSScriptRoot`.
- Scripts are mechanical: collect evidence, apply a mapping, format files.
  No evaluation logic ever moves back into scripts.

## Evidence integrity
- Never fabricate a setting absent from the snapshot — treat as unknown /
  `not_reviewed`.
- Every status cites its snapshot `path=value` in `finding_details`.
- Same evidence always produces the same statuses (determinism goal).

## Decision-recording format (stage 03)
Decisions go to `03_review\output\decisions.md` in the table defined there.
Organization-level ("always true") decisions get an extra row appended to
`_config\overrides.md`.
