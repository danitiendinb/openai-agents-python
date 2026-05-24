#!/usr/bin/env bash
# Dependency Update Skill Script
# Checks for outdated dependencies and creates a PR with updates

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
BRANCH_PREFIX="chore/dependency-update"
DATE_STAMP="$(date +%Y%m%d)"
UPDATE_BRANCH="${BRANCH_PREFIX}-${DATE_STAMP}"
COMMIT_MSG="chore: update dependencies (${DATE_STAMP})"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { echo "[dependency-update] $*"; }
warn() { echo "[dependency-update] WARNING: $*" >&2; }
err()  { echo "[dependency-update] ERROR: $*" >&2; exit 1; }

require_cmd() {
  command -v "$1" &>/dev/null || err "Required command not found: $1"
}

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
require_cmd git
require_cmd python3
require_cmd pip

cd "${REPO_ROOT}"

# Ensure we are on a clean working tree before starting
if [[ -n "$(git status --porcelain)" ]]; then
  err "Working tree is dirty. Commit or stash changes before running this skill."
fi

# ---------------------------------------------------------------------------
# Detect package manager / project type
# ---------------------------------------------------------------------------
if [[ -f "pyproject.toml" ]]; then
  PROJECT_TYPE="pyproject"
elif [[ -f "requirements.txt" ]]; then
  PROJECT_TYPE="requirements"
else
  err "No recognised Python project file found (pyproject.toml or requirements.txt)."
fi

log "Detected project type: ${PROJECT_TYPE}"

# ---------------------------------------------------------------------------
# Install / upgrade pip-tools for dependency resolution
# ---------------------------------------------------------------------------
log "Ensuring pip-tools is available..."
pip install --quiet --upgrade pip pip-tools

# ---------------------------------------------------------------------------
# Collect outdated packages
# ---------------------------------------------------------------------------
log "Checking for outdated packages..."
OUTDATED_JSON="$(pip list --outdated --format=json 2>/dev/null || echo '[]')"

if [[ "${OUTDATED_JSON}" == "[]" ]]; then
  log "All dependencies are up to date. Nothing to do."
  exit 0
fi

OUTDATED_COUNT="$(echo "${OUTDATED_JSON}" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))")"
log "Found ${OUTDATED_COUNT} outdated package(s)."

# Build a human-readable summary for the PR body
UPDATE_SUMMARY="$(echo "${OUTDATED_JSON}" | python3 - <<'EOF'
import sys, json
packages = json.load(sys.stdin)
lines = []
for p in packages:
    lines.append(f"- **{p['name']}**: {p['version']} → {p['latest_version']} ({p['latest_filetype']})")
print("\n".join(lines))
EOF
)"

# ---------------------------------------------------------------------------
# Create update branch
# ---------------------------------------------------------------------------
log "Creating branch ${UPDATE_BRANCH}..."
git checkout -b "${UPDATE_BRANCH}" 2>/dev/null || {
  warn "Branch ${UPDATE_BRANCH} already exists — switching to it."
  git checkout "${UPDATE_BRANCH}"
}

# ---------------------------------------------------------------------------
# Apply updates
# ---------------------------------------------------------------------------
if [[ "${PROJECT_TYPE}" == "pyproject" ]]; then
  log "Upgrading all extras via pip (pyproject.toml project)..."
  # Upgrade each outdated package individually so we get precise control
  echo "${OUTDATED_JSON}" | python3 -c "
import sys, json, subprocess
for p in json.load(sys.stdin):
    pkg = p['name']
    ver = p['latest_version']
    print(f'Upgrading {pkg} to {ver}...')
    subprocess.run(['pip', 'install', '--quiet', f'{pkg}=={ver}'], check=True)
"
  # Sync pyproject / lock file if uv or poetry is available
  if command -v uv &>/dev/null; then
    log "Detected uv — running 'uv lock'..."
    uv lock
  elif command -v poetry &>/dev/null; then
    log "Detected poetry — running 'poetry lock --no-update'..."
    poetry lock --no-update
  fi
elif [[ "${PROJECT_TYPE}" == "requirements" ]]; then
  log "Recompiling requirements.txt with pip-compile..."
  pip-compile --upgrade --quiet requirements.in 2>/dev/null || \
    pip-compile --upgrade --quiet requirements.txt
fi

# ---------------------------------------------------------------------------
# Commit changes (if any)
# ---------------------------------------------------------------------------
if [[ -z "$(git status --porcelain)" ]]; then
  log "No file changes detected after upgrade. Dependencies may already be pinned at latest."
  git checkout -
  git branch -D "${UPDATE_BRANCH}" 2>/dev/null || true
  exit 0
fi

git add -A
git commit -m "${COMMIT_MSG}"
log "Changes committed: ${COMMIT_MSG}"

# ---------------------------------------------------------------------------
# Push and open PR (requires gh CLI)
# ---------------------------------------------------------------------------
if command -v gh &>/dev/null; then
  log "Pushing branch and creating pull request..."
  git push --set-upstream origin "${UPDATE_BRANCH}"

  PR_BODY="## Dependency Updates\n\nAutomated dependency update generated on ${DATE_STAMP}.\n\n### Updated packages\n\n${UPDATE_SUMMARY}\n\n---\n_Generated by the dependency-update agent skill._"

  gh pr create \
    --title "chore: dependency updates ${DATE_STAMP}" \
    --body "$(printf '%b' "${PR_BODY}")" \
    --label "dependencies" \
    --label "automated" 2>/dev/null || \
  gh pr create \
    --title "chore: dependency updates ${DATE_STAMP}" \
    --body "$(printf '%b' "${PR_BODY}")"

  log "Pull request created successfully."
else
  warn "'gh' CLI not found. Branch '${UPDATE_BRANCH}' has been committed locally."
  warn "Push it manually and open a PR when ready."
fi

log "Done."
