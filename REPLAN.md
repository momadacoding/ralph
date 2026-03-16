# Ralph Replan Instructions

You are running the replanning stage of Ralph. This stage updates the plan only.

## Inputs

- PRD: `__PRD_FILE__`
- Source PRD markdown: `__SOURCE_PRD_FILE__` (can be empty)
- Progress log: `__PROGRESS_FILE__`
- Current active phase hint: `__ACTIVE_PHASE__` (can be empty)

## Goals

1. Observe the latest outcomes from the previous iteration.
2. Replan the next phase/task queue in `prd.json`.
3. Record the replanning decision in `progress.txt`.

## Replanning Rules

1. Read `__SOURCE_PRD_FILE__` first when available, then read `prd.json` and `progress.txt`.
2. Treat source PRD markdown as the source of truth for goals/scope; treat `prd.json` as execution state.
3. If `phases` is missing in `prd.json`, add it:
   - Create 2-4 phases grouped by dependency order.
   - Add `phaseId` on every story.
   - Use phase statuses: `planned`, `in_progress`, `done`, `blocked`.
4. Keep exactly one active phase at a time:
   - First non-`done` phase should be `in_progress` unless blocked.
   - Completed phases should be `done`.
5. Reorder upcoming work for the next execution step:
   - Pending stories in the active phase must have the highest priorities.
   - Do not reorder completed (`passes: true`) stories.
6. If repeated failures are evident, set current phase to `blocked` and add a focused unblocker story.
7. If `__SOURCE_PRD_FILE__` is empty/unreadable, continue with fallback (`prd.json` + `progress.txt`) and note the fallback in `progress.txt`.
8. Append a short "Replan" entry to `progress.txt` with:
   - what you observed,
   - what changed in `prd.json`,
   - what story should execute next.

## Guardrails

- Do NOT implement product code in this stage.
- Do NOT create commits.
- Only edit planning artifacts (`prd.json`, `progress.txt`) unless absolutely necessary.
- Keep changes minimal and deterministic.
