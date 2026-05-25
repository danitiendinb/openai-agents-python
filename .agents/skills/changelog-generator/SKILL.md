# Changelog Generator Skill

Automatically generates and updates CHANGELOG.md based on merged pull requests and commit history since the last release.

## Overview

This skill analyzes the Git history and GitHub pull requests to produce a structured, human-readable changelog following the [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) format. It groups changes by type (Added, Changed, Deprecated, Removed, Fixed, Security) and links each entry back to the relevant PR or commit.

## Trigger

This skill is triggered:
- Manually via workflow dispatch (specifying a version tag)
- Automatically when a new release tag is pushed (e.g., `v*.*.*`)
- On a scheduled basis to generate a draft for the upcoming release

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `version` | The version string for the new changelog entry (e.g., `1.2.0`) | Yes | — |
| `since_tag` | The previous release tag to diff from | No | latest tag |
| `dry_run` | If `true`, prints the changelog without writing to file | No | `false` |

## Process

1. **Determine range** — Identify the previous release tag and the current HEAD (or specified tag).
2. **Collect PRs and commits** — Query merged PRs and commits in the range using the GitHub API and `git log`.
3. **Classify changes** — Map PR labels and conventional commit prefixes to changelog categories:
   - `feat` / label `enhancement` → **Added**
   - `fix` / label `bug` → **Fixed**
   - `refactor`, `perf` → **Changed**
   - `deps` / label `dependencies` → **Changed** (dependency updates)
   - `security` / label `security` → **Security**
   - `deprecate` → **Deprecated**
   - `remove` → **Removed**
4. **Generate entry** — Render the Markdown section for the new version with today's date.
5. **Prepend to CHANGELOG.md** — Insert the new section at the top of the existing file, preserving history.
6. **Commit and push** — Create a commit `chore: update CHANGELOG for vX.Y.Z` on the current branch (or open a PR if on a protected branch).

## Output

- Updated `CHANGELOG.md` committed to the repository.
- A summary comment posted to the triggering PR or release (if applicable).

## Dependencies

- `gh` CLI (GitHub CLI) — for querying PRs and posting comments
- `git` — for commit range and log
- `python3` — for Markdown rendering and file manipulation
- `GITHUB_TOKEN` environment variable with `contents: write` and `pull-requests: write` permissions

## Notes

- Commits without a conventional prefix and not linked to a labeled PR are placed under **Changed** with a note.
- Merge commits and bot commits (e.g., Dependabot, github-actions) are filtered out unless they carry a `security` label.
- The skill respects a `.changelogignore` file at the repo root — any PR number or commit SHA listed there is excluded.
