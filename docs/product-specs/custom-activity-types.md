# Custom Activity Types

Activity types are user-configurable. Instead of a fixed set of categories, users define their own activity types, each with a name, a description and a group. The LLM uses these definitions when classifying screenshots.

## Activity Groups

Every activity type belongs to one of three groups:

| Group | Id | Meaning |
|-------|----|---------|
| Work | `work` | The job |
| Personal Projects | `personal_projects` | Side projects, learning, own writing and making |
| Personal | `personal` | Everything else — the residual group |

A machine does not declare which groups it uses: it has a group when it has types in that group. No group has to be populated.

An entry stores only its type id, so the group comes from the type and re-labelling a type re-groups history. An entry whose type id is no longer configured — because the type was deleted or renamed — reports as **Unclassified**. It is never folded into a group it was not labelled with.

## Activity Type Definition

Each activity type has:

| Field | Description | Constraints |
|-------|-------------|-------------|
| Name | Short label (e.g. "Work Coding", "YouTube Entertainment") | Non-empty, max 50 characters, unique across all groups |
| Description | Context for the LLM (e.g. "Writing code, using IDEs") | Non-empty, max 200 characters |
| Group | `work`, `personal_projects` or `personal` | — |

The name "idle" is reserved for system use. Maximum 30 total types.

A set of 16 default types is provided and can be restored at any time via "Reset to Defaults". They are written automatically only when no activity types exist at all, for the machine where nobody opens the GUI.

### Migration from the work/personal flag

Activity types used to carry a work/personal boolean. An existing database is migrated in place, without renaming any id:

| Existing row | New group |
|--------------|-----------|
| work | `work` |
| `professional_development` | `personal_projects` |
| `personal_ai_use` | `personal_projects` |
| any other non-work type | `personal` |

Only ids Zeit itself shipped are remapped by name — guessing a group for a user-written type would record wrong knowledge.

## Where Activity Types Are Configured

Activity types can be managed in three places:

- **Onboarding** - A dedicated step after model download, pre-filled with defaults. Two lists — work, and everything else — that can be edited, extended, or cleared entirely.
- **Settings > Activity Types** - Same editing interface, accessible any time from the menubar.
- **CLI** - `zeit list-activity-types` to view, `zeit set-activity-types` to update.

### CLI Usage

```bash
# List configured types, grouped
zeit list-activity-types

# Set the types of one or more groups (semicolon-separated Name: Description pairs)
zeit set-activity-types \
  --group work --types "Coding: Code in company repositories; Meetings: Video calls" \
  --group personal --types "Browsing: Reading news and articles"
```

`--group` and `--types` are repeatable and paired by position. A group named on the command line is replaced; a group not named keeps the types it has.

## How Activity Types Affect Tracking

The classification prompt is built dynamically from the configured types, one section per group that has types in it. Each type's id and description are included so the LLM understands what to look for. The structured output schema constrains the model to only produce valid activity IDs, ensuring classifications always map to a configured type.

Types in different groups can look alike on screen — work coding and project coding are both an editor and a terminal — so the prompt asks the model to decide from the visible content, and the descriptions have to name what separates them.

Changes to activity types take effect on the next tracking iteration.

## Validation Rules

- Names and descriptions must be non-empty
- Names max 50 characters, descriptions max 200 characters
- Names must be unique across all groups
- At least 1 type overall; no individual group has to be populated
- Maximum 30 total types
- "idle" is reserved and cannot be used as a type name

These rules are enforced in both the UI and CLI.
