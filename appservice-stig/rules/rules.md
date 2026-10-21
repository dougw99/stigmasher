# Rule Evaluation Guide — Azure App Service (Application Server SRG)

Working guide for the AI agent performing the App Service STIG assessment,
same shape as `cosmos-stig\rules\rules.md`: review the snapshot against the
decision tables below, set statuses, and surface only genuinely ambiguous
rules to the user (stage 03).

STIG: Application_Server_SRG — 137 rules (V-204708…V-204834, V-240925,
V-263549…V-263556, V-278959…V-278967). The SRG is written for a generic
application server; most rules reduce to a handful of Azure App Service
setting groups plus platform facts, with an org/tenant layer (identity,
redundancy, data tagging) decided in stage 03 or `_config\overrides.md`.

Tracker statuses available in the checklist: `not_a_finding`, `open`,
`not_applicable`, `not_reviewed` (leave for human).

## Snapshot reference (evidence inputs)

The snapshot (`snapshot\azure_snapshot.json`) contains:

| Field | Used for |
|---|---|
| `collected_utc`, `source`, `subscription`, `resource_id` | evidence provenance quoted in comments |
| `site` | id, kind, state, tier — resource existence, plan facts |
| `site.config.httpsOnly` | HTTP→HTTPS enforcement (K1) |
| `site.config.minTlsVersion` | inbound TLS floor (K1) |
| `site.config.scmMinTlsVersion` | SCM/management endpoint TLS floor (K2) |
| `site.config.ftpsState` | FTP/FTPS state (K3) |
| `site.config.http20Enabled`, `webSocketsEnabled`, `remoteDebuggingEnabled`, `alwaysOn`, `healthCheckEnabled` | feature exposure checks |
| `site.identity` | managed identity types (K6) |
| `network.ipSecurityRestrictions` | inbound ACL evidence (K5) |
| `network.virtual_network_subnet_id` | VNet-integration (K5) |
| `diagnostic_settings[]` with `logs[]` `{category, enabled}` and `work_spaceId` | audit logging rules (K4) |
| `platform_facts` (static block emitted by collector) | PaaS/managed-primitives reasoning (table P) |

Never treat a missing field as a pass: missing evidence is `not_reviewed`
and is quoted as "not present in snapshot".

Never treat a missing field as a pass; missing evidence = `not_reviewed`
plus the named gap. Unknown *app-level* behavior (what code does with
sessions, passwords, LDAP, mobile code) is also `not_reviewed` with the
named gap — the platform snapshot cannot prove it.

## The 8 key events (decide once, reuse)

| # | Key event | Deciding evidence | Outcome |
|---|---|---|---|
| K1 | Inbound transport locked to approved TLS | `httpsOnly == true` AND `minTlsVersion` in ["1.2","1.3"] AND `scmMinTlsVersion` in ["1.2","1.3"] | All transmission-crypto rules NAF (with `platform_facts` TLS quote when needed) |
| K2 | FTP disabled | `ftpsState == "Disabled"` | Nonsecure-protocol rules NAF; FTPS enabled ("ftpOnly"/"sftpOnly") → quote allowed protocols; FTP unencrypted allowed ("allAllowed") → OPEN |
| K3 | Dev endpoints closed | `remoteDebuggingEnabled == false` | Debug-exposure rules NAF |
| K4 | Audit pipeline to central logs | any diagnostic-setting entry with ≥1 enabled log category AND `workspaceId` set | Audit generation rules NAF per category that is on |
| K5 | Network exposure restricted | `publicNetworkAccess == "Disabled"` OR non-default `ipSecurityRestrictions` present OR `virtual_network_subnet_id` set | Exposure rules NAF; public-with-no-ACL → OPEN |
| K6 | No app-managed credentials in the platform | `site.identity` has managed identity AND/OR EasyAuth config present with an Entra ID provider | Password-storage/LDAP rules judged against gap named below |
| K7 | File-audit enabled | `AppServiceFileAuditLogs` enabled AND `AppServiceIPSecAuditLogs` enabled | Content-change / IPSec-audit rules NAF |
| K8 | Static platform facts block present | `platform_facts` present in snapshot | Table P rules NAF with the quoted platform reasoning |

