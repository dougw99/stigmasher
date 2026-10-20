#Requires -Version 5.1
<#
.SYNOPSIS
  Evaluates a Cosmos DB evidence snapshot against the deterministic rules map
  and writes statuses/comments/finding_details into the STIG cklb checklist.
.DESCRIPTION
  Repeatable assessment pipeline:
    1. collect_azure.ps1 snapshots Azure Cosmos DB configuration to JSON.
    2. This script applies rules-map.json deterministically.
    3. Rules it cannot evidence confidently are left not_reviewed and listed in
       review_report.md for AI-agent / human review.
.PARAMETER Checklist
  Path to the .cklb checklist (default: 'Database Checklist.cklb').
.PARAMETER Snapshot
  Path to the azure snapshot JSON (default: snapshot\azure_snapshot.json).
.PARAMETER RulesMap
  Path to rules map JSON (default: rules-map.json).
.PARAMETER OutChecklist
  Path to write the filled checklist (default: '<input>_filled.cklb').
.PARAMETER Report
  Path for the markdown review report (default: 'review_report.md').
.EXAMPLE
  .\run.ps1 -Checklist 'Database Checklist.cklb' -Snapshot snapshot\azure_snapshot.json
#>
param(
  [string]$Checklist,
  [string]$Snapshot,
  [string]$RulesMap,
  [string]$OutChecklist,
  [string]$Report,
  # After a successful run the snapshot is moved to output\ so it cannot be
  # accidentally reused without re-collecting fresh evidence. Set to keep it.
  [switch]$KeepSnapshot
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path $PSScriptRoot -Parent

# ---------------------------------------------------------- helpers
function ConvertTo-CharpString { param($v) if ($null -eq $v) { "" } else { "$v" } }
function NormalizeId { param($id) ($id -replace '^V-', '') }

# defaults resolved from repo root
if (-not $Checklist)   { $Checklist   = Join-Path $RepoRoot 'Database Checklist.cklb' }
if (-not $Snapshot)    { $Snapshot    = Join-Path $RepoRoot 'snapshot\azure_snapshot.json' }
if (-not $RulesMap)    { $RulesMap    = Join-Path $RepoRoot 'rules\rules-map.json' }
if (-not $Report)      { $Report      = Join-Path $RepoRoot 'output\review_report.md' }

# ---------------------------------------------------------- load inputs
foreach ($f in @($Checklist, $Snapshot, $RulesMap)) {
  if (-not (Test-Path -LiteralPath $f)) { throw "Required input not found: $f" }
}

$checklistRaw = Get-Content -LiteralPath $Checklist -Raw
$cklb = $checklistRaw | ConvertFrom-Json
$snap = Get-Content -LiteralPath $Snapshot -Raw | ConvertFrom-Json
$map  = Get-Content -LiteralPath $RulesMap -Raw | ConvertFrom-Json

if (-not $OutChecklist) {
  $base = [IO.Path]::GetFileNameWithoutExtension($Checklist)
  $outDir = Join-Path $RepoRoot 'output'
  if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
  $OutChecklist = Join-Path $outDir ($base + '_filled.cklb')
}

$acct = $snap.account
# az CLI may return settings either nested under .properties or at top level
if ($acct.PSObject.Properties['properties'] -and $acct.properties) { $ap = $acct.properties } else { $ap = $acct }
$ds   = @($snap.diagnostic_settings | Where-Object { $_ })

function Test-DiagEnabled {
  param([string]$LogName, [string[]]$Categories)
  foreach ($d in $ds) {
    if (-not $d.logs) { continue }
    $enabledLogs = @($d.logs | Where-Object { $_.enabled })
    $hasLog = $enabledLogs | Where-Object { $_.category -ieq $LogName }
    if (-not $hasLog) { continue }
    if (-not $Categories) { return $true }
    foreach ($c in $Categories) {
      if ($hasLog | Where-Object { $_.category -ieq $c }) { return $true }
    }
  }
  return $false
}

function Get-DiagDestination {
  foreach ($d in $ds) {
    if ($d.workspaceId) { return "Log Analytics workspace $($d.workspaceId)" }
  }
  if ($ds.Count -gt 0) { return "storage/eventhub destination" }
  return $null
}

# ---------------------------------------------------------- check kinds
function Resolve-Rule {
  param($entry, $rule)

  function Result {
    param([string]$status, [string]$comment, [string]$details)
    return @{ status = $status; comment = $comment; details = $details }
  }

  $title = ConvertTo-CharpString $rule.rule_title
  $checkEval = $null

  switch ($entry.kind) {

    'public_access' {
      $pna = ConvertTo-CharpString $ap.publicNetworkAccess
      $ipr = ConvertTo-CharpString $ap.ipRangeFilter
      $ipRules = @($ap.ipRules | Where-Object { $_ })
      if ($pna -eq 'Disabled') {
        return Result 'not_a_finding' "Public network access is disabled on the Cosmos DB account; access restricted to private endpoints/VNets." "Evidence: publicNetworkAccess=$pna (case-insensitive). Check:$($rule.check_content)"
      }
      if ($ipRules.Count -gt 0 -or ($ipr -and $ipr -ne '*' -and -not ($ipr -match '^\s*0\.0\.0\.0')) ) {
        return Result 'not_a_finding' "Inbound access restricted by firewall rules to approved networks only." "Evidence: publicNetworkAccess=$pna; ipRules=$($ipRules | ForEach-Object { $_.ipAddressOrRange }) ; ipRangeFilter=$ipr. Check:$($rule.check_content)"
      }
      return Result 'open' "Public network access is enabled and no firewall rules restrict access. Restrict via ipRules/firewall or disable public access and use private endpoints." "Evidence: publicNetworkAccess=$pna; ipRules count=$($ipRules.Count); ipRangeFilter='$ipr'. Check:$($rule.check_content)"
    }

    'local_auth' {
      $dla = $ap.disableLocalAuth
      if ($dla -eq $true) {
        return Result 'not_a_finding' "Only Azure AD/Entra ID-based (Microsoft Entra) authentication is enabled (disableLocalAuth=$dla)." "Evidence: properties.disableLocalAuth=$dla. Check:$($rule.check_content)"
      }
      return Result 'open' "Local authentication via primary/secondary keys or resource token is enabled (disableLocalAuth=$dla). Disable local auth to enforce RBAC/Azure AD-only authentication." "Evidence: properties.disableLocalAuth=$dla. Check:$($rule.check_content)"
    }

    'tls_version' {
      $tls = ConvertTo-CharpString $ap.minimalTlsVersion
      if ($tls -match 'TLS12' -or ($tls -eq '')) {
        return Result 'not_a_finding' "TLS transport encryption enforced by platform (minimalTlsVersion=$tls; empty defaults to TLS12+)." "Evidence: properties.minimalTlsVersion='$tls'. Check:$($rule.check_content)"
      }
      return Result 'open' "minimalTlsVersion set to unsupported version: $tls. Set to Tls12 or later." "Evidence: properties.minimalTlsVersion=$tls. Check:$($rule.check_content)"
    }

    'encryption_at_rest' {
      $eks = ConvertTo-CharpString $ap.encryptionKeySource
      $kvUri = $ap.keyVaultKeyUri
      # Cosmos DB is encrypted at rest by default; absence of encryptionKeySource = platform-managed keys
      if ($eks -match 'Keyvault|Microsoft\.KeyVault' -and $kvUri) {
        return Result 'not_a_finding' "At-rest encryption enforced with customer-managed keys in AKV ($eks)." "Evidence: encryptionKeySource=$eks; keyVaultKeyUri=$kvUri. Check:$($rule.check_content)"
      }
      return Result 'not_a_finding' "At-rest encryption enforced by platform with Microsoft-managed keys (CMK not configured). Cosmos DB data at rest is always encrypted; verify CMK is required for this data classification." "Evidence: encryptionKeySource=$(if ($eks) { $eks } else { 'default platform-managed' }); keyVaultKeyUri=$(ConvertTo-CharpString $kvUri). Check:$($rule.check_content)"
    }

    'key_storage' {
      $eks = ConvertTo-CharpString $ap.encryptionKeySource
      $kvUri = $ap.keyVaultKeyUri
      if ($eks -match 'Keyvault|Microsoft\.KeyVault' -and $kvUri) {
        return Result 'not_a_finding' "Customer-managed encryption keys stored in Azure Key Vault (hardware-backed HSM)." "Evidence: encryptionKeySource=$eks; keyVaultKeyUri=$kvUri. Check:$($rule.check_content)"
      }
      return Result 'not_reviewed' "Platform-managed encryption keys in Microsoft-managed HSM; confirm protected key storage meets organization-defined safeguards." "Evidence: encryptionKeySource=$(if ($eks) { $eks } else { 'default platform-managed' }); keyVaultKeyUri=$(ConvertTo-CharpString $kvUri). Check:$($rule.check_content)"
    }

    'classified_crypto' {
      # high classification - no automatic status.
      return Result 'not_reviewed' "Human review: classified data (if present) must use NSA-approved cryptography; verify configuration per DoW guidance." "No automatic status assigned for classified-data rule."
    }

    'diagnostics_to_la' {
      $enabled = Test-DiagEnabled -LogName $null -Categories $null
      $dest = Get-DiagDestination
      if ($enabled -and $dest -match 'Log Analytics') {
        return Result 'not_a_finding' ("Audit data offloaded to {0} near real-time. Centralized review/analysis supported." -f $dest) "Diagnostic settings enabled; destination=$dest. Check:$($rule.check_content)"
      }
      return Result 'open' "Diagnostic settings to Log Analytics not confirmed. Enable and route audit data to a centralized log management facility." "Diagnostic settings present: $($ds.Count); destination=$(ConvertTo-CharpString $dest). Check:$($rule.check_content)"
    }

    'audit_generated' {
      $categories = @('DataPlaneRequests', 'QueryRuntimeStatistics', 'MongoRequests', 'CassandraRequests', 'GremlinRequests', 'TableRequests')
      $enabledData = $false
      foreach ($c in $categories) {
        if (Test-DiagEnabled -LogName $c -Categories $null) { $enabledData = $true; break }
      }
      if ($enabledData) {
        return Result 'not_a_finding' "Cosmos DB diagnostic settings audit data-plane events to centralized log facility." "Evidence: diagnostic settings include data-plane request logging (DataPlaneRequests etc.). Check:$($rule.check_content)"
      }
      return Result 'open' "Audit record generation for data-plane events is not confirmed. Enable Cosmos DB diagnostic settings (DataPlaneRequests) to a Log Analytics workspace." "No data-plane request logging category found enabled. Check:$($rule.check_content)"
    }

    'audit_generated_detailed' {
      $qrs = Test-DiagEnabled -LogName 'QueryRuntimeStatistics' -Categories $null
      $dp  = Test-DiagEnabled -LogName 'DataPlaneRequests' -Categories $null
      if ($qrs -and $dp) {
        return Result 'not_a_finding' "Cosmos DB diagnostics include QueryRuntimeStatistics and DataPlaneRequests, providing start/end time and identity detail." "Evidence: QueryRuntimeStatistics+DataPlaneRequests enabled. Check:$($rule.check_content)"
      }
      return Result 'open' "Sufficient detail (QueryRuntimeStatistics + DataPlaneRequests) not confirmed. Enable both categories in diagnostic settings." "QueryRuntimeStatistics=$qrs; DataPlaneRequests=$dp. Check:$($rule.check_content)"
    }

    'access_control' {
      $defs = @($snap.sql_role_definitions)
      $asgns = @($snap.sql_role_assignments)
      $dla = $ap.disableLocalAuth
      if ($dla -eq $true -and $defs.Count -gt 0 -and $asgns.Count -gt 0) {
        return Result 'not_a_finding' "Cosmos DB SQL/RBAC role definitions ($($defs.Count)) and assignments ($($asgns.Count)) in place with local auth disabled. Access control enforced at DBMS level." "Evidence: disableLocalAuth=$dla; role definitions=$($defs.Count); role assignments=$($asgns.Count). Check:$($rule.check_content)"
      }
      if ($dla -eq $false) {
        return Result 'open' "Local auth keys enabled; enable disableLocalAuth and configure Cosmos DB SQL role definitions/assignments to enforce access control." "Evidence: disableLocalAuth=$dla; role definitions=$($defs.Count); role assignments=$($asgns.Count). Check:$($rule.check_content)"
      }
      return Result 'not_reviewed' "Human review: RBAC configured (defs=$($defs.Count), asgns=$($asgns.Count)) but local auth state uset. Confirm." "Evidence: disableLocalAuth=$(ConvertTo-CharpString $dla). Check:$($rule.check_content)"
    }

    'pki_general' {
      $dla = $ap.disableLocalAuth
      return Result 'not_reviewed' "PKI/cert evaluation: Cosmos DB uses Microsoft-managed certificates for endpoint TLS. Confirm organization PKI requirements with respect to this platform service." "Evidence: disableLocalAuth=$(ConvertTo-CharpString $dla); no customer-managed certificate stores exposed. Check:$($rule.check_content)"
    }

    'key_auth_dependent' {
      # Rule depends on per-user identity; shared account keys defeat it.
      $dla = $ap.disableLocalAuth
      if ($dla -eq $true) {
        return Result 'not_applicable' "Not applicable: shared account keys are disabled; per-user identity supplied by Entra ID-only auth." "Evidence: disableLocalAuth=$dla. Check:$($rule.check_content)"
      }
      elseif ($dla -eq $false) {
        return Result 'open' ("Shared account keys are enabled (disableLocalAuth=False): {0}" -f $entry.comment) "Evidence: disableLocalAuth=$dla. Check:$($rule.check_content)"
      }
      return Result 'not_reviewed' $entry.comment "Evidence: disableLocalAuth not set. Check:$($rule.check_content)"
    }

    'audit_support' {
      # Audit-support requirements: need an audit pipeline in place to configure/protect.
      if ($ds.Count -eq 0) {
        return Result 'open' "No audit pipeline configured: diagnostic settings are absent, so auditable events are not being selected, stored, protected, or alerted on. Enable diagnostic settings to a Log Analytics workspace." "Evidence: diagnostic_settings count=0. Check:$($rule.check_content)"
      }
      return Result 'not_reviewed' $entry.comment "Evidence: $(Get-DiagDestination). Check:$($rule.check_content)"
    }

    'diag_dependent' {
      if ($ds.Count -gt 0) {
        return Result 'not_a_finding' ("{0}" -f $entry.comment) "Evidence: diagnostic settings count=$($ds.Count); destination=$(Get-DiagDestination). Check:$($rule.check_content)"
      }
      return Result 'open' ("{0} Diagnostic logging is not enabled." -f $entry.comment) "Evidence: diagnostic_settings count=0. Check:$($rule.check_content)"
    }

    'no_databases' {
      $dbs = @($snap.sql_databases | Where-Object { $_ })
      if ($dbs.Count -eq 0) {
        return Result 'not_a_finding' "No databases/collections exist in the account; no samples or unused objects are present." "Evidence: sql_databases count=0. Check:$($rule.check_content)"
      }
      return Result 'not_reviewed' "Human review: confirm all databases ($($dbs.Count)) are required and no samples remain." "Evidence: sql_databases count=$($dbs.Count). Check:$($rule.check_content)"
    }

    'password_list' {
      $dla = $ap.disableLocalAuth
      if ($dla -eq $true) {
        return Result 'not_applicable' "Not applicable: password-based authentication to the database is not employed; only Azure AD/Entra ID authentication is permitted." "Evidence: disableLocalAuth=$dla. Check:$($rule.check_content)"
      }
      return Result 'not_reviewed' "Password auth possible via account keys; human review regarding password-policy mapping to Azure AD required." "Evidence: disableLocalAuth=$(ConvertTo-CharpString $dla). Check:$($rule.check_content)"
    }

    default {
      # 'static' kind with explicit status / fallbacks
      if ($null -ne $entry.status) {
        return Result $entry.status $entry.comment ("Check content: {0}" -f $rule.check_content)
      }
      return Result 'not_reviewed' $entry.comment ("Check content: {0}" -f $rule.check_content)
    }
  }
}

# cast 'static' kind rules
$mapById = @{}
foreach ($e in $map.rules) { $gid = NormalizeId $e.group_id; $mapById[$gid] = $e }

# ---------------------------------------------------------- apply
$stats = @{}
$reviewTargets = New-Object System.Collections.Generic.List[object]

$stig = $cklb.stigs[0]
foreach ($rule in $stig.rules) {
  $gid = NormalizeId $rule.group_id
  $entry = $mapById[$gid]
  $res = $null
  if ($entry) {
    try {
      $res = Resolve-Rule -entry $entry -rule $rule
    } catch {
      Write-Warning "Error evaluating $($rule.rule_id) [$($entry.kind)]: $_"
    }
  }

  if ($res) {
    if ($res.status -ne $rule.status -or -not $rule.status) { $rule.status = $res.status }
    $rule.comments        = $res.comment
    $rule.finding_details = $res.details
    $key = $res.status
    if ($stats.ContainsKey($key)) { $stats[$key] = $stats[$key] + 1 } else { $stats[$key] = 1 }
  } else {
    $ruleAdded = $false
    if (-not $ruleAdded) {
      # no mapping: leave as-is but flag for review
      $reviewTargets.Add([pscustomobject]@{
        rule_id = $rule.rule_id; group_id = $gid; title = $rule.rule_title
        severity = $rule.severity; reason = "no mapping entry"
      })
      if ($stats.ContainsKey('unmapped')) { $stats['unmapped'] = $stats['unmapped'] + 1 } else { $stats['unmapped'] = 1 }
    }
  }
}

# ---------------------------------------------------------- save cklb
$outJson = $cklb | ConvertTo-Json -Depth 40 -ErrorAction SilentlyContinue
# PS 5.1 ConvertTo-Json can fail silently on deep/nested byte types; verifying parse
$null = $outJson | ConvertFrom-Json
# BOM-less UTF-8 (PS5.1 Set-Content -Encoding UTF8 writes a BOM that breaks JSON parsers)
$checklistOutAbs = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutChecklist)
[System.IO.File]::WriteAllText($checklistOutAbs, $outJson, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Checklist written: $OutChecklist"

# ---------------------------------------------------------- report
$lines = @()
$lines += "# Cosmos DB STIG Assessment - Review Report"
$lines += ""
$lines += "- Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$lines += "- Account: $($acct.id) ($($acct.location))"
$lines += "- Checklist: $Checklist -> $OutChecklist"
$lines += "- Snapshot: $Snapshot (collected $($snap.collected_utc))"
$lines += ""
$lines += "## Status summary"
$lines += ""
$lines += "| Status | Count |"
$lines += "|---|---|"
foreach ($k in ($stats.Keys | Sort-Object)) { $lines += "| $k | $($stats[$k]) |" }
$lines += ""
$lines += "## Rules requiring human/AI review"
$lines += ""
$lines += "These rules have no deterministic mapping. The agent (OpenCode/Claude) and/or human must evaluate:"
$lines += ""
$lines += "| Rule | Severity | Title | Guidance |"
$lines += "|---|---|---|---|"
foreach ($r in $reviewTargets) {
  $lines += "| $($r.rule_id) | $($r.severity) | $($r.title) | $($r.reason) |"
}
$lines += ""
$lines += "## AI fallback instruction"
$lines += ""
$lines += "For the rules listed above, use the checklist entries' check_content against the evidence in snapshot\azure_snapshot.json."
$lines += "Assign the most evidence-based status (not_a_finding/open/not_applicable) in comments/finding_details."
$lines += "Uncertain cases remain not_reviewed for human adjudication."

$reportLines = $lines -join [Environment]::NewLine
[System.IO.File]::WriteAllText($Report, $reportLines, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Report written: $Report"

# ---------------------------------------------------------- archive snapshot
$reportAbs  = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Report)
$snapshotAbs = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Snapshot)
if (-not $KeepSnapshot) {
  $outDirAbs = Split-Path $reportAbs -Parent
  $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
  $archivedName = "{0}_{1}{2}" -f [IO.Path]::GetFileNameWithoutExtension($snapshotAbs), $stamp, [IO.Path]::GetExtension($snapshotAbs)
  $archivedPath = Join-Path $outDirAbs $archivedName
  Move-Item -LiteralPath $snapshotAbs -Destination $archivedPath -Force
  # add archived evidence to the report tail
  [System.IO.File]::AppendAllText($reportAbs, "`n- Snapshot archived to: $archivedName (moved so it cannot be reused without re-collecting)", (New-Object System.Text.UTF8Encoding($false)))
  Write-Host "Snapshot archived: $archivedPath"
}

# ---------------------------------------------------------- summary
Write-Host ""
Write-Host "Summary:"
$stats.GetEnumerator() | Sort-Object Name | ForEach-Object { Write-Host ("  {0,-18} {1}" -f $_.Key, $_.Value) }

