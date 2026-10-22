# Rule Evaluation Guide — Cosmos DB (Database SRG V4R6)

This file is the working guide for the AI agent that performs the assessment.
It replaces "hardcoded evaluation" with: review the snapshot against the
decision tables below, set statuses, and surface only genuinely ambiguous
rules to the user.

Tracker statuses available in the checklist: `not_a_finding`, `open`,
`not_applicable`, `not_reviewed` (leave for human).

## Snapshot reference (evidence inputs)

The snapshot (`snapshot\azure_snapshot.json`) contains:

| Field | Used for |
|---|---|
| `account` (aka `properties` nested fields) | auth, network, TLS, encryption, failover settings |
| `account.disableLocalAuth` | key-auth-dependent rules |
| `account.publicNetworkAccess`, `ipRangeFilter`, `ipRules`, `private_endpoints` | network exposure rules |
| `account.minimalTlsVersion` | TLS rules |
| `account.encryptionKeySource`, `keyVaultKeyUri` | encryption-at-rest / key storage rules |
| `diagnostic_settings[].logs[].{category,enabled}`, `.workspaceId` | audit rules |
| `sql_role_definitions`, `sql_role_assignments` | access control rules |
| `sql_databases` | data-presence rules |
| `collected_utc`, `resource_id` | evidence provenance quoted in comments |

Never treat a missing field as a pass: missing evidence is `not_reviewed` and
quoted as "not present in snapshot".

## The 9 key events (oneshot decision model)

Almost every rule reduces to one of nine well-known settings or states. Evaluate
these ONCE, then reuse the outcome across all rules that depend on it.

| # | Key event | Deciding evidence | Outcome |
|---|---|---|---|
| K1 | Local auth disabled | `disableLocalAuth == true` | Identity/RBAC/accountability rules can be NAF |
| K2 | Keys still in use | `disableLocalAuth` not `true` | Key-auth-dependent rules go OPEN |
| K3 | Public access restricted | `publicNetworkAccess == Disabled` OR `(ipRules or ipRangeFilter) restrict to approved ranges` OR `private_endpoints` exist | Network exposure rules NAF |
| K4 | TLS ≥ 1.2 enforced | `minimalTlsVersion` empty (defaults to TLS12+) or matches `TLS12` | Transport crypto rules NAF |
| K5 | Encryption at rest effective | Always true for Cosmos DB (platform or CMK). Custom: `encryptionKeySource` includes KeyVault AND `keyVaultKeyUri` | CMK vs platform keys decides nuances |
| K6 | Diagnostics to centralized logs | any `diagnostic_settings` entry with enabled `logs`/`metrics` AND `workspaceId` | Data-plane retrieval rules NAF |
| K7 | Data-plane audit categories on | any enabled category among `DataPlaneRequests`, `MongoRequests`, `CassandraRequests`, `GremlinRequests`, `TableRequests` | Audit generation rules NAF |
| K8 | Detailed identity/timestamps captured | `QueryRuntimeStatistics` AND `DataPlaneRequests` both enabled | Detailed-audit rules NAF |
| K9 | RBAC configured | `sql_role_definitions` count > 0 AND `sql_role_assignments` count > 0 (with K1) | Privilege rules NAF |

