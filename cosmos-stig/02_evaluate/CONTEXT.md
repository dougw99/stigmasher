# Stage 02 — Evaluate

## Purpose
Interpret the evidence snapshot against the STIG rule knowledge and produce a
plain-text first-pass evaluation. Judgment lives here, in the AI, guided by markdown.

## Role
Auditor. Evidence-driven, conservative. You evaluate; you do not invent
statuses without an evidence path; you defer ambiguity to stage 03.

## Context to load (nothing else)
- `rules/rules.md`            — key events + decision tables (the core logic)
- `_config/overrides.md`      — organization decisions that supersede tables
- `_config/glossary.md`       — legal status vocabulary
- `snapshot\azure_snapshot.json` — the evidence

## Task contract

- Reads: `snapshot\azure_snapshot.json`, `rules/rules.md`, `_config/overrides.md`
- Writes: `02_evaluate\output\evaluation.md`

## Output format (`evaluation.md`)

```markdown
# Evaluation <collected_utc of snapshot>

## Key-event state
| Event | State | Evidence (path=value) |
|---|---|---|
| K1 local_auth_disabled | true/false | account.properties.disableLocalAuth=true |

## Per-rule first pass
| Rule (GroupID) | Proposed status | Decided by | Evidence / question for 03 |
|---|---|---|---|
| V-206519 | open | Table A + K2 | key-auth rule requiring session limits; keys enabled |
```

## Rules for this stage
- One key-event table first, then one row per rule. No prose paragraphs per rule.
- Statuses: `not_a_finding`, `open`, `not_applicable`, or `needs_user`.
- `needs_user` is the ONLY way to hand a rule to stage 03 — list exactly why.
- Every proposed status must cite a snapshot `path=value` or a
  `rules/rules.md` table row. Never both, never neither.
- Draft a working comment for each rule (audit-grade phrasing; stage 04 copies
  it into the checklist verbatim).
- Overrides in `_config/overrides.md` always beat decision tables.

## Definition of done
- Every rule in the checklist has a row, and every row has a status or an
  explicit question
- Next routing statement: "X rules are decisions-ready, Y need the user.
  Route to 03_review."
