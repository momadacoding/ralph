#!/bin/bash
# Ralph Wiggum - Long-running AI agent loop
# Usage: ./ralph.sh [--tool amp|claude|codex] [--branch-strategy reuse-current|create-from-current|create-from-base] [--base-branch main] [--no-replan] [--replan-prompt REPLAN.md] [--replan-every 1] [max_iterations]

set -e
set -o pipefail

print_usage() {
  cat <<EOF
Usage: ./ralph.sh [options] [max_iterations]

Options:
  --tool <amp|claude|codex>               Select AI tool (default: amp)
  --branch-strategy <strategy>            Branch behavior:
                                          - create-from-base (default)
                                          - create-from-current
                                          - reuse-current
  --base-branch <branch>                  Base branch for create-from-base (default: main)
  --replan-prompt <path>                  Prompt file for replan step (default: REPLAN.md)
  --replan-every <n>                      Run replan every n iterations (default: 1)
  --no-replan                             Disable per-iteration replan step
  -h, --help                              Show this help message
EOF
}

is_main_branch() {
  local branch_name="$1"
  [[ "$branch_name" == "main" || "$branch_name" == "master" ]]
}

current_git_branch() {
  git symbolic-ref --short -q HEAD || true
}

resolve_source_prd_file() {
  local source_path=""
  local resolved_path=""

  if [ ! -f "$PRD_FILE" ]; then
    echo ""
    return
  fi

  source_path="$(jq -r '.sourcePrdPath // empty' "$PRD_FILE" 2>/dev/null || true)"
  if [ -z "$source_path" ]; then
    echo ""
    return
  fi

  case "$source_path" in
    /*)
      resolved_path="$source_path"
      ;;
    *)
      resolved_path="$(cd "$(dirname "$PRD_FILE")" && pwd)/$source_path"
      ;;
  esac

  if [ -f "$resolved_path" ]; then
    echo "$resolved_path"
    return
  fi

  echo "Warning: sourcePrdPath is set but file was not found: $resolved_path" >&2
  echo ""
}

ensure_clean_worktree_for_switch() {
  if ! git diff --quiet --ignore-submodules -- || ! git diff --cached --quiet --ignore-submodules -- || [ -n "$(git ls-files --others --exclude-standard)" ]; then
    echo "Error: Working tree has uncommitted changes. Commit/stash changes before switching branches."
    exit 1
  fi
}

ensure_branch_context() {
  local target_branch="$1"
  local current_branch
  current_branch="$(current_git_branch)"

  case "$BRANCH_STRATEGY" in
    reuse-current)
      if [ -z "$current_branch" ]; then
        echo "Error: Cannot use --branch-strategy reuse-current from detached HEAD."
        exit 1
      fi
      if is_main_branch "$current_branch"; then
        echo "Error: reuse-current requires a non-main branch. Current branch is '$current_branch'."
        exit 1
      fi
      echo "Branch strategy: reuse-current (using '$current_branch')"
      ;;
    create-from-current)
      if [ -z "$target_branch" ]; then
        echo "Error: PRD branchName is required for --branch-strategy create-from-current."
        exit 1
      fi

      if [ "$current_branch" = "$target_branch" ]; then
        echo "Branch strategy: create-from-current (already on '$target_branch')"
        return
      fi

      ensure_clean_worktree_for_switch
      if git show-ref --verify --quiet "refs/heads/$target_branch"; then
        echo "Branch strategy: create-from-current (switching to existing '$target_branch')"
        git checkout "$target_branch"
      else
        if [ -z "$current_branch" ]; then
          echo "Error: Cannot create '$target_branch' from detached HEAD."
          exit 1
        fi
        echo "Branch strategy: create-from-current (creating '$target_branch' from '$current_branch')"
        git checkout -b "$target_branch"
      fi
      ;;
    create-from-base)
      local base_ref=""

      if [ -z "$target_branch" ]; then
        echo "Error: PRD branchName is required for --branch-strategy create-from-base."
        exit 1
      fi

      if [ "$current_branch" = "$target_branch" ]; then
        echo "Branch strategy: create-from-base (already on '$target_branch')"
        return
      fi

      ensure_clean_worktree_for_switch
      if git show-ref --verify --quiet "refs/heads/$target_branch"; then
        echo "Branch strategy: create-from-base (switching to existing '$target_branch')"
        git checkout "$target_branch"
        return
      fi

      if git show-ref --verify --quiet "refs/heads/$BASE_BRANCH"; then
        base_ref="$BASE_BRANCH"
      elif git show-ref --verify --quiet "refs/remotes/origin/$BASE_BRANCH"; then
        base_ref="origin/$BASE_BRANCH"
      else
        echo "Error: Base branch '$BASE_BRANCH' not found locally or on origin."
        exit 1
      fi

      echo "Branch strategy: create-from-base (creating '$target_branch' from '$base_ref')"
      git checkout -b "$target_branch" "$base_ref"
      ;;
    *)
      echo "Error: Unknown branch strategy '$BRANCH_STRATEGY'."
      exit 1
      ;;
  esac
}

# Parse arguments
TOOL="amp"  # Default to amp for backwards compatibility
MAX_ITERATIONS=10
BRANCH_STRATEGY="create-from-base"
BASE_BRANCH="main"
ENABLE_REPLAN=1
REPLAN_PROMPT_ARG=""
REPLAN_EVERY=1

while [[ $# -gt 0 ]]; do
  case $1 in
    --tool)
      TOOL="$2"
      shift 2
      ;;
    --tool=*)
      TOOL="${1#*=}"
      shift
      ;;
    --branch-strategy)
      if [ -z "${2:-}" ]; then
        echo "Error: Missing value for --branch-strategy."
        print_usage
        exit 1
      fi
      BRANCH_STRATEGY="$2"
      shift 2
      ;;
    --branch-strategy=*)
      BRANCH_STRATEGY="${1#*=}"
      shift
      ;;
    --base-branch)
      if [ -z "${2:-}" ]; then
        echo "Error: Missing value for --base-branch."
        print_usage
        exit 1
      fi
      BASE_BRANCH="$2"
      shift 2
      ;;
    --base-branch=*)
      BASE_BRANCH="${1#*=}"
      shift
      ;;
    --replan-prompt)
      if [ -z "${2:-}" ]; then
        echo "Error: Missing value for --replan-prompt."
        print_usage
        exit 1
      fi
      REPLAN_PROMPT_ARG="$2"
      shift 2
      ;;
    --replan-prompt=*)
      REPLAN_PROMPT_ARG="${1#*=}"
      shift
      ;;
    --replan-every)
      if [ -z "${2:-}" ]; then
        echo "Error: Missing value for --replan-every."
        print_usage
        exit 1
      fi
      REPLAN_EVERY="$2"
      shift 2
      ;;
    --replan-every=*)
      REPLAN_EVERY="${1#*=}"
      shift
      ;;
    --no-replan)
      ENABLE_REPLAN=0
      shift
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    *)
      # Assume it's max_iterations if it's a number
      if [[ "$1" =~ ^[0-9]+$ ]]; then
        MAX_ITERATIONS="$1"
      else
        echo "Error: Unknown argument '$1'"
        print_usage
        exit 1
      fi
      shift
      ;;
  esac
done

# Validate tool choice
if [[ "$TOOL" != "amp" && "$TOOL" != "claude" && "$TOOL" != "codex" ]]; then
  echo "Error: Invalid tool '$TOOL'. Must be 'amp', 'claude', or 'codex'."
  exit 1
fi
if [[ "$BRANCH_STRATEGY" != "reuse-current" && "$BRANCH_STRATEGY" != "create-from-current" && "$BRANCH_STRATEGY" != "create-from-base" ]]; then
  echo "Error: Invalid branch strategy '$BRANCH_STRATEGY'. Must be 'reuse-current', 'create-from-current', or 'create-from-base'."
  exit 1
fi
if ! [[ "$REPLAN_EVERY" =~ ^[1-9][0-9]*$ ]]; then
  echo "Error: --replan-every must be a positive integer (received '$REPLAN_EVERY')."
  exit 1
fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRD_FILE="$SCRIPT_DIR/prd.json"
PROGRESS_FILE="$SCRIPT_DIR/progress.txt"
ARCHIVE_DIR="$SCRIPT_DIR/archive"
LAST_BRANCH_FILE="$SCRIPT_DIR/.last-branch"
AMP_PROMPT_FILE="${AMP_PROMPT_FILE:-$SCRIPT_DIR/prompt.md}"
CLAUDE_PROMPT_FILE="${CLAUDE_PROMPT_FILE:-$SCRIPT_DIR/CLAUDE.md}"
CODEX_PROMPT_FILE="${CODEX_PROMPT_FILE:-$SCRIPT_DIR/CODEX.md}"
if [ -n "$REPLAN_PROMPT_ARG" ]; then
  case "$REPLAN_PROMPT_ARG" in
    /*)
      REPLAN_PROMPT_FILE="$REPLAN_PROMPT_ARG"
      ;;
    *)
      REPLAN_PROMPT_FILE="$SCRIPT_DIR/$REPLAN_PROMPT_ARG"
      ;;
  esac
else
  REPLAN_PROMPT_FILE="${REPLAN_PROMPT_FILE:-$SCRIPT_DIR/REPLAN.md}"
fi
CODEX_CMD="${CODEX_CMD:-codex exec --dangerously-bypass-approvals-and-sandbox}"

if ! git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Error: $SCRIPT_DIR is not inside a git worktree."
  exit 1
fi

cd "$SCRIPT_DIR"

CURRENT_WORKTREE_PATH="$(git rev-parse --show-toplevel)"
if git worktree list --porcelain | grep -Fqx "worktree $CURRENT_WORKTREE_PATH"; then
  echo "Using current worktree: $CURRENT_WORKTREE_PATH"
else
  echo "Using repository checkout at: $CURRENT_WORKTREE_PATH"
fi

PRD_BRANCH="$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")"
SOURCE_PRD_FILE="$(resolve_source_prd_file)"
CURRENT_BRANCH_BEFORE_SWITCH="$(current_git_branch)"
if [ "$BRANCH_STRATEGY" = "reuse-current" ]; then
  RUN_BRANCH_KEY="$CURRENT_BRANCH_BEFORE_SWITCH"
else
  RUN_BRANCH_KEY="$PRD_BRANCH"
fi
RESET_PROGRESS_FILE=0

check_prd_completion() {
  local remaining_stories

  if [ ! -f "$PRD_FILE" ]; then
    echo "Warning: Missing PRD file at $PRD_FILE. Treating as incomplete."
    return 1
  fi

  if ! remaining_stories="$(jq '.userStories[] | select(.passes == false) | {id, title, passes}' "$PRD_FILE" 2>/dev/null)"; then
    echo "Warning: Unable to parse $PRD_FILE for completion check. Treating as incomplete."
    return 1
  fi

  [ -z "$remaining_stories" ]
}

current_active_phase() {
  if [ ! -f "$PRD_FILE" ]; then
    return
  fi

  jq -r '
    if (.phases // [] | length) == 0 then
      ""
    else
      (.phases | map(select((.status // "planned") != "done")) | .[0].id // "")
    end
  ' "$PRD_FILE" 2>/dev/null || true
}

render_prompt() {
  local prompt_file="$1"
  local active_phase
  active_phase="$(current_active_phase)"

  if [ ! -f "$prompt_file" ]; then
    echo "Error: Missing prompt file at $prompt_file."
    return 1
  fi

  awk -v prd_file="$PRD_FILE" -v progress_file="$PROGRESS_FILE" -v active_phase="$active_phase" -v source_prd_file="$SOURCE_PRD_FILE" '
    {
      gsub(/__PRD_FILE__/, prd_file)
      gsub(/__PROGRESS_FILE__/, progress_file)
      gsub(/__ACTIVE_PHASE__/, active_phase)
      gsub(/__SOURCE_PRD_FILE__/, source_prd_file)
      print
    }
  ' "$prompt_file"
}

run_codex() {
  local prompt_file="$1"

  if [ -z "${CODEX_CMD//[[:space:]]/}" ]; then
    echo "Error: CODEX_CMD is empty."
    return 1
  fi

  render_prompt "$prompt_file" | bash -lc "$CODEX_CMD"
}

run_agent_prompt() {
  local prompt_file="$1"

  if [[ "$TOOL" == "amp" ]]; then
    render_prompt "$prompt_file" | amp --dangerously-allow-all
  elif [[ "$TOOL" == "claude" ]]; then
    # Claude Code: use --dangerously-skip-permissions for autonomous operation, --print for output
    render_prompt "$prompt_file" | claude --dangerously-skip-permissions --print
  else
    # Codex: use non-interactive exec mode because the default TUI requires a terminal.
    run_codex "$prompt_file"
  fi
}

# Archive previous run if branch changed
if [ -f "$LAST_BRANCH_FILE" ]; then
  CURRENT_BRANCH="$RUN_BRANCH_KEY"
  LAST_BRANCH=$(cat "$LAST_BRANCH_FILE" 2>/dev/null || echo "")
  
  if [ -n "$CURRENT_BRANCH" ] && [ -n "$LAST_BRANCH" ] && [ "$CURRENT_BRANCH" != "$LAST_BRANCH" ]; then
    # Archive the previous run
    DATE=$(date +%Y-%m-%d)
    # Strip "ralph/" prefix from branch name for folder
    FOLDER_NAME=$(echo "$LAST_BRANCH" | sed 's|^ralph/||')
    ARCHIVE_FOLDER="$ARCHIVE_DIR/$DATE-$FOLDER_NAME"
    
    echo "Archiving previous run: $LAST_BRANCH"
    mkdir -p "$ARCHIVE_FOLDER"
    [ -f "$PRD_FILE" ] && cp "$PRD_FILE" "$ARCHIVE_FOLDER/"
    [ -f "$PROGRESS_FILE" ] && cp "$PROGRESS_FILE" "$ARCHIVE_FOLDER/"
    echo "   Archived to: $ARCHIVE_FOLDER"

    RESET_PROGRESS_FILE=1
  fi
fi

ensure_branch_context "$PRD_BRANCH"
ACTIVE_BRANCH="$(current_git_branch)"

# Track current branch
if [ -n "$ACTIVE_BRANCH" ]; then
  echo "$ACTIVE_BRANCH" > "$LAST_BRANCH_FILE"
fi

if [ "$RESET_PROGRESS_FILE" -eq 1 ]; then
  # Reset progress file for a new run branch after branch/worktree preparation.
  echo "# Ralph Progress Log" > "$PROGRESS_FILE"
  echo "Started: $(date)" >> "$PROGRESS_FILE"
  echo "---" >> "$PROGRESS_FILE"
fi

# Initialize progress file if it doesn't exist
if [ ! -f "$PROGRESS_FILE" ]; then
  echo "# Ralph Progress Log" > "$PROGRESS_FILE"
  echo "Started: $(date)" >> "$PROGRESS_FILE"
  echo "---" >> "$PROGRESS_FILE"
fi

if check_prd_completion; then
  echo "Ralph has no remaining tasks. All stories already pass in $PRD_FILE."
  exit 0
fi

echo "Starting Ralph - Tool: $TOOL - Max iterations: $MAX_ITERATIONS"
echo "Branch strategy: $BRANCH_STRATEGY"
echo "Active branch: ${ACTIVE_BRANCH:-detached-HEAD}"
if [ "$BRANCH_STRATEGY" = "create-from-base" ]; then
  echo "Base branch: $BASE_BRANCH"
fi
if [ "$ENABLE_REPLAN" -eq 1 ]; then
  echo "Replan step: enabled ($REPLAN_PROMPT_FILE)"
  echo "Replan cadence: every $REPLAN_EVERY iteration(s)"
else
  echo "Replan step: disabled"
fi
if [ -n "$SOURCE_PRD_FILE" ]; then
  echo "Source PRD: $SOURCE_PRD_FILE"
else
  echo "Source PRD: not set"
fi

case "$TOOL" in
  amp)
    MAIN_PROMPT_FILE="$AMP_PROMPT_FILE"
    ;;
  claude)
    MAIN_PROMPT_FILE="$CLAUDE_PROMPT_FILE"
    ;;
  codex)
    MAIN_PROMPT_FILE="$CODEX_PROMPT_FILE"
    ;;
esac

for i in $(seq 1 $MAX_ITERATIONS); do
  echo ""
  echo "==============================================================="
  echo "  Ralph Iteration $i of $MAX_ITERATIONS ($TOOL)"
  echo "==============================================================="

  if [ "$ENABLE_REPLAN" -eq 1 ]; then
    if (( (i - 1) % REPLAN_EVERY == 0 )); then
      if [ -f "$REPLAN_PROMPT_FILE" ]; then
        echo "Replan step (iteration $i)"
        run_agent_prompt "$REPLAN_PROMPT_FILE" 2>&1 | tee /dev/stderr || true
      else
        echo "Warning: Replan prompt file not found at $REPLAN_PROMPT_FILE. Skipping replan step."
      fi
    else
      echo "Replan step skipped (iteration $i, replan-every=$REPLAN_EVERY)"
    fi
  fi

  echo "Execution step (iteration $i)"
  run_agent_prompt "$MAIN_PROMPT_FILE" 2>&1 | tee /dev/stderr || true
  
  # Stop when the PRD shows every story has passed.
  if check_prd_completion; then
    echo ""
    echo "Ralph completed all tasks!"
    echo "Completed at iteration $i of $MAX_ITERATIONS"
    exit 0
  fi
  
  echo "Iteration $i complete. Continuing..."
  sleep 2
done

echo ""
echo "Ralph reached max iterations ($MAX_ITERATIONS) without completing all tasks."
echo "Check $PROGRESS_FILE for status."
exit 1
