# Ralph Agent Instructions

## Overview

Ralph is an autonomous AI agent loop that runs AI coding tools (Amp, Claude Code, or Codex) repeatedly until all PRD items are complete. Each iteration is a fresh instance with clean context.

## Commands

```bash
# Run the flowchart dev server
cd flowchart && npm run dev

# Build the flowchart
cd flowchart && npm run build

# Run Ralph with Amp (default)
./ralph.sh [max_iterations]

# Run Ralph with Claude Code
./ralph.sh --tool claude [max_iterations]

# Run Ralph with Codex
./ralph.sh --tool codex [max_iterations]

# Branch strategy options
./ralph.sh --branch-strategy reuse-current [max_iterations]
./ralph.sh --branch-strategy create-from-current [max_iterations]
./ralph.sh --branch-strategy create-from-base --base-branch develop [max_iterations]

# Disable replanning stage (not recommended)
./ralph.sh --no-replan [max_iterations]

# Replan every 3 iterations
./ralph.sh --replan-every 3 [max_iterations]

# Combined example: Codex + current branch + periodic replanning
./ralph.sh --tool codex --branch-strategy reuse-current --replan-every 3 18
```

## Key Files

- `ralph.sh` - The bash loop that spawns fresh AI instances (supports `--tool`, `--branch-strategy`, `--base-branch`, and replan controls)
- `REPLAN.md` - Replanning-stage prompt used before each execution iteration
- `prompt.md` - Instructions given to each AMP instance
-  `CLAUDE.md` - Instructions given to each Claude Code instance
- `CODEX.md` - Instructions given to each Codex instance
- `prd.json.example` - Example PRD format
- `flowchart/` - Interactive React Flow diagram explaining how Ralph works

## Flowchart

The `flowchart/` directory contains an interactive visualization built with React Flow. It's designed for presentations - click through to reveal each step with animations.

To run locally:
```bash
cd flowchart
npm install
npm run dev
```

## Patterns

- Each iteration spawns a fresh AI instance (Amp, Claude Code, or Codex) with clean context
- Completion is determined from `prd.json` (`userStories[].passes`), not a special token in model output
- For Codex, use `codex exec` for Ralph runs because the interactive CLI expects a TTY
- Memory persists via git history, `progress.txt`, and `prd.json`
- Stories should be small enough to complete in one context window
- Always update AGENTS.md with discovered patterns for future iterations
- Branch/worktree preparation belongs in `ralph.sh`; prompt files should not independently switch branches
- Prefer phase-based planning (`phases` + `phaseId`) so each iteration executes within a single active phase
- Replanning should update `prd.json`/`progress.txt` first, then execution prompt should implement one story
- Use `--replan-every` to reduce planning cost on long runs while keeping periodic replanning checkpoints
