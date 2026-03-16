# Ralph Replan Instructions

You are running the replanning stage of Ralph. This stage updates the plan only.

## Inputs

- PRD: `__PRD_FILE__`
- Progress log: `__PROGRESS_FILE__`
- Current active phase hint: `__ACTIVE_PHASE__` (can be empty)

## Goals

1. Observe the latest outcomes from the previous iteration.
2. Replan the next phase/task queue in `prd.json`.
3. Record the replanning decision in `progress.txt`.

## Replanning Rules

1. Read `prd.json` and `progress.txt` first.
2. If `phases` is missing in `prd.json`, add it:
   - Create 2-4 phases grouped by dependency order.
   - Add `phaseId` on every story.
   - Use phase statuses: `planned`, `in_progress`, `done`, `blocked`.
3. Keep exactly one active phase at a time:
   - First non-`done` phase should be `in_progress` unless blocked.
   - Completed phases should be `done`.
4. Reorder upcoming work for the next execution step:
   - Pending stories in the active phase must have the highest priorities.
   - Do not reorder completed (`passes: true`) stories.
5. If repeated failures are evident, set current phase to `blocked` and add a focused unblocker story.
6. Append a short "Replan" entry to `progress.txt` with:
   - what you observed,
   - what changed in `prd.json`,
   - what story should execute next.

## Guardrails

- Do NOT implement product code in this stage.
- Do NOT create commits.
- Only edit planning artifacts (`prd.json`, `progress.txt`) unless absolutely necessary.
- Keep changes minimal and deterministic.
