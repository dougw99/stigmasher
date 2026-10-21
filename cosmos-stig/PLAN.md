# TODO — ICM restructure (done: layout + contracts + compose script)

The pipeline is now ICM-style: numbered stage folders, markdown contracts, one
agent, plain-text handoffs, and only two mechanical scripts.

## Remaining work
1. Exercise stage 02's AI evaluation end-to-end with a real snapshot; tighten
   `rules\rules.md` decision tables wherever an evaluation row lacked a clean
   evidence citation.
2. Validate `compose_checklist.ps1` output in STIG Viewer 3 (parse + load).
3. Decide what to do with `SV3_CKLB_1_0_JSON_SCHEMA.json` — use as stage 05
   validation reference or drop.
4. Optional: per-run artifact folders (`_runs\<timestamp>\`) if we need
   historical assessments alongside the latest one.
