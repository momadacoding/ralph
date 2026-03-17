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
4. Handle unresolved product decisions explicitly so execution does not guess.

## Replanning Rules

1. Read `__SOURCE_PRD_FILE__` first when available, then read `prd.json` and `progress.txt`.
2. Treat source PRD markdown as the source of truth for goals/scope; treat `prd.json` as execution state.
3. Detect unresolved decision blockers before prioritizing implementation:
   - Check source PRD `Open Questions` (when available), story/phase notes, and latest progress entries.
   - If an unanswered decision blocks the next story, set the current phase to `blocked`.
   - Add or update one focused unblocker story at the top priority of that phase (reuse existing; do not create duplicates).
4. When a blocking decision is resolved (recorded in progress/notes), reflect it in affected stories and resume execution:
   - Update acceptance criteria, notes, or priorities as needed.
   - Move the phase from `blocked` back to `in_progress`.
5. If `phases` is missing in `prd.json`, add it:
   - Create 2-4 phases grouped by dependency order.
   - Add `phaseId` on every story.
   - Use phase statuses: `planned`, `in_progress`, `done`, `blocked`.
6. Keep exactly one active phase at a time:
   - First non-`done` phase should be `in_progress` unless blocked.
   - Completed phases should be `done`.
7. Reorder upcoming work for the next execution step:
   - Pending stories in the active phase must have the highest priorities.
   - Do not reorder completed (`passes: true`) stories.
8. If repeated failures are evident, set current phase to `blocked` and add a focused unblocker story.
9. If `__SOURCE_PRD_FILE__` is empty/unreadable, continue with fallback (`prd.json` + `progress.txt`) and note the fallback in `progress.txt`.
10. Append a short "Replan" entry to `progress.txt` with:
   - what you observed,
   - what changed in `prd.json`,
   - what story should execute next,
   - whether execution is blocked on a user decision.

## Guardrails

- Do NOT implement product code in this stage.
- Do NOT create commits.
- Only edit planning artifacts (`prd.json`, `progress.txt`) unless absolutely necessary.
- Keep changes minimal and deterministic.
