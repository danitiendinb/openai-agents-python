#!/usr/bin/env bash
# Test Automation Skill - Run Script
# Automatically discovers and runs tests, generates coverage reports,
# and posts results as PR comments or workflow summaries.

set -euo pipefail

# ─── Configuration ────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}" )" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
RESULTS_DIR="${REPO_ROOT}/.agents/test-results"
COVERAGE_THRESHOLD="${COVERAGE_THRESHOLD:-80}"
PYTHON_CMD="${PYTHON_CMD:-python}"

# ─── Helpers ──────────────────────────────────────────────────────────────────
log()  { echo "[test-automation] $*"; }
warn() { echo "[test-automation] WARNING: $*" >&2; }
die()  { echo "[test-automation] ERROR: $*" >&2; exit 1; }

require_cmd() {
  command -v "$1" &>/dev/null || die "Required command not found: $1"
}

# ─── Environment validation ───────────────────────────────────────────────────
validate_env() {
  require_cmd "$PYTHON_CMD"
  require_cmd "git"

  if ! "$PYTHON_CMD" -m pytest --version &>/dev/null; then
    die "pytest is not installed. Run: pip install pytest pytest-cov"
  fi

  log "Environment validated."
}

# ─── Discover changed test-relevant files ─────────────────────────────────────
get_changed_modules() {
  local base_ref="${BASE_REF:-origin/main}"
  git diff --name-only "${base_ref}"...HEAD 2>/dev/null \
    | grep -E '\.(py)$' \
    | grep -v '__pycache__' \
    || true
}

# ─── Run tests ────────────────────────────────────────────────────────────────
run_tests() {
  local test_path="${1:-tests/}"
  local junit_xml="${RESULTS_DIR}/junit.xml"
  local coverage_xml="${RESULTS_DIR}/coverage.xml"
  local coverage_html="${RESULTS_DIR}/htmlcov"

  mkdir -p "${RESULTS_DIR}"

  log "Running tests in: ${test_path}"

  set +e
  "$PYTHON_CMD" -m pytest \
    "${test_path}" \
    --tb=short \
    --junitxml="${junit_xml}" \
    --cov=src \
    --cov-report=xml:"${coverage_xml}" \
    --cov-report=html:"${coverage_html}" \
    --cov-report=term-missing \
    --cov-fail-under="${COVERAGE_THRESHOLD}" \
    -q \
    2>&1 | tee "${RESULTS_DIR}/pytest.log"
  local exit_code=$?
  set -e

  return $exit_code
}

# ─── Parse coverage percentage from XML ───────────────────────────────────────
parse_coverage() {
  local coverage_xml="${RESULTS_DIR}/coverage.xml"
  if [[ -f "${coverage_xml}" ]]; then
    "$PYTHON_CMD" - <<'EOF'
import xml.etree.ElementTree as ET, sys
tree = ET.parse(sys.argv[1])
root = tree.getroot()
line_rate = float(root.attrib.get('line-rate', 0))
print(f"{line_rate * 100:.1f}")
EOF
  else
    echo "N/A"
  fi
}

# ─── Generate summary ─────────────────────────────────────────────────────────
generate_summary() {
  local test_exit_code="$1"
  local coverage_pct
  coverage_pct=$(parse_coverage "${RESULTS_DIR}/coverage.xml" 2>/dev/null || echo "N/A")

  local status_icon="✅"
  [[ "$test_exit_code" -ne 0 ]] && status_icon="❌"

  cat <<EOF
## ${status_icon} Test Automation Results

| Metric | Value |
|--------|-------|
| Status | $([ "$test_exit_code" -eq 0 ] && echo "Passed" || echo "Failed") |
| Coverage | ${coverage_pct}% |
| Threshold | ${COVERAGE_THRESHOLD}% |

<details>
<summary>Full test log</summary>

\`\`\`
$(tail -50 "${RESULTS_DIR}/pytest.log" 2>/dev/null || echo 'No log available')
\`\`\`
</details>
EOF
}

# ─── Post to GitHub step summary (if available) ───────────────────────────────
post_summary() {
  local summary
  summary=$(generate_summary "$1")

  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    echo "${summary}" >> "${GITHUB_STEP_SUMMARY}"
    log "Summary posted to GitHub Actions step summary."
  else
    echo "${summary}"
  fi
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
  log "Starting test automation skill..."
  log "Repo root: ${REPO_ROOT}"

  cd "${REPO_ROOT}"

  validate_env

  local changed_files
  changed_files=$(get_changed_modules)

  if [[ -n "${changed_files}" ]]; then
    log "Changed Python files detected:"
    echo "${changed_files}" | sed 's/^/  /'
  else
    log "No changed Python files detected; running full test suite."
  fi

  local test_exit_code=0
  run_tests "tests/" || test_exit_code=$?

  post_summary "${test_exit_code}"

  if [[ "${test_exit_code}" -ne 0 ]]; then
    die "Tests failed or coverage below threshold (${COVERAGE_THRESHOLD}%). See ${RESULTS_DIR}/pytest.log for details."
  fi

  log "All tests passed. Coverage meets threshold."
}

main "$@"
