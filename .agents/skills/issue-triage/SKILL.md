# Issue Triage Skill

Automatically triages new GitHub issues by analyzing content, applying labels, assigning priority, and routing to appropriate team members.

## Overview

This skill monitors incoming GitHub issues and performs automated triage to reduce manual overhead and ensure issues are properly categorized and routed.

## Capabilities

- **Label Assignment**: Automatically applies relevant labels (bug, enhancement, documentation, question, etc.) based on issue content analysis
- **Priority Detection**: Identifies high-priority issues (crashes, security vulnerabilities, data loss) and escalates appropriately
- **Duplicate Detection**: Searches existing issues for potential duplicates and links them
- **Template Validation**: Checks if the issue follows the project's issue template and requests missing information
- **Routing**: Suggests or assigns appropriate maintainers based on affected components
- **Response Generation**: Posts an initial acknowledgment comment with next steps

## Trigger

This skill is triggered when:
- A new issue is opened
- An issue is reopened
- An issue is edited (re-triage if significant changes detected)

## Configuration

```yaml
skill: issue-triage
triggers:
  - event: issues
    types: [opened, reopened, edited]
```

## Inputs

| Input | Description | Required |
|-------|-------------|----------|
| `github_token` | GitHub token with issues read/write permissions | Yes |
| `issue_number` | The issue number to triage | Yes |
| `repo` | Repository in `owner/repo` format | Yes |
| `openai_api_key` | OpenAI API key for content analysis | Yes |

## Outputs

| Output | Description |
|--------|-------------|
| `labels_applied` | List of labels that were applied |
| `priority` | Detected priority level (critical/high/medium/low) |
| `duplicate_of` | Issue number if duplicate detected, null otherwise |
| `assigned_to` | GitHub username assigned, null if unassigned |
| `comment_posted` | Boolean indicating if acknowledgment was posted |

## Label Schema

The skill uses the following label categories:

- **Type**: `bug`, `enhancement`, `documentation`, `question`, `chore`
- **Priority**: `priority: critical`, `priority: high`, `priority: medium`, `priority: low`
- **Status**: `needs-info`, `needs-reproduction`, `triaged`
- **Component**: `component: agents`, `component: tools`, `component: tracing`, `component: docs`

## Priority Detection Rules

- **Critical**: Keywords like `crash`, `security`, `data loss`, `broken`, `not working at all`
- **High**: Regressions, major feature breakage, affects many users
- **Medium**: Standard bugs, feature requests with clear use case
- **Low**: Minor issues, cosmetic bugs, nice-to-have enhancements

## Duplicate Detection

Searches open and recently closed issues using semantic similarity. If a potential duplicate is found with >85% confidence, the skill will:
1. Comment on the new issue linking to the potential duplicate
2. Apply the `possible-duplicate` label
3. Request the reporter to confirm

## Usage

```bash
# Run manually for a specific issue
bash .agents/skills/issue-triage/scripts/run.sh --issue 42 --repo owner/repo

# Run with dry-run mode (no changes applied)
bash .agents/skills/issue-triage/scripts/run.sh --issue 42 --repo owner/repo --dry-run
```

## Notes

- The skill respects existing labels and will not remove manually applied labels
- Maintainer assignments are suggestions only unless `auto_assign=true` is configured
- All actions are logged for audit purposes
