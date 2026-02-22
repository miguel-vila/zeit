# Custom Activity Types

Activity types are user-configurable. Instead of a fixed set of categories, users define their own work and personal activity types, each with a name and description. The LLM uses these definitions when classifying screenshots.

## Activity Type Definition

Each activity type has:

| Field | Description | Constraints |
|-------|-------------|-------------|
| Name | Short label (e.g. "Work Coding", "YouTube Entertainment") | Non-empty, max 50 characters, unique across all types |
| Description | Context for the LLM (e.g. "Writing code, using IDEs") | Non-empty, max 200 characters |
| Category | Work or personal | At least 1 of each required |

The name "idle" is reserved for system use. Maximum 30 total types.

A set of 16 default types is provided and can be restored at any time via "Reset to Defaults".

## Where Activity Types Are Configured

Activity types can be managed in three places:

- **Onboarding** - A dedicated step after permissions, pre-filled with defaults. Two lists (work and personal) that can be edited, extended, or cleared entirely.
- **Settings > Activity Types** - Same editing interface, accessible any time from the menubar.
- **CLI** - `zeit list-activity-types` to view, `zeit set-activity-types` to update.

### CLI Usage

```bash
# List configured types
zeit list-activity-types

# Set types (semicolon-separated Name: Description pairs)
zeit set-activity-types --work "Coding: Writing code, using IDEs; Meetings: Video calls" \
                        --personal "Browsing: Reading news and articles; Social Media: Leisure browsing"
```

If only `--work` is provided, existing personal types are preserved (and vice versa).

## How Activity Types Affect Tracking

The classification prompt is built dynamically from the configured types. Each type's name and description are included so the LLM understands what to look for. The structured output schema constrains the model to only produce valid activity IDs, ensuring classifications always map to a configured type.

Changes to activity types take effect on the next tracking iteration.

## Validation Rules

- Names and descriptions must be non-empty
- Names max 50 characters, descriptions max 200 characters
- Names must be unique across both work and personal categories
- At least 1 work and 1 personal type required
- Maximum 30 total types
- "idle" is reserved and cannot be used as a type name

These rules are enforced in both the UI and CLI.
