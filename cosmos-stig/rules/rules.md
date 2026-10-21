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
206635, 233501… (full watchlist: `disableLocalAuth` dependents in rules-map).

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
