#!/usr/bin/env bash
# Release Automation Script
# Automates the release process for openai-agents-python:
# version bumping, changelog generation, tagging, and publishing.

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
PYPROJECT="${REPO_ROOT}/pyproject.toml"
CHANGELOG="${REPO_ROOT}/CHANGELOG.md"

RELEASE_TYPE="${1:-patch}"   # major | minor | patch
DRY_RUN="${DRY_RUN:-false}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
PYPI_TOKEN="${PYPI_TOKEN:-}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { echo "[release] $*"; }
error(){ echo "[release] ERROR: $*" >&2; exit 1; }

require_cmd() {
  command -v "$1" &>/dev/null || error "Required command not found: $1"
}

# Run a command, or just print it when DRY_RUN=true
run() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[dry-run] $*"
  else
    "$@"
  fi
}

# ---------------------------------------------------------------------------
# Validate environment
# ---------------------------------------------------------------------------
require_cmd git
require_cmd python3
require_cmd sed

[[ "${RELEASE_TYPE}" =~ ^(major|minor|patch)$ ]] || \
  error "Invalid release type '${RELEASE_TYPE}'. Use major, minor, or patch."

[[ -f "${PYPROJECT}" ]] || error "pyproject.toml not found at ${PYPROJECT}"

# Ensure working tree is clean
if [[ -n "$(git -C "${REPO_ROOT}" status --porcelain)" ]]; then
  error "Working tree is not clean. Commit or stash changes before releasing."
fi

# ---------------------------------------------------------------------------
# Determine current and next version
# ---------------------------------------------------------------------------
CURRENT_VERSION=$(python3 - <<'EOF'
import re, sys
with open(sys.argv[1]) as f:
    content = f.read()
m = re.search(r'^version\s*=\s*"([^"]+)"', content, re.MULTILINE)
if not m:
    sys.exit(1)
print(m.group(1))
EOF
"${PYPROJECT}")

log "Current version: ${CURRENT_VERSION}"

NEXT_VERSION=$(python3 - <<EOF
parts = "${CURRENT_VERSION}".split(".")
major, minor, patch = int(parts[0]), int(parts[1]), int(parts[2])
if "${RELEASE_TYPE}" == "major":
    major += 1; minor = 0; patch = 0
elif "${RELEASE_TYPE}" == "minor":
    minor += 1; patch = 0
else:
    patch += 1
print(f"{major}.{minor}.{patch}")
EOF
)

log "Next version:    ${NEXT_VERSION}"

# ---------------------------------------------------------------------------
# Bump version in pyproject.toml
# ---------------------------------------------------------------------------
log "Bumping version in pyproject.toml ..."
run sed -i "s/^version = \"${CURRENT_VERSION}\"/version = \"${NEXT_VERSION}\"/" "${PYPROJECT}"

# ---------------------------------------------------------------------------
# Update CHANGELOG
# ---------------------------------------------------------------------------
DATE=$(date +%Y-%m-%d)
if [[ -f "${CHANGELOG}" ]]; then
  log "Prepending release header to CHANGELOG.md ..."
  HEADER="## [${NEXT_VERSION}] - ${DATE}\n"
  run python3 - <<EOF
import pathlib
p = pathlib.Path("${CHANGELOG}")
original = p.read_text()
p.write_text("${HEADER}\n" + original)
EOF
fi

# ---------------------------------------------------------------------------
# Commit and tag
# ---------------------------------------------------------------------------
log "Committing version bump ..."
run git -C "${REPO_ROOT}" add "${PYPROJECT}" "${CHANGELOG}"
run git -C "${REPO_ROOT}" commit -m "chore: release v${NEXT_VERSION}"

log "Creating git tag v${NEXT_VERSION} ..."
run git -C "${REPO_ROOT}" tag -a "v${NEXT_VERSION}" -m "Release v${NEXT_VERSION}"

# ---------------------------------------------------------------------------
# Push to remote
# ---------------------------------------------------------------------------
if [[ -n "${GITHUB_TOKEN}" ]]; then
  log "Pushing commit and tag to origin ..."
  run git -C "${REPO_ROOT}" push origin HEAD
  run git -C "${REPO_ROOT}" push origin "v${NEXT_VERSION}"
else
  log "GITHUB_TOKEN not set — skipping push."
fi

# ---------------------------------------------------------------------------
# Build and publish to PyPI
# ---------------------------------------------------------------------------
if [[ -n "${PYPI_TOKEN}" ]]; then
  log "Building distribution packages ..."
  run python3 -m build --outdir "${REPO_ROOT}/dist" "${REPO_ROOT}"

  log "Publishing to PyPI ..."
  run python3 -m twine upload \
    --non-interactive \
    --username __token__ \
    --password "${PYPI_TOKEN}" \
    "${REPO_ROOT}/dist"/*
else
  log "PYPI_TOKEN not set — skipping PyPI publish."
fi

log "Release v${NEXT_VERSION} completed successfully."
