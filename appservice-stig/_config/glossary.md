# Glossary

STIG checklist (STIG Viewer 3 `.cklb`) vocabulary, per V4R6 Database SRG.

## Tracker statuses
| Status | Meaning |
|---|---|
| `not_a_finding` | Control requirement is met by evidence or platform architecture; comment must explain how |
| `open` | Requirement is not met; comment states the gap and remediation direction |
| `not_applicable` | Requirement cannot be met by design of the system (e.g., no user passwords exist); comment must justify why scope excludes it |
| `not_reviewed` | No confident decision yet — left for human adjudication; never hidden |

## Checklist fields
| Field | Content |
|---|---|
| `status` | one of the four statuses above (or the STIG default `not_reviewed` when untouched) |
| `comments` | audit-grade human-readable justification for the status |
| `finding_details` | exact evidence reference (`path=value`) or check-content quote |

## STIG identifiers in this repo
- `GroupID` (`V-NNNNNN`) is the join key used across rules.md, mapping,
  checklist. The leading `V-` is normalized away only inside scripts
  (`NormalizeId`), never in human-readable files.

## Evidence snapshot fields (per `collect_azure.ps1`)
`collected_utc, source, subscription, resource_id, account,
diagnostic_settings, sql_role_definitions, sql_role_assignments, sql_databases,
private_endpoints` — field definitions and usage live in `rules\rules.md`
("Snapshot reference").
