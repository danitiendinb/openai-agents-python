# Dependency Update Skill

This skill automates the process of checking for outdated dependencies, evaluating update safety, and preparing pull requests with dependency updates.

## Overview

The dependency update skill helps maintain project health by:
- Scanning `pyproject.toml`, `requirements*.txt`, and `setup.py` for dependencies
- Checking for newer versions on PyPI
- Evaluating breaking changes via changelog/release notes analysis
- Grouping updates by risk level (patch, minor, major)
- Generating a structured update report
- Optionally applying updates and running the test suite to verify compatibility

## Trigger

This skill can be triggered:
- On a schedule (e.g., weekly via cron)
- Manually via workflow dispatch
- When a `dependencies` label is added to an issue

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `update_type` | Which updates to apply: `patch`, `minor`, `all` | No | `patch` |
| `dry_run` | Report only, do not apply changes | No | `true` |
| `auto_pr` | Automatically open a PR with changes | No | `false` |
| `exclude` | Comma-separated list of packages to skip | No | `` |

## Outputs

- **Report**: Markdown-formatted table of available updates with risk assessment
- **PR** (optional): A pull request with applied updates and test results
- **Summary**: JSON file at `.agents/artifacts/dependency-report.json`

## Risk Classification

| Level | Criteria | Auto-apply |
|-------|----------|------------|
| 🟢 Patch | `x.y.Z` bump, no API changes | Yes (if `update_type=patch`) |
| 🟡 Minor | `x.Y.z` bump, backwards-compatible additions | Yes (if `update_type=minor`) |
| 🔴 Major | `X.y.z` bump, potential breaking changes | Manual review required |

## Steps

1. **Discover** — Parse all dependency files and collect pinned/ranged versions
2. **Fetch** — Query PyPI JSON API for latest versions
3. **Classify** — Determine semver bump level for each outdated package
4. **Analyze** — Fetch changelog/release notes and summarize breaking changes using the agent
5. **Report** — Write structured report to stdout and artifact file
6. **Apply** (optional) — Update version specifiers in source files
7. **Verify** (optional) — Run `pytest` to confirm no regressions
8. **PR** (optional) — Commit changes and open a pull request

## Example Output

```
## Dependency Update Report — 2024-01-15

### 🟢 Patch Updates (safe to apply)
| Package | Current | Latest | Changelog |
|---------|---------|--------|-----------|
| httpx | 0.26.0 | 0.26.1 | Bug fixes |
| pydantic | 2.5.3 | 2.5.4 | Perf improvements |

### 🟡 Minor Updates (review recommended)
| Package | Current | Latest | Notes |
|---------|---------|--------|-------|
| openai | 1.12.0 | 1.15.0 | New streaming helpers added |

### 🔴 Major Updates (manual review required)
| Package | Current | Latest | Breaking Changes |
|---------|---------|--------|------------------|
| pydantic | 2.5.4 | 3.0.0 | Model config API changed |
```

## Configuration

Add a `.agents/skills/dependency-update/config.yaml` to customize behavior per-repository.

## Notes

- The skill respects version constraints in `pyproject.toml` and will not suggest updates outside allowed ranges unless `--force` is passed
- Security vulnerabilities (via `pip-audit`) are always flagged regardless of `update_type`
- The skill integrates with the `code-change-verification` skill to run tests after applying updates
