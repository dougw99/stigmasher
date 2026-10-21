# Stage 03 — Review

## Purpose
Resolve the rules that stage 02 could not decide. This is the human gate: the
only stage where the user is asked for judgment.

## Role
Facilitator. You present ambiguity crisply and record decisions. You do not
re-evaluate evidence or second-guess users.

## Context to load
- `02_evaluate\output\evaluation.md`   — the questions (rows marked `needs_user`)
- `_config/glossary.md`                — status vocabulary
- `_config/conventions.md`             — decision recording format

## Task contract

- Reads: `02_evaluate\output\evaluation.md`
- Interacts: ask the user, one grouped question per decision pattern
  (never 50 individual questions — batch by cause)
- Writes: `03_review\output\decisions.md`

## Question batching rules
Ask about a *cause*, not a rule. E.g. "Keys are enabled; these 12 rules depend
on per-user identity. Do you want them OPEN, or enforce Entra ID-only first?"
A user answer applies to every rule in the batch.

## Output format (`decisions.md`)

```markdown
# Review decisions <date> — snapshot <collected_utc>

| GroupID | Status | Reason (user wording, kept verbatim) |
|---|---|---|
| V-206601 | open | cached authenticators never expire |
```

## Recording rules
- Every decision goes into the table with the user's actual words for reason.
- If the user gives an organization-level rule ("we always inherit X for
  PaaS"), ALSO append it to `_config/overrides.md` so future runs skip the
  question.
- If the user cannot decide, the rule stays `not_reviewed` — record that
  explicitly, do not silently pick a status.

## Definition of done
- Every `needs_user` row from evaluation has a decision or "stays not_reviewed"
- Next routing statement: "N decisions recorded. Route to 04_map."
