#!/usr/bin/env bash
# changelog-generator/scripts/run.sh
# Generates a structured CHANGELOG entry based on merged PRs and commits
# between two git refs (tags, branches, or SHAs).
#
# Usage:
#   FROM_REF=v0.1.0 TO_REF=HEAD bash run.sh
#   FROM_REF=v0.1.0 TO_REF=v0.2.0 OUTPUT_FILE=CHANGELOG.md bash run.sh

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
FROM_REF="${FROM_REF:-}"
TO_REF="${TO_REF:-HEAD}"
OUTPUT_FILE="${OUTPUT_FILE:-CHANGELOG_DRAFT.md}"
REPO_URL="${REPO_URL:-}"
DATE="$(date +%Y-%m-%d)"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { echo "[changelog-generator] $*" >&2; }
die()  { log "ERROR: $*"; exit 1; }

require_cmd() {
  command -v "$1" &>/dev/null || die "Required command not found: $1"
}

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------
require_cmd git

if [[ -z "$FROM_REF" ]]; then
  # Fall back to the most recent tag if FROM_REF is not provided
  FROM_REF="$(git describe --tags --abbrev=0 2>/dev/null || true)"
  if [[ -z "$FROM_REF" ]]; then
    die "FROM_REF is not set and no git tags were found. "\
        "Please set FROM_REF to a tag, branch, or commit SHA."
  fi
  log "FROM_REF not set; using latest tag: $FROM_REF"
fi

# Resolve REPO_URL from remote if not provided
if [[ -z "$REPO_URL" ]]; then
  REPO_URL="$(git remote get-url origin 2>/dev/null || true)"
  # Convert SSH remote to HTTPS URL for link generation
  REPO_URL="${REPO_URL/git@github.com:/https://github.com/}"
  REPO_URL="${REPO_URL%.git}"
fi

log "Generating changelog from $FROM_REF..$TO_REF"
log "Repository URL : ${REPO_URL:-<unknown>}"
log "Output file    : $OUTPUT_FILE"

# ---------------------------------------------------------------------------
# Collect commits
# ---------------------------------------------------------------------------
# Format: <short-sha>|<subject>
COMMITS="$(git log --no-merges --pretty=format:'%h|%s' "${FROM_REF}..${TO_REF}" 2>/dev/null)"

if [[ -z "$COMMITS" ]]; then
  log "No commits found between $FROM_REF and $TO_REF — nothing to generate."
  exit 0
fi

# ---------------------------------------------------------------------------
# Categorise commits (conventional-commit prefixes)
# ---------------------------------------------------------------------------
declare -a BREAKING FEATURES FIXES DOCS CHORES OTHER

while IFS='|' read -r sha subject; do
  [[ -z "$sha" ]] && continue

  if echo "$subject" | grep -qiE '!:|BREAKING[[:space:]]CHANGE'; then
    BREAKING+=("$sha|$subject")
  elif echo "$subject" | grep -qiE '^feat(\([^)]+\))?[!]?:'; then
    FEATURES+=("$sha|$subject")
  elif echo "$subject" | grep -qiE '^fix(\([^)]+\))?[!]?:'; then
    FIXES+=("$sha|$subject")
  elif echo "$subject" | grep -qiE '^docs?(\([^)]+\))?[!]?:'; then
    DOCS+=("$sha|$subject")
  elif echo "$subject" | grep -qiE '^(chore|ci|build|refactor|perf|test|style)(\([^)]+\))?[!]?:'; then
    CHORES+=("$sha|$subject")
  else
    OTHER+=("$sha|$subject")
  fi
done <<< "$COMMITS"

# ---------------------------------------------------------------------------
# Render a section
# ---------------------------------------------------------------------------
render_section() {
  local title="$1"; shift
  local -a entries=("$@")
  [[ ${#entries[@]} -eq 0 ]] && return

  echo "### $title"
  echo
  for entry in "${entries[@]}"; do
    local sha subject commit_url
    sha="${entry%%|*}"
    subject="${entry#*|}"
    if [[ -n "$REPO_URL" ]]; then
      commit_url="$REPO_URL/commit/$sha"
      echo "- $subject ([\`$sha\`]($commit_url))"
    else
      echo "- $subject (\`$sha\`)"
    fi
  done
  echo
}

# ---------------------------------------------------------------------------
# Determine version heading
# ---------------------------------------------------------------------------
if [[ "$TO_REF" == "HEAD" ]]; then
  VERSION_HEADING="Unreleased"
else
  VERSION_HEADING="$TO_REF"
fi

# ---------------------------------------------------------------------------
# Write output
# ---------------------------------------------------------------------------
{
  echo "## [$VERSION_HEADING] — $DATE"
  echo
  render_section "⚠ Breaking Changes"  "${BREAKING[@]+${BREAKING[@]}}"
  render_section "✨ Features"          "${FEATURES[@]+${FEATURES[@]}}"
  render_section "🐛 Bug Fixes"         "${FIXES[@]+${FIXES[@]}}"
  render_section "📚 Documentation"     "${DOCS[@]+${DOCS[@]}}"
  render_section "🔧 Chores / Internal" "${CHORES[@]+${CHORES[@]}}"
  render_section "📝 Other Changes"     "${OTHER[@]+${OTHER[@]}}"

  if [[ -n "$REPO_URL" ]]; then
    echo "**Full diff:** [$FROM_REF...$VERSION_HEADING]($REPO_URL/compare/$FROM_REF...$TO_REF)"
    echo
  fi
} > "$OUTPUT_FILE"

log "Changelog draft written to $OUTPUT_FILE"
cat "$OUTPUT_FILE"
