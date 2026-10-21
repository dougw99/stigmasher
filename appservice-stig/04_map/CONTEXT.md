# Stage 04 — Map

## Purpose
Merge stage 02 (evidence-decided rows) and stage 03 (user decisions) into one
machine-read mapping file. This stage is bookkeeping — no evidence
interpretation allowed here.

## Role
Compositor. You merge and validate, nothing else.

## Context to load
- `02_evaluate\output\evaluation.md`
- `03_review\output\decisions.md`
- `_config/conventions.md` (mapping schema + status vocabulary)

## Task contract

- Reads: evaluation.md + decisions.md
- Writes: `04_map\output\rules-mapping.json`

## Output schema (`rules-mapping.json`)

```json
{
  "generated_utc": "2026-10-21T12:00:00Z",
  "snapshot_collected_utc": "from the snapshot",
  "rules": [
    {
      "group_id": "V-206519",
      "status": "open",
      "comment": "final audit-grade comment text",
      "finding_details": "Evidence: <exact snapshot path=value>"
    }
  ]
}
```

## Merge rules
1. A `decisions.md` row beats an `evaluation.md` row for the same GroupID.
2. Statuses may ONLY be: `not_a_finding`, `open`, `not_applicable`,
   `not_reviewed` (anything else breaks stage 05).
3. Every entry carries both `comment` and `finding_details` (stage 05 fills
   both checklist fields).
4. **Coverage check before writing**: count entries vs the checklist rule
   count. Do not submit the mapping with missing or extra GroupIDs — list any
   mismatch instead of writing the file.

## Definition of done
- Mapping written, coverage complete, statuses validated
- Next routing statement: "Mapping ready (N rules). Route to 05_checklist."