Static `platform_facts` (emitted by collector, never re-derived):
- App Service is a fully managed Microsoft platform service (PaaS): Microsoft
  maintains and patches the underlying Windows/Linux images and runtime
  stacks; users cannot touch OS-level file permissions, log-tool binaries,
  or the platform TLS/provider stack.
- Inbound ports 80/443 (+FTP per K3) are the only listener ports; management
  goes exclusively over HTTPS ARM (`*.azure.com`; SCM/Kudu via HTTPS).
- All persisted state (app disk, platform storage, service metadata) is
  encrypted at rest by the platform; CMK is available for dedicated premium
  tiers via Key Vault.
- Log timestamps are UTC; platform components are NTP-synchronized.
- Sign-out is provided by the Azure management portal; sessions on Azure's
  management plane are enforced/terminated by Entra ID + ARM per tenant.

## Priority ladder (applies when rules appear to conflict)

1. **User overrides** (`_config\overrides.md`) always win.
2. **Collection gaps** (field absent / diagnostics list empty) stay
   `not_reviewed`, never OPEN — unless a sibling setting proves the control
   is absent, then OPEN with the contradiction quoted.
3. **App-level unknowns** (code-managed sessions, passwords, LDAP, mobile
   code, data tags) stay `not_reviewed` — the platform snapshot cannot prove
   them; stage 03 asks the user only when the org view matters.
4. **Static platform facts** (table P, table X) never flip on a snapshot
   field; re-review only on tier/architecture change (e.g., moving to
   App Service Environment, self-hosting, IC modem phased out).

## Decision tables

### P. Platform/managed-service facts (static NAF) — 16 rules

Never depend on snapshot settings; decided by `platform_facts`:

| Rules | Status | Comment anchor |
|---|---|---|
| V-204740, V-204741, V-204742, V-204743, V-204822, V-204823, V-204834, V-278967 | `not_a_finding` | "Microsoft-managed platform: OS/runtime patching, signed updates, rollback, supported stacks are platform responsibilities (platform_facts)" |
| V-204770, V-204771, V-204812, V-204813 | `not_a_finding` | "Platform storage encrypted at rest; CMK available (platform_facts)" |
| V-204767, V-204769, V-204821, V-204772 | `not_a_finding` | "Deployment slots / platform fault behavior encapsulate rollback + fail-secure; ARM mgmtplane input validation is platform code" |
| V-204776, V-204778, V-204779 | `not_a_finding` | "Signed platform binaries/sign-out/logout paths are platform UI/portal responsibilities (platform_facts)" |

### T. Transport & TLS (depends on K1) — 10 rules

| Rules | Evidence | Status |
|---|---|---|
| V-204816, V-204817, V-204818, V-204819, V-204820 | K1 satisfied | `not_a_finding` — quote `httpsOnly`, `minTlsVersion`, `scmMinTlsVersion`, platform cipher/FIPS fact for export-ciphers |
| V-204758 | K1 satisfied | `not_a_finding` — "TLS floor >= 1.2 per platform settings; Windows App Service runs on FIPS-validated provider stack (platform_facts)" |
| V-204709, V-204710 | K1 satisfied (management plane is HTTPS ARM) | `not_a_finding` |
| (same set) | `httpsOnly != true` or TLS floor below 1.2 | `open` — name the field and current value |
| V-204752 | K1 satisfied | `not_a_finding` — "all HTTP redirected to HTTPS; no cleartext credential transmission path" |
| V-204757 | Always `not_a_finding` | "auth feedback masking is enforced by the platform UIs; no setting exposes passwords" |

### E. FTP / ports / remote access (K2, K3) — 7 rules

