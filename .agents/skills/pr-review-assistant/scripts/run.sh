#!/usr/bin/env bash
# PR Review Assistant Script
# Analyzes pull requests and provides structured code review feedback
# using OpenAI agents to identify issues, suggest improvements, and
# enforce project coding standards.

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

PR_NUMBER="${PR_NUMBER:-}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
OPENAI_API_KEY="${OPENAI_API_KEY:-}"
GITHUB_REPO="${GITHUB_REPO:-}"

# Review configuration
MAX_FILES_PER_REVIEW="${MAX_FILES_PER_REVIEW:-30}"
REVIEW_FOCUS="${REVIEW_FOCUS:-general}"  # general | security | performance | style
POST_COMMENT="${POST_COMMENT:-false}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { echo "[pr-review] $*" >&2; }
error() { echo "[pr-review][ERROR] $*" >&2; exit 1; }

require_env() {
  local var="$1"
  [[ -n "${!var:-}" ]] || error "Required environment variable \$${var} is not set."
}

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------
require_env OPENAI_API_KEY
require_env GITHUB_TOKEN
require_env GITHUB_REPO
require_env PR_NUMBER

command -v curl  >/dev/null 2>&1 || error "curl is required but not installed."
command -v jq    >/dev/null 2>&1 || error "jq is required but not installed."
command -v python3 >/dev/null 2>&1 || error "python3 is required but not installed."

# ---------------------------------------------------------------------------
# Fetch PR metadata from GitHub
# ---------------------------------------------------------------------------
log "Fetching PR #${PR_NUMBER} metadata from ${GITHUB_REPO}..."

GH_API="https://api.github.com/repos/${GITHUB_REPO}"

pr_meta=$(curl -fsSL \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  "${GH_API}/pulls/${PR_NUMBER}")

pr_title=$(echo "${pr_meta}" | jq -r '.title')
pr_body=$(echo "${pr_meta}"  | jq -r '.body // ""')
pr_base=$(echo "${pr_meta}"  | jq -r '.base.sha')
pr_head=$(echo "${pr_meta}"  | jq -r '.head.sha')

log "PR title : ${pr_title}"
log "Base SHA : ${pr_base}"
log "Head SHA : ${pr_head}"

# ---------------------------------------------------------------------------
# Fetch changed files
# ---------------------------------------------------------------------------
log "Fetching changed files (max ${MAX_FILES_PER_REVIEW})..."

changed_files=$(curl -fsSL \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  "${GH_API}/pulls/${PR_NUMBER}/files?per_page=${MAX_FILES_PER_REVIEW}" \
  | jq '[.[] | {filename: .filename, status: .status, additions: .additions, deletions: .deletions, patch: (.patch // "")}]')

file_count=$(echo "${changed_files}" | jq 'length')
log "Found ${file_count} changed file(s)."

# ---------------------------------------------------------------------------
# Build review prompt payload
# ---------------------------------------------------------------------------
log "Building review payload (focus: ${REVIEW_FOCUS})..."

review_payload=$(python3 - <<'PYEOF'
import json, os, sys

focus      = os.environ.get("REVIEW_FOCUS", "general")
pr_title   = os.environ.get("_PR_TITLE", "")
pr_body    = os.environ.get("_PR_BODY", "")
files_json = os.environ.get("_CHANGED_FILES", "[]")

files = json.loads(files_json)

focus_instructions = {
    "general":     "Review for correctness, readability, maintainability, and adherence to project conventions.",
    "security":    "Focus on security vulnerabilities: injection flaws, secrets in code, improper auth, unsafe deserialization.",
    "performance": "Focus on performance: algorithmic complexity, unnecessary allocations, blocking calls, caching opportunities.",
    "style":       "Focus on code style: naming conventions, formatting, documentation, and PEP-8 / project lint rules.",
}

file_summaries = []
for f in files:
    patch = f.get("patch", "")[:3000]  # truncate very large patches
    file_summaries.append(
        f"### {f['filename']} ({f['status']}, +{f['additions']}/-{f['deletions']})\n"
        f"```diff\n{patch}\n```"
    )

prompt = (
    f"You are an expert code reviewer for the openai-agents-python project.\n"
    f"PR Title: {pr_title}\n"
    f"PR Description: {pr_body or '(none)'}\n\n"
    f"Review focus: {focus_instructions.get(focus, focus_instructions['general'])}\n\n"
    f"Changed files:\n\n" + "\n\n".join(file_summaries) + "\n\n"
    f"Provide a structured review with:\n"
    f"1. **Summary** – overall assessment (1-3 sentences).\n"
    f"2. **Issues** – numbered list of concrete problems (file + line if possible).\n"
    f"3. **Suggestions** – optional improvements.\n"
    f"4. **Verdict** – one of: APPROVE / REQUEST_CHANGES / COMMENT.\n"
)

print(json.dumps({"prompt": prompt}))
PYEOF
)

export _PR_TITLE="${pr_title}"
export _PR_BODY="${pr_body}"
export _CHANGED_FILES="${changed_files}"

# ---------------------------------------------------------------------------
# Call OpenAI Chat Completions
# ---------------------------------------------------------------------------
log "Calling OpenAI API for review..."

prompt_text=$(echo "${review_payload}" | jq -r '.prompt')

review_response=$(curl -fsSL \
  -H "Authorization: Bearer ${OPENAI_API_KEY}" \
  -H "Content-Type: application/json" \
  -d "$(jq -n \
        --arg model "gpt-4o" \
        --arg content "${prompt_text}" \
        '{model: $model, messages: [{role: "user", content: $content}], temperature: 0.2}')" \
  "https://api.openai.com/v1/chat/completions")

review_text=$(echo "${review_response}" | jq -r '.choices[0].message.content')

log "Review generated."
echo "------------------------------------------------------------"
echo "${review_text}"
echo "------------------------------------------------------------"

# ---------------------------------------------------------------------------
# Optionally post review comment to GitHub
# ---------------------------------------------------------------------------
if [[ "${POST_COMMENT}" == "true" ]]; then
  log "Posting review comment to PR #${PR_NUMBER}..."
  curl -fsSL -X POST \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg body "${review_text}" '{body: $body}')" \
    "${GH_API}/issues/${PR_NUMBER}/comments" >/dev/null
  log "Comment posted successfully."
fi

log "PR review assistant completed."
