# Rule Evaluation Guide — Azure App Service (STIG)

TODO: This file is the working guide for the AI agent performing the App
Service STIG assessment. It must be populated before the first real run,
in the same form `cosmos-stig\rules\rules.md` uses:

1. **Key events** — the handful of settings almost every rule reduces to,
   decided once per run from snapshot evidence (decide facts, then reuse).
   Cosmos used: local auth state, network exposure, TLS, CMK, diagnostics
   pipeline, RBAC state. The exact set differs per STIG — derive it from the
   checklist's check_content clauses.
2. **Snapshot reference** — which evidence fields the collector provides and
   what each is used for. Same table as in the cosmos version.
3. **Decision tables** — grouped per evidence area with concrete
   evidence | status rows. Never "usually NAF"; always cite the deciding field.
4. **Priority ladder** — user overrides > open-contradictions > collection
   gaps stay `not_reviewed` > non-data rules excluded by the empty-state.
5. **Interaction contract** — silent passes, when to ask the user (stage 03),
   evidence path in every finding_details, decisions recorded to
   `_config\overrides.md` when organization-level.

Do not run stage 02 until this file has at least the key events and one
decision table per evidence area. A blank guide is the riskiest artifact in
the repo — nothing here is auto-generated.
