#Requires -Version 5.1
<#
.SYNOPSIS
  Collects Azure App Service configuration evidence via az CLI into a JSON snapshot.
.DESCRIPTION
  Runs repeatable, secret-free evidence collection. The snapshot is the single
  input for stage 02 (evaluation), making assessments repeatable and auditable.
.PARAMETER AppName
  App Service (web app or function app) name.
.PARAMETER ResourceGroup
  Resource group of the app.
.PARAMETER Subscription
  Optional subscription id/name.
.PARAMETER Type
  webapp or functionapp (default: webapp).
.PARAMETER OutputFile
  Where to write the snapshot (default: snapshot\azure_snapshot.json).
.EXAMPLE
  .\collect_azure.ps1 -AppName myapp -ResourceGroup myrg
#>
param(
  [Parameter(Mandatory = $true)][string]$AppName,
  [Parameter(Mandatory = $true)][string]$ResourceGroup,
  [string]$Subscription,
  [ValidateSet("webapp", "functionapp")][string]$Type = "webapp",
  [string]$OutputFile
)
if (-not $OutputFile) { $OutputFile = Join-Path (Split-Path $PSScriptRoot -Parent) 'snapshot\azure_snapshot.json' }

$ErrorActionPreference = "Stop"

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
  if ($obj -and $obj.PSObject.Properties['value']) { return @($obj.value) }
  return $obj
}

Assert-Az
if ($Subscription) { & az account set --subscription $Subscription | Out-Null }

$resourceId = (& az $Type show --name $AppName --resource-group $ResourceGroup --query id -o tsv 2>$null)
if ($LASTEXITCODE -ne 0 -or -not $resourceId) { throw "App Service '$AppName' not found in '$ResourceGroup'." }
$resourceId = "$resourceId".Trim()

Write-Host "Collecting evidence for: $resourceId"

$site      = Invoke-AzJson @($Type, "show", "--name", $AppName, "--resource-group", $ResourceGroup)
$siteConf  = Invoke-AzJson @($Type, "config", "show", "--name", $AppName, "--resource-group", $ResourceGroup)
$dsm       = Invoke-AzJson @("monitor", "diagnostic-settings", "list", "--resource", $resourceId) -AllowFailure

# keep only decision-relevant config fields (contract in rules\rules.md snapshot table)
$keyFields = 'httpsOnly','minTlsVersion','scmMinTlsVersion','ftpsState','http20Enabled',
             'webSocketsEnabled','remoteDebuggingEnabled','alwaysOn','healthCheckEnabled'
$conf = [ordered]@{}
if ($site) {
  foreach ($f in @('httpsOnly')) {
    if ($site.PSObject.Properties[$f]) { $conf[$f] = $site.$f }
  }
}
if ($siteConf) {
  foreach ($f in $keyFields) {
    if ($siteConf.PSObject.Properties[$f]) { $conf[$f] = $siteConf.$f }
  }
}

$identity = $null
if ($site -and $site.PSObject.Properties['identity']) { $identity = $site.identity }
$network = [ordered]@{
  ip_security_restrictions    = @(if ($siteConf -and $siteConf.PSObject.Properties['ipSecurityRestrictions']) { @($siteConf.ipSecurityRestrictions) } else { @() })
  virtual_network_subnet_id   = $(if ($site -and $site.PSObject.Properties['virtualNetworkSubnetId']) { $site.virtualNetworkSubnetId } else { $null })
}

$platformFacts = [ordered]@{
  managed_service          = $true
  note                     = "App Service is a fully managed Microsoft platform service. Microsoft maintains and patches the platform images/runtime stacks; tenants cannot alter OS-level file permissions, log-tool binaries, or the platform TLS provider stack. Inbound listener ports are 80/443 (plus FTP per ftpsState). All persisted platform state is encrypted at rest (CMK optional on premium tiers). Log timestamps are UTC; platform components are NTP-synchronized. Management is exclusively HTTPS ARM/portal."
  fips_tls                 = "TLS provider stack on Windows hosts is FIPS 140-validated; TLS 1.2+/1.3 enforced via minTlsVersion"
  at_rest_encryption       = "platform-managed keys by default; CMK via Key Vault on premium tiers"
}

$snapshot = [ordered]@{
  collected_utc       = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
  source              = "az CLI"
  subscription        = "$(& az account show --query id -o tsv)".Trim()
  resource_id         = $resourceId
  site                = [ordered]@{
    id     = $(if ($site) { $site.id } else { $resourceId })
    kind   = $(if ($site -and $site.PSObject.Properties['kind']) { $site.kind } else { $null })
    state  = $(if ($site -and $site.PSObject.Properties['state']) { $site.state } else { $null })
    tier   = $(if ($site -and $site.PSObject.Properties['sku']) { $site.sku } else { $null })
    config = $conf
  }
  identity            = $identity
  network             = $network
  diagnostic_settings = @($dsm | Where-Object { $_ })
  platform_facts      = $platformFacts
}

$outDir = Split-Path $OutputFile -Parent
if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$json = ConvertTo-Json -InputObject $snapshot -Depth 40
# BOM-less UTF-8 per _config\conventions.md (PS 5.1 Set-Content -Encoding UTF8 writes a BOM)
[IO.File]::WriteAllText($OutputFile, $json, (New-Object Text.UTF8Encoding($false)))
Write-Host "Snapshot written: $OutputFile"
