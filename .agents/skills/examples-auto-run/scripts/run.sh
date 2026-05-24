#!/usr/bin/env bash
# examples-auto-run/scripts/run.sh
# Automatically discovers and runs all examples in the repository,
# capturing output and reporting pass/fail status for each.

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
EXAMPLES_DIR="${REPO_ROOT}/examples"
LOG_DIR="${REPO_ROOT}/.agents/skills/examples-auto-run/logs"
TIMEOUT_SECONDS="${EXAMPLES_TIMEOUT:-60}"
PYTHON="${PYTHON_BIN:-python}"

PASSED=()
FAILED=()
SKIPPED=()

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { echo "[examples-auto-run] $*"; }
warn() { echo "[examples-auto-run] WARN: $*" >&2; }
err()  { echo "[examples-auto-run] ERROR: $*" >&2; }

require_command() {
  if ! command -v "$1" &>/dev/null; then
    err "Required command not found: $1"
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
require_command "$PYTHON"
require_command "timeout"

mkdir -p "$LOG_DIR"

if [[ ! -d "$EXAMPLES_DIR" ]]; then
  err "Examples directory not found: $EXAMPLES_DIR"
  exit 1
fi

# ---------------------------------------------------------------------------
# Discover examples
# ---------------------------------------------------------------------------
# An example is any *.py file directly under examples/ or one level deep.
mapfile -t EXAMPLE_FILES < <(
  find "$EXAMPLES_DIR" -maxdepth 2 -name "*.py" | sort
)

if [[ ${#EXAMPLE_FILES[@]} -eq 0 ]]; then
  warn "No example files found in $EXAMPLES_DIR"
  exit 0
fi

log "Found ${#EXAMPLE_FILES[@]} example file(s) to run."
log "Timeout per example: ${TIMEOUT_SECONDS}s"
log "Logs directory: $LOG_DIR"
echo ""

# ---------------------------------------------------------------------------
# Run each example
# ---------------------------------------------------------------------------
for example in "${EXAMPLE_FILES[@]}"; do
  rel="${example#"$REPO_ROOT/"}"
  safe_name="$(echo "$rel" | tr '/' '_' | tr ' ' '_')"
  log_file="${LOG_DIR}/${safe_name%.py}.log"

  # Check for explicit skip marker inside the file
  if grep -qE '^\s*#\s*skip-auto-run' "$example" 2>/dev/null; then
    log "  SKIP  $rel  (skip-auto-run marker found)"
    SKIPPED+=("$rel")
    continue
  fi

  log "  RUN   $rel"

  set +e
  timeout "$TIMEOUT_SECONDS" "$PYTHON" "$example" \
    > "$log_file" 2>&1
  exit_code=$?
  set -e

  if [[ $exit_code -eq 0 ]]; then
    log "  PASS  $rel"
    PASSED+=("$rel")
  elif [[ $exit_code -eq 124 ]]; then
    warn "  TIMEOUT $rel (>${TIMEOUT_SECONDS}s) — log: $log_file"
    FAILED+=("$rel (timeout)")
  else
    warn "  FAIL  $rel (exit $exit_code) — log: $log_file"
    FAILED+=("$rel (exit $exit_code)")
  fi
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
log "========================================"
log "Results: ${#PASSED[@]} passed, ${#FAILED[@]} failed, ${#SKIPPED[@]} skipped"
log "========================================"

if [[ ${#FAILED[@]} -gt 0 ]]; then
  err "Failed examples:"
  for f in "${FAILED[@]}"; do
    err "  - $f"
  done
  exit 1
fi

log "All examples passed."
exit 0
