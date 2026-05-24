#!/usr/bin/env bash
# Issue Triage Skill - Automatically triages GitHub issues by analyzing content,
# applying labels, assigning priority, and routing to appropriate team members.

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
REPO="${REPO:-openai/openai-agents-python}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
ISSUE_NUMBER="${ISSUE_NUMBER:-}"
DRY_RUN="${DRY_RUN:-false}"

if [[ -z "$GITHUB_TOKEN" ]]; then
  echo "ERROR: GITHUB_TOKEN is required" >&2
  exit 1
fi

if [[ -z "$ISSUE_NUMBER" ]]; then
  echo "ERROR: ISSUE_NUMBER is required" >&2
  exit 1
fi

GH_API="https://api.github.com"
AUTH_HEADER="Authorization: Bearer ${GITHUB_TOKEN}"
ACCEPT_HEADER="Accept: application/vnd.github+json"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
gh_get() {
  curl -sSL -H "${AUTH_HEADER}" -H "${ACCEPT_HEADER}" "${GH_API}$1"
}

gh_post() {
  local endpoint="$1"
  local payload="$2"
  curl -sSL -X POST \
    -H "${AUTH_HEADER}" \
    -H "${ACCEPT_HEADER}" \
    -H "Content-Type: application/json" \
    -d "${payload}" \
    "${GH_API}${endpoint}"
}

gh_patch() {
  local endpoint="$1"
  local payload="$2"
  curl -sSL -X PATCH \
    -H "${AUTH_HEADER}" \
    -H "${ACCEPT_HEADER}" \
    -H "Content-Type: application/json" \
    -d "${payload}" \
    "${GH_API}${endpoint}"
}

apply_labels() {
  local labels_json="$1"
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY RUN] Would apply labels: ${labels_json}"
    return
  fi
  gh_post "/repos/${REPO}/issues/${ISSUE_NUMBER}/labels" "{\"labels\": ${labels_json}}" > /dev/null
  echo "Applied labels: ${labels_json}"
}

add_comment() {
  local body="$1"
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY RUN] Would add comment: ${body:0:80}..."
    return
  fi
  local escaped
  escaped=$(echo "$body" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
  gh_post "/repos/${REPO}/issues/${ISSUE_NUMBER}/comments" "{\"body\": ${escaped}}" > /dev/null
  echo "Added triage comment."
}

# ---------------------------------------------------------------------------
# Fetch issue data
# ---------------------------------------------------------------------------
echo "Fetching issue #${ISSUE_NUMBER} from ${REPO}..."
ISSUE_DATA=$(gh_get "/repos/${REPO}/issues/${ISSUE_NUMBER}")

TITLE=$(echo "$ISSUE_DATA" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('title',''))")
BODY=$(echo "$ISSUE_DATA" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('body','') or '')")
CURRENT_LABELS=$(echo "$ISSUE_DATA" | python3 -c "import sys,json; d=json.load(sys.stdin); print(','.join(l['name'] for l in d.get('labels',[])))")
STATE=$(echo "$ISSUE_DATA" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('state',''))")

echo "Title   : ${TITLE}"
echo "State   : ${STATE}"
echo "Labels  : ${CURRENT_LABELS}"

if [[ "$STATE" != "open" ]]; then
  echo "Issue is not open — skipping triage."
  exit 0
fi

# ---------------------------------------------------------------------------
# Classify issue using keyword heuristics
# ---------------------------------------------------------------------------
LABELS_TO_ADD=()
COMBINED="${TITLE} ${BODY}"
COMBINED_LOWER=$(echo "$COMBINED" | tr '[:upper:]' '[:lower:]')

# Bug detection
if echo "$COMBINED_LOWER" | grep -qE '\b(bug|error|exception|traceback|crash|broken|fail|failure|not working|unexpected)\b'; then
  LABELS_TO_ADD+=("bug")
fi

# Feature request detection
if echo "$COMBINED_LOWER" | grep -qE '\b(feature|enhancement|request|add support|would be nice|suggestion|improve|proposal)\b'; then
  LABELS_TO_ADD+=("enhancement")
fi

# Documentation
if echo "$COMBINED_LOWER" | grep -qE '\b(docs|documentation|readme|guide|tutorial|example|typo|unclear)\b'; then
  LABELS_TO_ADD+=("documentation")
fi

# Question / help wanted
if echo "$COMBINED_LOWER" | grep -qE '\b(question|how to|how do i|help|confused|understand|what is|clarif)\b'; then
  LABELS_TO_ADD+=("question")
fi

# Performance
if echo "$COMBINED_LOWER" | grep -qE '\b(slow|performance|latency|memory|leak|speed|timeout|inefficient)\b'; then
  LABELS_TO_ADD+=("performance")
fi

# Security
if echo "$COMBINED_LOWER" | grep -qE '\b(security|vulnerability|cve|exploit|injection|auth|token leak)\b'; then
  LABELS_TO_ADD+=("security")
fi

# Duplicate / needs-info
if echo "$COMBINED_LOWER" | grep -qE '\b(duplicate|same as|already reported|needs more info|reproduction|repro steps)\b'; then
  LABELS_TO_ADD+=("needs-info")
fi

# ---------------------------------------------------------------------------
# Deduplicate and filter already-applied labels
# ---------------------------------------------------------------------------
UNIQUE_LABELS=()
for label in "${LABELS_TO_ADD[@]}"; do
  if [[ ",${CURRENT_LABELS}," != *",${label},"* ]]; then
    UNIQUE_LABELS+=("\"${label}\"")
  fi
done

if [[ ${#UNIQUE_LABELS[@]} -eq 0 ]]; then
  echo "No new labels to apply."
else
  LABELS_JSON="[$(IFS=','; echo "${UNIQUE_LABELS[*]}")]"
  apply_labels "$LABELS_JSON"
fi

# ---------------------------------------------------------------------------
# Post a triage summary comment
# ---------------------------------------------------------------------------
if [[ ${#UNIQUE_LABELS[@]} -gt 0 ]]; then
  LABEL_LIST=$(echo "${UNIQUE_LABELS[@]}" | tr -d '"' | tr ' ' ', ')
  COMMENT="👋 Thanks for opening this issue!\n\nThis issue has been automatically triaged and labeled: **${LABEL_LIST}**.\n\nA maintainer will review it shortly. If you have additional context or a minimal reproduction, please add it to help us resolve this faster."
  add_comment "$(printf '%b' "$COMMENT")"
fi

echo "Triage complete for issue #${ISSUE_NUMBER}."
