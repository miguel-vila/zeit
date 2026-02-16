# Custom Activity Types

## Objective

Allow users to list and describe their own activity types by providing a list of
personal and work-related activities, instead of using predefined ones.

This feature requires doing it as part of the app onboarding, after setting up
the permissions. The user will have to specify the list of work-related activity
types and the list of personal-related activity types.

For each activity type, the user will have to provide:

- A short name (e.g. "Work Coding", "YouTube Entertainment", etc...)
- A description (e.g. "Writing code, using IDEs", "Watching YouTube videos for entertainment", etc...)

The short name should be a unique identifier for the activity type, while the description should provide more context about what the activity type entails.

## Affected Areas

- Onboarding flow: Add a step to allow users to input their custom activity types. This will have to be two separate lists: one for work-related activities and one for personal-related activities. It should be pre-filled with the current activity types, but allow users to edit them and add new ones. Include a clear button to delete all activity types and start from scratch.
- Settings screen: Add a section to allow users to view and edit their custom activity types. This should also allow users to add new activity types, edit existing ones, and delete them. The UI should be similar to the onboarding step for consistency.
- Activity tracking: When tracking activities, the app should use the most up-to-date list of activity types from the database, instead of a hardcoded list. This will allow users to have their custom activity types reflected in the tracking and reporting features. This will involve updating the prompt building logic to fetch the activity types from the database and include them in the prompts for activity classification. The descriptions provided by the user should also be included in the prompts to help the model understand the context of each activity type.
- Add a cli command to list the current activity types and their descriptions. This will be useful for users to quickly see their configured activity types without having to open the app.
- Add a cli command to set the activity types and their descriptions. This will allow users to configure their activity types directly from the command line, which can be faster for some users and also allows for scripting and automation. It could be something like `zeit set-activity-types --work "Work Coding: Writing code, using IDEs; Work Meetings: Attending meetings, video calls, etc..." --personal "YouTube Entertainment: Watching YouTube videos for entertainment; Social Media: Browsing social media platforms for leisure"` (; separated). The command should parse the input and update the database with the new activity types and their descriptions.

## Implementation Details

- Persistence: This information should be stored in the app's local database (the SQLite database) in a separate table.
- Data model: Right now we have a hardcoded Activity type. This will need updating to a more flexible data model, maybe making it a struct with a name and description, and then having a list of these structs for work-related activities and another list for personal-related activities. The database schema will also need to be updated to accommodate this new data model.
- Input validation: Activity names must be non-empty, max 50 characters, and unique across both work and personal categories. Descriptions must be non-empty, max 200 characters. The generated snake_case ID must not be "idle" (reserved for system use). There must be at least 1 work and 1 personal type. Maximum 30 total types to keep LLM prompts within token limits. These rules are enforced in both the UI (disabling Continue/Save until valid) and the CLI (`validate()` method).
- Dynamic structured output schema: The classification pipeline uses MLX's structured output feature, which provides a JSON schema that constrains the model's token generation. The schema's `main_activity` field has an `"enum"` constraint listing all valid activity IDs. This enum is built dynamically from the user's configured types plus "idle", so the LLM is constrained at the generation level to only produce valid activity IDs — not just via prompt instructions, but as a hard constraint on the output space.
- Reset to Defaults: In addition to the clear button, the UI includes a "Reset to Defaults" button that restores the 16 built-in activity types. This provides a quick way to undo customizations without having to re-enter everything manually.