| Rules | Evidence | Status |
|---|---|---|
| V-204744 | K2 satisfied (FTP disabled explicit) | `not_a_finding` — quote `ftpsState:"Disabled"` |
| V-204744 | `ftpsState` == "sftpOnly" → FTPS-only | `not_a_finding` — quote allowed protocols; FTP unencrypted ("allAllowed") → `open` |
| V-204761, V-204782, V-204783 | Remote mgmt = ARM HTTPS only; immediate-disconnect capability inherent via platform | `not_a_finding` (platform_facts) |
| V-204762 | Mutually authenticate connecting gateways — app/architecture specific | `not_reviewed` unless org override says a gateway/proxy fronts the site: then K5 + TLS evidence decides |
| V-263553 | Nonlocal maintenance separation — no separate maintenance path exists on this platform | `not_a_finding` / `not_applicable` — "no nonlocal maintenance session path is exposed; mgmt is the same HTTPS ARM plane" |
| V-204796 | Config-change restrictions = ARM RBAC on this resource profile (deployment + config changes resource-authorized) + org RBAC policy in stage 03 | `not_reviewed`-default until org RBAC answer; K5 evidence does NOT prove this |

### D. Audit & logging (depends on K4/K7) — 47 rules

Biggest group. Decided by which applicable categories are ON; every finding
quotes the exact category + workspaceId.

**Generation / content** (V-204711, V-204717, V-204719, V-204720, V-204721,
V-204722, V-204723, V-204724, V-204725, V-204726, V-204727, V-204731,
V-204785, V-204824, V-204825, V-204826, V-204827, V-204828, V-204829,
V-204830):

| Evidence | Status |
|---|---|
| Required categories enabled | `not_a_finding` — per rule, name the category covering it (HTTPLogs→site access; AuditLogs/IPSecAuditLogs→auth & policy; FileAuditLogs→file changes; FailedRequests→outcomes; AppLogs/Console/Platform logs→app-startup & runtime identities) |
| Any required category missing/disabled | `open` — name the missing category(s) |
| No diagnostic_settings at all | `not_reviewed` — "no diagnostic settings in snapshot" |

**Pipeline / central-handling** (V-204716, V-204718, V-204738, V-204739,
V-204759, V-204788, V-204789, V-204833, V-204790, V-204791, V-204728,
V-263550, V-204797):

| Evidence | Status |
|---|---|
| K4 satisfied AND `overrides.md` records a central/SIEM destination (or canned answer in stage 03) | `not_a_finding` — quote workspace + org SIEM |
| K4 satisfied, no SIEM record | `not_reviewed` — "Log Analytics destination proven; SIEM/log-reduction/backup/alert delegation NOT evidenced" |
| K4 gap | `open` (settings exist but misdirected) or `not_reviewed` (nothing collected) |

**Log protection** (V-204732, V-204733, V-204734, V-204735, V-204736,
V-204737): always `not_a_finding` — "platform_fact: logs persist in
platform-held, tenant-RBAC-gated storage; no OS filesystem/user-credential
path exists".

