#Requires -Version 5.1
<#
.SYNOPSIS
  Stage 05 tool. Applies a rules mapping to the STIG checklist, writes the
  filled checklist and a review report to output\. Mechanical only.
.DESCRIPTION
  No evaluation logic lives here. Status/comment/finding_details come verbatim
  from 04_map\output\rules-mapping.json. If a rule is missing from the mapping
  it is left at not_reviewed and listed in the report as a coverage gap.
.PARAMETER Checklist
  Source .cklb baseline (default: _config\Database Checklist.cklb). Never modified.
.PARAMETER Mapping
  Mapping JSON from stage 04 (default: 04_map\output\rules-mapping.json).
.PARAMETER Snapshot
  Evidence snapshot used this run; referenced in the report and archived to
  output\ after success (default: snapshot\azure_snapshot.json).
.PARAMETER OutChecklist
  Filled output path (default: output\<checklist-name>_filled.cklb).
.PARAMETER Report
  Report path (default: output\review_report.md).
.PARAMETER KeepSnapshot
  Skip archiving (moving) the snapshot to output\.
.EXAMPLE
  .\compose_checklist.ps1
#>
param(
  [string]$Checklist,
  [string]$Mapping,
  [string]$Snapshot,
  [string]$OutChecklist,
  [string]$Report,
  [switch]$KeepSnapshot
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path $PSScriptRoot -Parent

if (-not $Checklist) { $Checklist = Join-Path $RepoRoot '_config\Database Checklist.cklb' }
if (-not $Mapping)   { $Mapping     = Join-Path $RepoRoot '04_map\output\rules-mapping.json' }
$mappingData = $Mapping
if (-not $Snapshot)  { $Snapshot  = Join-Path $RepoRoot 'snapshot\azure_snapshot.json' }
if (-not $Report)    { $Report    = Join-Path $RepoRoot 'output\review_report.md' }

foreach ($required in @($Checklist, $mappingData)) {
  if (-not (Test-Path -LiteralPath $required)) { throw "Required input not found: $required" }
}

function NormalizeId { param($id) ($id -replace '^V-', '') }

# ---------------------------------------------------------- resource identity
# Load one input early to name outputs/target fields after the assessed resource.
$resourceName = $null
if (Test-Path -LiteralPath $Snapshot) {
  $snapData = Get-Content -LiteralPath $Snapshot -Raw | ConvertFrom-Json
  if ($snapData.account -and $snapData.account.name) {
    $resourceName = [string]$snapData.account.name
} else {
    $resourceName = $null
  }
}

if (-not $OutChecklist) {
  if ($resourceName) { $n = $resourceName } else { $n = [IO.Path]::GetFileNameWithoutExtension($Checklist) }
  $OutChecklist = Join-Path (Join-Path $RepoRoot 'output') ($n + '_filled.cklb')
}

# ---------------------------------------------------------- load
$cklb    = Get-Content -LiteralPath $Checklist -Raw | ConvertFrom-Json
$mappingPath = $mappingData
$mappingData = Get-Content -LiteralPath $mappingData -Raw | ConvertFrom-Json

$validStatuses = @('not_a_finding', 'open', 'not_applicable', 'not_reviewed')
foreach ($m in $mappingData.rules) {
  if ($validStatuses -notcontains $m.status) {
    throw "Mapping status invalid for $($m.group_id): '$($m.status)' (must be one of: $($validStatuses -join ', '))"
  }
}

# ---------------------------------------------------------- apply
$mapById = @{}
foreach ($m in $mappingData.rules) { $mapById[(NormalizeId $m.group_id)] = $m }

$stats = @{}
$covered = New-Object System.Collections.Generic.List[string]
foreach ($m in $mappingData.rules) { $covered.Add((NormalizeId $m.group_id)) }

# stamp the assessed resource into the checklist target fields
if ($resourceName) {
  if (-not $cklb.PSObject.Properties['target_data'] -or -not $cklb.target_data) { throw "Checklist has no target_data to stamp." }
  if ($cklb.target_data.PSObject.Properties['host_name']) {
    $cklb.target_data.host_name = $resourceName
  } else {
    Add-Member -InputObject $cklb.target_data -MemberType NoteProperty -Name host_name -Value $resourceName -Force
  }
  Write-Host "Target host_name set to: $resourceName"
}

$stig = $cklb.stigs[0]
foreach ($rule in $stig.rules) {
  $gid = NormalizeId $rule.group_id
  $m = $mapById[$gid]
  if ($m) {
    $rule.status          = $m.status
    $rule.comments        = if ($m.comment)        { [string]$m.comment }        else { "" }
    $rule.finding_details = if ($m.finding_details) { [string]$m.finding_details } else { "" }
    if ($stats.ContainsKey($m.status)) { $stats[$m.status]++ } else { $stats[$m.status] = 1 }
  } else {
    # unmapped rules stay untouched (source checklist default = not_reviewed)
    if ($stats.ContainsKey('unmapped')) { $stats['unmapped']++ } else { $stats['unmapped'] = 1 }
  }
}

# ---------------------------------------------------------- save checklist (BOM-less UTF-8)
$outJson = $cklb | ConvertTo-Json -Depth 40 -ErrorAction SilentlyContinue
$null = $outJson | ConvertFrom-Json   # round-trip verify
$checklistOutAbs = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutChecklist)
$outDirAbs = Split-Path $checklistOutAbs -Parent
if ($outDirAbs -and -not (Test-Path $outDirAbs)) { New-Item -ItemType Directory -Path $outDirAbs -Force | Out-Null }
[System.IO.File]::WriteAllText($checklistOutAbs, $outJson, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Checklist written: $OutChecklist"

# ---------------------------------------------------------- report
$snapInfo = "n/a"
$snapMeta = $null
if (Test-Path -LiteralPath $Snapshot) {
  try { $snapMeta = Get-Content -LiteralPath $Snapshot -Raw | ConvertFrom-Json } catch { }
}
if ($snapMeta) { $snapInfo = "$($snapMeta.resource_id) (collected $($snapMeta.collected_utc))" }

$lines = @()
$lines += "# Cosmos DB STIG Assessment - Review Report"
$lines += ""
$lines += "- Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$lines += "- Resource:  $(if ($resourceName) { $resourceName } else { 'unknown (no snapshot)' })"
$lines += "- Checklist: $Checklist -> $OutChecklist"
$lines += "- Mapping:   $mappingPath (generated $($mappingData.generated_utc); snapshot $($mappingData.snapshot_collected_utc))"
$lines += "- Snapshot:  $snapInfo"
$lines += ""
$lines += "## Status summary"
$lines += ""
$lines += "| Status | Count |"
$lines += "|---|---|"
foreach ($k in ($stats.Keys | Sort-Object)) { $lines += "| $k | $($stats[$k]) |" }
$lines += ""
$lines += "## Not ready for adjudication"
$lines += ""
if ($stats.ContainsKey('unmapped')) {
  $lines += "$($stats['unmapped']) rules had no mapping entry and remain not_reviewed."
  $lines += ""
  $lines += "| Rule | Severity | Title |"
  $lines += "|---|---|---|"
  foreach ($rule in $stig.rules) {
    if (-not $covered.Contains((NormalizeId $rule.group_id))) {
      $lines += "| $($rule.rule_id) | $($rule.severity) | $($rule.rule_title) |"
    }
  }
} else {
  $lines += "None - mapping covered every checklist rule."
}
$lines += ""
$lines += "## Open items (fix list)"
$lines += ""
$lines += "| Rule | Severity | Comment |"
$lines += "|---|---|---|"
foreach ($rule in $stig.rules) {
  if ($rule.status -eq 'open') {
    $lines += "| $($rule.rule_id) | $($rule.severity) | $($rule.comments) |"
  }
}

$reportAbs = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Report)
[System.IO.File]::WriteAllText($reportAbs, ($lines -join [Environment]::NewLine), (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Report written: $Report"

# ---------------------------------------------------------- archive snapshot
if (Test-Path -LiteralPath $Snapshot) {
  if (-not $KeepSnapshot) {
    $snapshotAbs = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Snapshot)
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $archivedName = "{0}_{1}{2}" -f [IO.Path]::GetFileNameWithoutExtension($snapshotAbs), $stamp, [IO.Path]::GetExtension($snapshotAbs)
    Move-Item -LiteralPath $snapshotAbs -Destination (Join-Path $outDirAbs $archivedName) -Force
    Write-Host "Snapshot archived: $(Join-Path $outDirAbs $archivedName)"
  } else {
    Write-Host "Snapshot kept in place: $Snapshot"
  }
}

# ---------------------------------------------------------- summary
Write-Host ""
Write-Host "Summary:"
$stats.GetEnumerator() | Sort-Object Name | ForEach-Object { Write-Host ("  {0,-15} {1}" -f $_.Key, $_.Value) }
