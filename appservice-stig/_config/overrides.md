# Organization overrides

User/organization decisions that are **always true**, regardless of snapshot
evidence. They supersede the decision tables in `rules\rules.md`.

Stage 03 appends a row here whenever the user gives an organization-level
rule (rather than a one-off per-run answer). Newest wins; never delete rows
without user consent.

| Group ID(s) | Status | Reason | Decided | Notes |
|---|---|---|---|---|
| — | — | — | — | — |
| V-204746; V-204784; V-263551; V-263552 | not_a_finding | MFA + conditional access enforced for privileged users (user decision 2026-10-21) | 2026-10-21 | tenant-level mgmt-plane identity |
| V-204800; V-204801; V-204806; V-204807; V-204808; V-204809; V-204754; V-204756; V-204805; V-204811; V-204832; V-240925; V-263554 | not_a_finding | DoD PKI/CAC in use and verified for this system (user decision 2026-10-21) | 2026-10-21 | incl. PIV/FICAM acceptance at tenant sign-in |
| V-204831; V-263555 | not_a_finding | NIST key management / protected key storage delegated to platform + Key Vault (verified with org) | 2026-10-21 | platform_facts |
| V-204750; V-204798; V-204804; V-263549 | not_a_finding | Entra tenant policy enforces account lifecycle (inactivity disable, reauth, cached-auth limits, unassociated accounts) | 2026-10-21 | — |
| V-204713; V-204714 | not_a_finding | Standard Mandatory DoD banner present at tenant sign-in level | 2026-10-21 | — |
| V-204708; V-204715 | not_a_finding | Org-defined concurrent-session limits and non-repudiation covered-actions exist | 2026-10-21 | values not enumerated in checklist comments |
| V-204768; V-204814 | not_applicable | No redundancy mandate for this system (no MAC requirement driving HA) | 2026-10-21 | — |
| V-204796 | not_a_finding | Site config changes restricted by ARM RBAC to designated users | 2026-10-21 | — |
