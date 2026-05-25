# Release Automation Skill

Automates the release process for the openai-agents-python package, including version bumping, changelog consolidation, PyPI publishing preparation, and GitHub release creation.

## Overview

This skill handles end-to-end release automation:
1. Determines the next version based on conventional commits or explicit input
2. Updates version references across the codebase
3. Consolidates changelog entries
4. Creates a release commit and tag
5. Prepares the release for PyPI publishing
6. Drafts a GitHub release with auto-generated notes

## Trigger

This skill can be triggered:
- Manually via workflow dispatch with an explicit version bump type (`patch`, `minor`, `major`)
- Automatically when a release branch is merged into `main`

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `bump_type` | Version bump type: `patch`, `minor`, or `major` | No | `patch` |
| `dry_run` | If `true`, performs all steps without pushing or publishing | No | `false` |
| `prerelease` | If `true`, creates a pre-release (e.g., `1.2.0-beta.1`) | No | `false` |

## Outputs

- Updated `pyproject.toml` with new version
- Updated `src/agents/__init__.py` version constant
- Consolidated `CHANGELOG.md` entry
- Git tag matching the new version
- GitHub release draft

## Steps

### 1. Version Determination
Reads current version from `pyproject.toml` and applies the requested bump type using semver rules.

### 2. File Updates
- `pyproject.toml`: Updates `version` field
- `src/agents/__init__.py`: Updates `__version__` constant
- `CHANGELOG.md`: Prepends new release section with date and version

### 3. Build Verification
Runs `python -m build` and verifies the dist artifacts are valid using `twine check`.

### 4. Git Operations
Creates a signed commit with message `chore(release): bump version to vX.Y.Z`, then creates an annotated tag.

### 5. GitHub Release
Uses the GitHub API to create a draft release with:
- Auto-generated release notes from merged PRs
- Link to full changelog
- Dist artifacts attached

## Configuration

The skill reads configuration from `.agents/skills/release-automation/agents/openai.yaml`.

## Required Secrets

- `GITHUB_TOKEN`: For creating releases and pushing tags
- `PYPI_API_TOKEN`: For publishing to PyPI (only used when `dry_run=false`)

## Notes

- All releases must pass CI checks before the skill proceeds
- The skill will abort if there are uncommitted changes in the working tree
- Pre-releases are published to PyPI with the `--pre` flag visible to users who opt in