**Error tracking** (V-204773, V-204774, V-204775): app-level message content
→ `not_reviewed` with named gap ("what the app logs is outside the platform
snapshot; stage 03 question"); platform component errors → `not_a_finding`
(platform_fact: platform error paths do not emit secrets).

**Time** (V-204792, V-204793, V-204794, V-204795, V-263556): always
`not_a_finding` — platform_fact UTC/NTP quote.

### S. Session & app-level behavior (K6) — 13 rules

| Rules | Evidence | Status |
|---|---|---|
| V-204763, V-204764, V-204765, V-204766, V-204777 | Management-plane sessions (Azure portal/ARM) are governed by platform_fact + Entra; site-hosted app sessions cannot be proven from the snapshot | mgmt angle: `not_a_finding` (platform_fact + Entra quote); app angle per rule: `not_reviewed` — name "app-level session handling not evidenced" (stage 03 asks only if the site hosts stateful privileged sessions per org view) |
| V-204751 | EasyAuth present + K6, OR app uses no password auth (decide in stage 03) | `not_a_finding` — "authentication delegated to Entra ID; app does not store password material" (quoted) OR `not_reviewed` — "password handling inside app code unproven" |
| V-204753 | App uses LDAP? | `not_reviewed` default — "no LDAP config in snapshot; if app integrates LDAP, org must confirm LDAPS"; `open` only if evidence contradicts |
| V-204749 | SOAP/WS-Security used? | `not_reviewed` default — same shape as 753 |
| V-204760 | Mobile code: app-content concern | `not_reviewed` — "app content standards are an org application-security matter" |
| V-204712, V-278961, V-278966, V-278964 | App/tenant-level authz architecture (RBAC/ABAC/IDS) | `not_reviewed` — "depends on app design + org ID governance; stage 03" |

### X. Labeling / attribute boundary (static or org) — 7 rules

V-204780, V-204781, V-278959, V-278960, V-278962, V-278963, V-278965 →
`not_a_finding` by default with boundary reasoning: "Azure App Service is a
compute service; it does not process/import security-attribute or PII-tag
metadata as part of transmitted/rested system content — the classification
binding happens in tenant/app code and is an org responsibility."

Re-review once per architecture change (same as cosmos PaaS rules), not per
run. If the org asserts attribute-processing requirements, move these to
stage-03 questions and record the decision in overrides.md.

### I. Identity management plane (org + tenant evidence) — 7 rules

V-204745, V-204746, V-204747, V-204748, V-204784, V-263551, V-263552:

| Evidence | Status |
|---|---|
| K6 present (Entra-based auth exists) but NO MFA/ICAM record in overrides | `not_reviewed` — "Entra used (quote); MFA/conditional-access/not-local-console assertions are TENANT-LEVEL and not in snapshot" |
| overrides.md records Entra CA/MFA for privileged + no local console | `not_a_finding` — quote the override |
| K6 absent (no Entra evidence at all) | `open` with named gap |

### L. Org/tenant decisions (must be resolved in stage 03; record in overrides) — 27 rules

Default status for all of these in stage 02 is `not_reviewed` with the
specific gap named; stage 03 turns them into decisions.

- **A Sign-in banner** — V-204713, V-204714.
- **B MFA/PIV/CAC/FICAM on the mgmt plane** — V-204800, V-204801, V-204806,
  V-204807, V-204808, V-204809.
- **C Account lifecycle** — V-204750, V-204798, V-204804, V-263549.
- **D Redundancy/HA** — V-204768, V-204814, V-204815 (MAC/confidentiality gate; DoS safeguards = platform + org edge: App GW/FrontDoor/WAF).
- **E PKI trust** — V-204754, V-204755, V-204756, V-204805, V-204811,
  V-204831, V-204832, V-240925 (NSA crypto, only when classified),
  V-263554, V-263555.
- **F Org-defined session/repudiate values** — V-204708, V-204715.

For D/E: if PKI/CAC is not used at all for this resource (typical), the PKI
rules are `not_applicable` — decided in stage 03, not silent.

## Interaction contract (the agent)

1. **Baseline first**: tabulate K1–K7 evidence before per-rule evaluation;
   emit the key-event summary.
2. **Silent passes**: table P, T (when decided), E, log-protection subset,
   X always pass without user input.
3. **Ask only when**:
   - a table-O org value is genuinely unknown (banner, MFA, MAC level, PKI),
   - K4 category is deemed required by the org beyond HTTP/audit/file bases,
   - app-level gaps (session, LDAP, mobile code) matter to the org.
4. **Every status change** must quote the exact snapshot path/value.
5. **Never** introduce a status without a comment; comments must be
   human-readable justifications, not placeholders.

## Organization overrides (user decisions, newest wins)

Empty by default. Supersede decision tables above when not empty.

| Group ID(s) | Status | Reason | Decided | Notes |
|---|---|---|---|---|
| — | — | — | — | — |
