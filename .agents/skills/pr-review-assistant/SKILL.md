# PR Review Assistant Skill

This skill provides automated pull request review capabilities, analyzing code changes for quality, consistency, and potential issues.

## Overview

The PR Review Assistant skill helps maintainers and contributors by:
- Analyzing diffs for common issues (style, logic, security)
- Checking that tests are included for new functionality
- Verifying documentation is updated alongside code changes
- Summarizing the impact and scope of changes
- Flagging breaking changes or deprecations

## Usage

This skill is triggered on pull request events and can also be invoked manually.

### Inputs

| Input | Description | Required |
|-------|-------------|----------|
| `pr_number` | The pull request number to review | Yes |
| `repo` | Repository in `owner/repo` format | Yes |
| `focus_areas` | Comma-separated list of focus areas (e.g. `security,tests,docs`) | No |
| `severity_threshold` | Minimum severity to report (`info`, `warning`, `error`) | No (default: `warning`) |

### Outputs

| Output | Description |
|--------|-------------|
| `review_summary` | High-level summary of the PR |
| `issues_found` | JSON array of issues detected |
| `approval_recommendation` | `approve`, `request_changes`, or `comment` |
| `breaking_changes` | Boolean indicating if breaking changes were detected |

## Configuration

The skill can be configured via environment variables:

```bash
PR_REVIEW_SEVERITY_THRESHOLD=warning
PR_REVIEW_FOCUS_AREAS=security,tests,docs,style
PR_REVIEW_MAX_FILES=50
PR_REVIEW_IGNORE_PATTERNS=*.lock,*.min.js
```

## Focus Areas

### Security
- Detects hardcoded secrets or credentials
- Flags use of deprecated/insecure APIs
- Checks for input validation on public interfaces

### Tests
- Verifies new public functions have corresponding tests
- Checks test coverage delta if coverage reports are available
- Flags test files that were modified without corresponding source changes

### Documentation
- Ensures public API changes include docstring updates
- Checks that CHANGELOG or release notes are updated for significant changes
- Validates that README reflects any new features or configuration options

### Style
- Enforces consistent code style with project conventions
- Checks for overly complex functions (cyclomatic complexity)
- Flags TODO/FIXME comments added in the PR

## Integration

This skill integrates with:
- GitHub Actions (via `agents/openai.yaml`)
- The `code-change-verification` skill for deeper static analysis
- The `docs-sync` skill to trigger documentation updates when needed

## Examples

```bash
# Review a specific PR
bash scripts/run.sh --pr 42 --repo myorg/myrepo

# Review with specific focus areas
bash scripts/run.sh --pr 42 --repo myorg/myrepo --focus security,tests

# Review with lower severity threshold to see all info-level notes
bash scripts/run.sh --pr 42 --repo myorg/myrepo --severity info
```
