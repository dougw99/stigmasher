#Requires -Version 5.1
<#
.SYNOPSIS
  Collects Cosmos DB configuration evidence from Azure via az CLI into a JSON snapshot.
.DESCRIPTION
  Runs repeatable, secret-free evidence collection. The snapshot is the single
  input for the evaluation stages, making assessments repeatable and auditable.
.PARAMETER AccountName
  Cosmos DB account name.
.PARAMETER ResourceGroup
  Resource group of the account.
.PARAMETER Subscription
  Optional subscription id/name.
.PARAMETER OutputFile
  Where to write the snapshot (default: snapshot\azure_snapshot.json).
.EXAMPLE
  .\collect_azure.ps1 -AccountName mycosmos -ResourceGroup myrg
#>
param(
  [Parameter(Mandatory = $true)][string]$AccountName,
  [Parameter(Mandatory = $true)][string]$ResourceGroup,
  [string]$Subscription,
  [string]$OutputFile
)
if (-not $OutputFile) { $OutputFile = Join-Path (Split-Path $PSScriptRoot -Parent) 'snapshot\azure_snapshot.json' }

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path $PSScriptRoot -Parent

function Assert-Az {
  if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw "Azure CLI (az) not found. Install: https://aka.ms/azure-cli"
  }
  $null = & az account show 2>$null
  if ($LASTEXITCODE -ne 0) { throw "Not logged in to Azure. Run: az login" }
}

function Invoke-AzJson {
  param([string[]]$AzArgs, [switch]$AllowFailure)
  Write-Host "  > az $($AzArgs -join ' ')"
  $raw = & az @AzArgs 2>$null
  if ($LASTEXITCODE -ne 0) {
    if ($AllowFailure) { return @() }
    throw "az command failed: az $($AzArgs -join ' ')"
  }
  if (-not $raw -or $raw.Count -eq 0) { return @() }
  $obj = $raw | ConvertFrom-Json -ErrorAction Stop
  # az list commands wrap results in { "value": [...] }; unwrap for consumers
  if ($obj -and $obj.PSObject.Properties['value']) { return @($obj.value) }
  return $obj
}

Assert-Az
if ($Subscription) { & az account set --subscription $Subscription | Out-Null }

$resourceId = (& az cosmosdb show --name $AccountName --resource-group $ResourceGroup --query id -o tsv 2>$null)
if ($LASTEXITCODE -ne 0 -or -not $resourceId) { throw "Cosmos DB account '$AccountName' not found in '$ResourceGroup'." }
$resourceId = "$resourceId".Trim()

Write-Host "Collecting evidence for: $resourceId"

$account      = Invoke-AzJson @("cosmosdb", "show", "--name", $AccountName, "--resource-group", $ResourceGroup)
$dsm          = Invoke-AzJson @("monitor", "diagnostic-settings", "list", "--resource", $resourceId) -AllowFailure
$sqlRoleDefs  = Invoke-AzJson @("cosmosdb", "sql", "role", "definition", "list", "--account-name", $AccountName, "--resource-group", $ResourceGroup) -AllowFailure
$sqlRoleAsgns = Invoke-AzJson @("cosmosdb", "sql", "role", "assignment", "list", "--account-name", $AccountName, "--resource-group", $ResourceGroup) -AllowFailure
$sqlDatabases = Invoke-AzJson @("cosmosdb", "sql", "database", "list", "--account-name", $AccountName, "--resource-group", $ResourceGroup) -AllowFailure

$allPes = Invoke-AzJson @("network", "private-endpoint", "list", "--resource-group", $ResourceGroup) -AllowFailure
$privateEndpoints = @($allPes | Where-Object { $_.id -and (
      ($_.privateLinkServiceConnections | Where-Object { $_.privateLinkServiceId -eq $resourceId }) -or
      ($_.customDnsConfigs)
) })

$snapshot = [ordered]@{
  collected_utc        = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
  source               = "az CLI"
  subscription         = "$(& az account show --query id -o tsv)".Trim()
  resource_id          = $resourceId
  account              = $account
  diagnostic_settings  = @($dsm | Where-Object { $_ })
  sql_role_definitions = @($sqlRoleDefs | Where-Object { $_ })
  sql_role_assignments = @($sqlRoleAsgns | Where-Object { $_ })
  sql_databases        = @($sqlDatabases | Where-Object { $_ })
  private_endpoints    = @($privateEndpoints | Where-Object { $_ })
}

$outDir = Split-Path $OutputFile -Parent
if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$json = ConvertTo-Json -InputObject $snapshot -Depth 40
Set-Content -Path $OutputFile -Value $json -Encoding UTF8
Write-Host "Snapshot written: $OutputFile"