Special state: `sql_databases` empty → data-plane rules may be N/N-A ("no
databases exist; re-evaluate when databases are deployed") — ask the user
whether the account is intentionally empty before using this.

## Priority ladder (applies when rules appear to conflict)

1. **User overrides** (recorded below in "Organization overrides") always win.
2. **Local auth open** (K2) makes every identity/accountability rule OPEN,
   even if the rule topic looks satisfied elsewhere.
3. **Collection gaps** (`diagnostic_settings` missing / role lists empty /
   field absent) downgrade to `not_reviewed`, never OPEN, unless a sibling
   setting proves the control is absent — then OPEN with the contradiction
   quoted.
4. **No databases** (K-empty) only justifies N/N-A for rules about data-plane
   user behavior, never for platform/audit rules.

## Decision tables

### A. Identity & accountability (`key_auth_dependent`)

Depends on K1/K2. Applies to: V-206519, 520, 522, 574, 579–581, 584, 586, 587,
206635, 233501… (full watchlist: see the `key_auth_dependent` IDs in Table A
above plus the key-auth-dependent rows in the tables below).

| Evidence | Status | Comment angle |
|---|---|---|
| K1 (local auth disabled) | `not_a_finding` | Per-user identity via Entra ID enforcement, RBAC |
| K2 (keys active) | `open` | Keys bypass per-user identity;craft issue = per-rule requirement |

Comment must name the per-rule requirement (session limits, non-repudiation,
MFA, labels, etc.), not just "keys are enabled".

### B. Network exposure (`public_access`)

Depends on K3. Rules: V-206553, 206599 (+ any network ACL rules).

| Evidence | Status |
|---|---|
| `publicNetworkAccess=Disabled` (and/or approved firewalls/private endpoints) | `not_a_finding` |
| Public access enabled AND no restricting rules | `open` |
| Public access enabled, `ipRules` not in snapshot | `not_reviewed` (quote gap) |

### C. Transport security (`tls_version`)

Depends on K4. Rules: V-206607, 206608.

| Evidence | Status |
|---|---|
| `minimalTlsVersion` empty or `Tls12`+ | `not_a_finding` |
| `minimalTlsVersion` < TLS12 | `open` |

GC-paths rules (V-206557, 206558, 206560, 206603, 263619) are static NAF unless
data classification changed — confirm in Organization overrides.

### D. Encryption at rest & key storage

Depends on K5. Rules: V-206570, 206604, 206605 (CMK storage nuances need user
confirmation unless CMK is configured).

| Evidence | Status |
|---|---|
| Customer-managed keys (`encryptionKeySource`=KeyVault + `keyVaultKeyUri`) | `not_a_finding` (with CMK comment) |
| Platform-managed keys | `not_a_finding` for at-rest rules; `not_reviewed` for "key storage safeguards" rules unless user accepts Microsoft-managed HSM |

### E. Audit & logging

Depends on K6/K7/K8. Rules: V-206523…534, 206594–598, 206612…634, 233603…

| Evidence | Status |
|---|---|
| K7 satisfied | Data-plane audit-generation rules `not_a_finding` |
| K8 satisfied | Detailed/timestamp-aware audit rules `not_a_finding` |
| K6 satisfied (LA workspace) | Diagnostics-to-central-logs rules `not_a_finding` |
| Any diagnostic / workspace gap | Missing piece → `open`; ambiguity (settings present but no workspace, empty role list) → `not_reviewed`, ask user |

### F. Access control & privilege (`access_control`)

Depends on K1+K9. Rules: V-206521, 206544, 206547, 206548, 206585, 206596,
206597.

| Evidence | Status |
|---|---|
| K1 AND K9 | `not_a_finding` |
| K2 (local auth active) | `open` |
| K1 but missing role defs/assignments | `not_reviewed`, ask user to decide |

### G. Data presence (`no_databases`)

Rules: V-206549, 206550.

| Evidence | Status |
|---|---|
| `sql_databases` empty | `open` or `not_applicable` — ask user which framing |
| Databases exist | `open` — rule requirement applies |

### H. PaaS / platform behavior (static NAF)

These rules never depend on snapshot settings; they encode architecture
("Cosmos DB is fully managed"): V-206546, 206551, 206552, 206565–567, 206575–579,
206594, 206610, 206611, 206643, 263606, 263621, 263622, 206568…571 — set NAF
with the PaaS reasoning quoted in the checklist. Review them once per
architecture change, not per run.

## Fixed per-rule decisions (static map, formerly `rules\rules-map.json`)

These rules have a fixed status + comment that do not vary with snapshot
evidence. Apply them verbatim. `_config/overrides.md` supersedes any row here.

### Static `not_a_finding`

| Group ID | Comment |
|---|---|
| V-206537 | Audit record timestamps are generated by the Cosmos DB platform infrastructure clocks and recorded in UTC. |
| V-206545, V-206551, V-206565, V-206566, V-206567, V-206643, V-263617, V-263618, V-263620 | Inherited by the Cloud Service Provider. |
| V-206546 | Cosmos DB is an Azure PaaS service; the software and configuration reside in Microsoft-managed platform infrastructure, entirely separate from any customer host OS. |
| V-206552 | Cosmos DB does not expose the capability to execute external executables from the database service. |
| V-206557 | Authentication secrets are never transmitted in cleartext; endpoint access is restricted to TLS 1.2+ (minimalTlsVersion=Tls12) and key-based requests use HMAC signatures. |
| V-206558, V-206560, V-206603, V-263619 | Azure Govcloud uses DoW-approved CAs. |
| V-206561 | Cosmos DB does not echo passwords or secret keys during authentication; secrets are managed only via the management plane. |
| V-206562, V-206639, V-206640, V-206641 | Cosmos DB uses FIPS-validated platform cryptographic modules (transport/at-rest encryption; digital signature, hashing, confidentiality operations respectively). |
| V-206564 | Cosmos DB separates management-plane (portal/ARM) functionality from data-plane (SDK/SQL API) functionality. |
| V-206568 | The Cosmos DB platform fails to a secure state on init/shutdown; Microsoft operates the platform for availability and integrity. |
| V-206569 | The Cosmos DB platform preserves fault telemetry and supports quick failover/recovery (enableAutomaticFailover=True on this account). |
| V-206571 | Cosmos DB security functions (authentication, authorization, encryption, auditing) are implemented in the platform layer, isolated from application data functions. |
| V-206573 | Cosmos DB accounts are isolated by the Azure platform; no shared customer-accessible system resources provide unintended information transfer between accounts. |
| V-206578 | Application-layer rule: error message sanitization. |
| V-206594 | Audit record timestamps are recorded in UTC by the Cosmos DB platform. |
| V-206606 | Cosmos DB processes execute in isolated platform-managed execution domains separating each account. |
| V-206610 | Azure Cosmos DB is fully managed; replaced components are removed by the platform during automatic updates. |
| V-206611 | Azure Cosmos DB is fully managed; Microsoft applies security updates to the underlying platform within its patching obligations. |
| V-263621 | Cosmos DB platform clocks synchronize to Microsoft's authoritative time infrastructure; audit records carry synchronized UTC timestamps. |
| V-263622 | Cosmos DB platform clocks are synchronized against Microsoft's authoritative time source by the service. |
| V-278969 | Azure Cosmos DB is a fully managed service; Microsoft maintains and patches the service to a current supported version. provisioningState=Succeeded on current SLA version. |

### Static `not_applicable`

| Group ID | Comment |
|---|---|
| V-206555 | No password-based authentication to the DBMS is employed. Authentication uses either machine-generated account keys (not user-selected passwords) or Entra ID. If password-based authentication is later introduced, review with Entra ID policy. |
| V-206556 | No password-based authentication to the DBMS is employed; there are no user passwords for the DBMS to hash or store. |
| V-206575, V-206576, V-206577 | Application-layer input validation. Cosmos DB does not provide dynamic execution surfaces for the customer beyond documented stored procedures. |
| V-206582, V-206583 | Security labels are not required for this system. |
| V-233495 | Not a classified system. |
| V-263606 | Cosmos DB is a fully managed PaaS; the customer cannot install software or firmware components on the DBMS platform. |
| V-263610 | No password-based authentication is employed. Account keys are machine-generated 256-bit random secrets, not user-selected passwords; compromised secret rotation is available via key regeneration in the management plane. |
| V-263611 | No password-based authentication is employed; no commonly-used password list applies. Account keys are regenerated by the customer in the management plane as needed. |
| V-263612 | No password-based authentication is employed; suspected compromise of account keys is addressed by regenerating keys in the management plane, not by a password list. |
| V-263613 | No user-selected passwords exist; account keys are machine-generated random secrets not checked against password lists. |
| V-263614 | No password-based authentication is employed; no user account recovery process exists at the DBMS to require a new DBMS password. |
| V-263615 | No user-selected passwords exist; the DBMS imposes no password length/character restrictions. |
| V-263616 | No user-selected passwords exist; password-strength tooling applies to the identity provider (Entra ID), not the DBMS. |

### Pre-flagged for human review (stage 02: propose these, stage 03 confirms)

| Group ID | Status | Comment |
|---|---|---|
| V-206559 | not_reviewed | Human review (PKI): the DBMS stores no customer PKI private keys; CMK (if adopted) resides in Azure Key Vault. Confirm organization requirements. |
| V-206572 | not_reviewed | Human review: confirm data-transfer policy enforcement (network ACLs, restricted containers) meets requirements. |
| V-206600 | not_reviewed | Human review: confirm reauthentication circumstances (e.g., Entra ID session policies) meet organization requirements. |
| V-206601 | open | Account keys (cached authenticators) never expire and can be cached indefinitely by clients; no cache lifetime is enforceable. Use Entra ID tokens, which expire per policy, instead of keys. |
| V-206609 | not_reviewed | Human review (application layer): confirm invalid input handling is predictable and documented. |

### I. Crypto-module / commercial-of-the-shelf rules

Rules: V-206557, 206582, 206583, 206639–641, 263610–263616 …

| Default | Comment anchor |
|---|---|
| NAF | "FIPS-validated platform modules / machine-generated keys" |
| N-A | "No user-selected passwords exist; account keys are random 256-bit secrets" |
| GC CA note | "Azure Govcloud uses DoD-approved CAs" |

If the account type or data classification changed (e.g., leaving GovCloud),
these need re-evaluation, not auto-NAF.

## Interaction contract (the agent)

1. **Baseline first**: gauge all 9 key events; emit a summary of the settings
   before per-rule evaluation.
2. **Silent passes**: rules fully decided by a key event + static reasoning
   never need user input.
3. **Ask only when**:
   - ambiguous evidence (contradictory settings, empty-but-expected lists),
   - a classification change would flip a crypto/commercial rule,
   - no databases present (decide open vs N/A),
   - non-default organization requirement (session reauth policy, CA list, etc.)
4. **Every status change** must quote the exact snapshot path/value used.
5. **Recording decisions**:
   - deterministic/evidence-driven → update a resolver rule in `rules\rules.md`
     (add to the decision table) or a new key event,
   - one-off override → add under "Organization overrides" below with
     `group_id`, chosen status, reason, and a review-next date.
6. **Never** introduce a status without a comment; comments must be human-readable
   justifications, not placeholders.

## Organization overrides (user decisions, newest wins)

Empty by default. Supersede decision tables above when not empty.

| Group ID(s) | Status | Reason | Decided | Notes |
|---|---|---|---|---|
| — | — | — | — | — |
