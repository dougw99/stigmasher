#Requires -Version 5.1
<#
.SYNOPSIS
  Stage 01 tool (placeholder): collects App Service STIG evidence via az CLI
  into a JSON snapshot.
.DESCRIPTION
  TODO: implement az CLI evidence collection for the App Service STIG's
  check_content requirements. Model shape after cosmos-stig\scripts\collect_azure.ps1:
  - secret-free az commands only
  - unwrap az list-command `value` wrappers
  - normalize to arrays
  - write BOM-less UTF-8 JSON to snapshot\
  The exact set of commands depends on the STIG's evidence needs — derive them
  from rules\rules.md (build the key events FIRST, then collect what they need).
#>
throw "collect script for appservice-stig is not implemented. Fill in per scripts\collect_azure.ps1 in cosmos-stig (same pattern: az CLI -> snapshot\azure_snapshot.json)."
