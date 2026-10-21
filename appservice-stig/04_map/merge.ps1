$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent

$snapshot = Get-Content -Encoding UTF8 (Join-Path $root "snapshot\azure_snapshot.json") -Raw | ConvertFrom-Json
$snapUtc = $snapshot.collected_utc

$eval = Get-Content -Encoding UTF8 (Join-Path $root "02_evaluate\output\evaluation.md") | Where-Object { $_ -match '^\| V-\d{6} \|' }
$dec = Get-Content -Encoding UTF8 (Join-Path $root "03_review\output\decisions.md") | Where-Object { $_ -match '^\| V-\d{6} \|' }

$legal = 'not_a_finding','open','not_applicable','not_reviewed'
$evalMap = $eval | ForEach-Object {
  $c = ($_ -split '\|').Trim()
  [pscustomobject]@{ id = $c[1]; status = $c[2]; comment = $c[4]; detail = $c[4] }
}
$decMap = $dec | ForEach-Object {
  $c = ($_ -split '\|').Trim()
  [pscustomobject]@{ id = $c[1]; status = $c[2]; reason = $c[3]; badge = $c[4] }
}

$cklb = Get-Content -Encoding UTF8 (Join-Path $root "_config\App Server.cklb") -Raw | ConvertFrom-Json
$all = @($cklb.stigs[0].rules | ForEach-Object { $_.group_id })

$rules = foreach ($id in $all) {
  $e = @($evalMap | Where-Object { $_.id -eq $id })[0]
  if (-not $e) { throw "evaluation.md is missing rule $id" }
  $d = @($decMap | Where-Object { $_.id -eq $id })[0]
  if ($d) {
    $status = $d.status
    # cleanup: eval text may end with a question tail; drop the Q: part
    $ctx = ($e.comment -replace '\s*Q:.*$','' -replace '\s*stage 03\.$','').TrimEnd()
    $comment = "$ctx; org decision: $($d.reason)"
    $detail = "Evidence: org review decision 2026-10-21 with reason: '$($d.reason)'"
  } else {
    if ($e.status -eq 'needs_user') { throw "rule $id has needs_user with no decision row" }
    $status = $e.status
    if ($legal -notcontains $status) { throw "illegal status '$status' for $id" }
    $comment = $e.comment
    $detail = "Evidence: $($e.detail)"
  }
  [ordered]@{ group_id = $id; status = $status; comment = $comment; finding_details = $detail }
}

$out = [ordered]@{
  generated_utc          = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
  snapshot_collected_utc = $snapUtc
  rules                  = $rules
}
$json = ConvertTo-Json -InputObject $out -Depth 6
[IO.File]::WriteAllText((Join-Path $root "04_map\output\rules-mapping.json"), $json, (New-Object Text.UTF8Encoding($false)))

# coverage/status validation
$m = Get-Content (Join-Path $root "04_map\output\rules-mapping.json") -Raw | ConvertFrom-Json
$ids = @($m.rules | ForEach-Object { $_.group_id })
Write-Host "Mapping written. Rules: $($ids.Count)"
$badStatus = @($m.rules | Where-Object { $legal -notcontains $_.status })
Write-Host "Illegal statuses: $($badStatus.Count)"
$noComment = @($m.rules | Where-Object { -not $_.comment -or -not $_.finding_details })
Write-Host "Missing comment/detail: $($noComment.Count)"
if ($badStatus.Count -or $noComment.Count) { exit 1 }
