# Test Automation Skill

This skill automatically runs the project's test suite, reports results, and can open issues or PR comments when failures are detected.

## Overview

The test-automation skill is triggered on pull requests or on a schedule. It:

1. Installs project dependencies in a clean virtual environment
2. Runs the full test suite (pytest) with coverage reporting
3. Parses the results and generates a structured summary
4. Posts a comment on the PR (or creates an issue) with the test report
5. Fails the workflow if any tests fail or coverage drops below the threshold

## Inputs

| Variable | Description | Default |
|---|---|---|
| `GITHUB_TOKEN` | Token used to post comments/issues | required |
| `COVERAGE_THRESHOLD` | Minimum acceptable coverage % | `80` |
| `TEST_PATH` | Directory or file to run tests against | `tests/` |
| `PYTHON_VERSION` | Python version to use | `3.11` |
| `POST_COMMENT` | Whether to post a PR comment with results | `true` |
| `CREATE_ISSUE_ON_FAIL` | Open a GitHub issue if tests fail on main | `false` |

## Outputs

- `test_passed` — `true` or `false`
- `coverage_pct` — overall coverage percentage
- `failed_tests` — newline-separated list of failed test node IDs
- `report_url` — link to the uploaded HTML coverage report artifact

## Usage

Add the following to your workflow:

```yaml
- name: Run test automation skill
  uses: ./.agents/skills/test-automation
  with:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
    COVERAGE_THRESHOLD: 85
    POST_COMMENT: true
```

## How It Works

### Step 1 — Environment Setup
The script creates a fresh `venv`, installs `.[dev]` (or `requirements-dev.txt` if present), and ensures `pytest`, `pytest-cov`, and `pytest-json-report` are available.

### Step 2 — Test Execution
`pytest` is invoked with `--cov`, `--cov-report=xml`, `--cov-report=html`, and `--json-report` flags so results can be parsed programmatically.

### Step 3 — Result Parsing
The JSON report is read to extract pass/fail counts, duration, and individual failure messages. Coverage XML is parsed for the overall line-coverage percentage.

### Step 4 — Reporting
A Markdown summary is constructed and posted as a PR review comment via the GitHub REST API. If running on the default branch and `CREATE_ISSUE_ON_FAIL=true`, a new issue is opened instead.

### Step 5 — Artifact Upload
The HTML coverage report is uploaded as a workflow artifact so developers can browse detailed coverage information.

## Notes

- The skill respects `pyproject.toml` or `setup.cfg` pytest configuration if present.
- If no tests are found, the skill exits with a warning rather than a failure.
- Coverage threshold comparison uses integer truncation (e.g., 84.9% does **not** meet an 85% threshold).
