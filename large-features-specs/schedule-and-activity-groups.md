# Per-Machine Schedule and Activity Groups

**Status:** proposed | **Date:** 2026-11-03

## Why

Zeit assumes one machine, used for work, inside one daily window. Two assumptions are baked in:

- `work_hours` is the only schedule, and the tracker returns early outside it (`TrackCommand` → `CLITrackingHelper.isWithinWorkHours`).
- `activity_types.is_work` is a boolean, so every activity is work or not-work, and the menubar shows one "work %".

The target setup is two machines: a personal MacBook tracking all day, where the time that matters is side projects, and a work laptop tracking during work hours, where the time that matters is the job. Both machines also need work *and* personal categories, because work gets checked from the personal Mac and personal browsing happens on the work laptop.

This spec splits the two assumptions into two independent settings — **when the machine tracks** and **how activities are grouped** — each configured per machine. Any machine can hold any combination.

Synchronising data between machines is out of scope. See [Out of scope](#out-of-scope).

## Axis 1 — Schedule

A machine either tracks always, or tracks inside a list of windows.

```yaml
tracking:
  schedule: always
  interval_seconds: 300
  skip_on_battery: true
  day_start_hour: 0
```

```yaml
tracking:
  schedule:
    windows:
      - days: ['mon', 'tue', 'wed', 'thu', 'fri']
        from: '09:00'
        to: '13:00'
      - days: ['mon', 'tue', 'wed', 'thu', 'fri']
        from: '14:00'
        to: '18:00'
  interval_seconds: 60
  skip_on_battery: false
  day_start_hour: 0
```

`always` is a value of the same field as `windows`, so "always on, but only 09:00–17:30" cannot be written.

### Semantics

| Rule | Behaviour | Reason |
|------|-----------|--------|
| Union | A moment is tracked when **any** window contains it | Overlapping windows need no validation |
| Overnight | When `to <= from`, the window ends on the following day; `days` names the start day | `20:00 → 01:00` is a normal evening window on a personal Mac |
| Empty list | `windows: []` is rejected at load; falls back to the previous valid value and logs | A silent "never track" is worse than a loud fallback |
| Cadence | `interval_seconds` is honoured by the tracker, not by launchd | The plist stays at `StartInterval 60`; changing cadence needs no service reinstall, and the plist cannot disagree with the config |
| Battery | With `skip_on_battery: true`, an iteration is skipped while on battery power | A 60 s cadence with a 4B vision model plus an 8B text model, all day, is the dominant cost of always-on tracking |
| Day start | An entry belongs to the day that started at `day_start_hour` local time. The default, `0`, is today's calendar-day behaviour | An evening window crossing midnight otherwise splits one session across two days; setting `4` keeps a late session on the day it began |

`interval_seconds` is enforced by comparing the newest entry's timestamp against the configured interval at the start of `track`. launchd fires every 60 s; the tracker decides whether this tick is due.

### Renames

The schedule is no longer about work, so the work vocabulary goes:

| Before | After |
|--------|-------|
| `ZeitConfig.WorkHoursConfig` | `ZeitConfig.ScheduleConfig` |
| `WorkHoursConfig.workDays` | `ScheduleWindow.days` |
| `TrackingClient.isWithinWorkHours` | `TrackingClient.isWithinSchedule` |
| `TrackingClient.getWorkHoursMessage` | `TrackingClient.getScheduleMessage` |
| `TrackingState` case for outside hours | case for outside schedule |
| `zeit set-work-hours` | `zeit schedule` (old name kept as an alias) |
| Settings tab "Work Hours" | Settings tab "Schedule" |

`ZeitConfig.Weekday` is unchanged. The YAML parser keeps reading a legacy `work_hours:` block as a single window, the same way it already accepts two formats for the hour fields.

## Axis 2 — Classification

`ActivityType.isWork: Bool` becomes `ActivityType.group: ActivityGroup`, a closed enum:

```swift
enum ActivityGroup: String, Codable, Sendable, CaseIterable {
    case work
    case personalProjects = "personal_projects"
    case personal
}
```

A machine does not declare which groups it uses. It has a group when it has types in that group, so no stored list can disagree with the types. The onboarding question is a seed for the type selection, not a persisted mode.

### Primary group

One group per machine is primary. It is the number the menubar icon shows and the group the day is judged by.

```yaml
classification:
  primary_group: personal_projects
```

The three groups are not symmetric as goals: `personal` is the residual group, measured against and never for. That asymmetry lives only in the onboarding copy and the seed defaults. The enum stays flat and no breakdown function special-cases a group.

### Suggestions versus the user's set

Today `ActivityType.defaultTypes` is both the suggestion list and the set auto-written by `ensureDefaultActivityTypes`. These separate:

- **`ActivityCatalog.suggestions`** — a code constant, grouped, larger than any one selection. Never written automatically.
- **`activity_types` table** — only what the user accepted or wrote. Onboarding ends its classification step with `saveActivityTypes(selection)`, which already replaces the whole set.
- **Auto-seeding** stays, for the machine where nobody opens the GUI. It writes one small starter set and does not read `conf.yml`: the database layer must not start depending on config to decide what to insert. Onboarding overwrites it one screen later.

Two properties of the existing code make picking cheap:

- Unselecting is reversible for free. Ids come from `ActivityType.generateID(from:)`, so re-adding "Social Media" regenerates `social_media` and old entries reconnect.
- Unselecting a type with history orphans its entries. `computeActivityBreakdown` currently relabels any unknown id as personal; that silent default is removed and replaced by an explicit **Unclassified** bucket (see [Data model](#data-model)).

### The separability constraint

Every suggestion must be separable from a 1–2 sentence screen description, because that is the only input the classifying model gets. "Code Review" against "Coding" passes: a pull request page does not look like an IDE. "Work AI Use" against "Coding" fails: both are an editor with a chat panel beside it. A catalog that fails this test does not produce finer data; it produces noise and a longer prompt.

The hard cases are the cross-group twins — coding, email, browsing and messaging exist in two or three groups and look identical on screen. Their only discriminator is content: which repository, which domain, which account. For those, the *description* does the work and it has to name the user's own specifics:

```
work_coding          Code in company repositories, work IDE windows
project_coding       Code in personal repositories — e.g. ~/repos/me
```

The catalog ships generic descriptions and marks the twins as needing detail. The picker shows descriptions inline and editable, so a user cannot select a twin pair without being shown the text that separates them. A checkbox-only picker would quietly produce a bad classifier.

### Catalog

25 suggestions against a 30-type cap. The cap applies to the selection; a sensible selection is 8 to 14 types. The UI states this, with the reason: every selected type costs prompt tokens and, past a point, costs accuracy.

Rows marked ✱ are twins whose description needs user-specific detail before they separate.

**work**

| Id | Name | Description | |
|----|------|-------------|---|
| `work_coding` | Work Coding | Code in company repositories, work IDE windows | ✱ |
| `code_review` | Code Review | Pull requests, diffs, review comments | ✱ |
| `meetings` | Meetings | Video calls and meetings | |
| `work_chat` | Work Chat | Slack, Teams, work group chat | |
| `work_email` | Work Email | Work email client or webmail | ✱ |
| `tickets_planning` | Tickets & Planning | Jira, boards, sprint planning | |
| `work_docs` | Work Docs & Writing | Confluence, specs, design documents | ✱ |
| `work_research` | Work Research | Work-related documentation and web research | ✱ |
| `work_calendar` | Work Calendar | Work calendar and scheduling | |

**personal_projects**

| Id | Name | Description | |
|----|------|-------------|---|
| `project_coding` | Project Coding | Code in personal repositories and side projects | ✱ |
| `project_writing` | Project Writing & Design | Notes, design documents and planning for own projects | ✱ |
| `learning` | Learning | Courses, tutorials, documentation read to learn | |
| `reading` | Reading | Technical articles, papers, long-form reading | |
| `writing_publishing` | Writing & Publishing | Blog posts, newsletters, publishing tools | |
| `creative_practice` | Creative Practice | Music, drawing, photography, other making | |

**personal**

| Id | Name | Description | |
|----|------|-------------|---|
| `personal_browsing` | Personal Browsing | General web browsing, not work and not a project | |
| `social_media` | Social Media | X, Instagram, Reddit, TikTok, LinkedIn feed | |
| `video` | Video & YouTube | YouTube and video watching for leisure | |
| `entertainment` | Entertainment | Games, films, music, streaming | |
| `messaging` | Personal Messaging | WhatsApp, iMessage, personal chat | |
| `personal_email` | Personal Email | Personal email accounts | ✱ |
| `finances` | Finances | Banking, budgeting, investments | |
| `shopping` | Shopping | Online shopping and marketplaces | |
| `life_admin` | Life Admin | Appointments, forms, travel, personal calendar | |
| `news` | News | News sites and news apps | |

Changes against today's 16 defaults:

- `slack` → `work_chat` and `zoom_meeting` → `meetings`: the category is not the vendor.
- `professional_development` → `learning`, in `personal_projects`.
- `personal_calendar` is absorbed by `life_admin`.
- `youtube_entertainment` → `video`.
- `personal_ai_use` is dropped from the suggestions: "using AI tools for personal projects" is `project_coding`, and the pair fails the separability test. An existing selection keeps it, because its entries reference the id; the picker shows it as a user type and it is not offered again once removed.
- New: `code_review`, `tickets_planning`, `work_docs`, `work_research`, `project_coding`, `project_writing`, `reading`, `writing_publishing`, `creative_practice`, `messaging`, `news`.

The renamed entries are **new ids**. The migration never renames an existing id, because entries reference ids. A migrated user keeps `slack` and `zoom_meeting` until they choose the new ones, and swapping moves the old entries to Unclassified — stated in the confirmation dialog.

### Pre-selection

After the primary-group answer, the picker starts with:

- the primary group's core types,
- the common `personal` types,
- a small `work` set when `work` is not primary: `work_chat`, `work_email`, `meetings`.

Editing from there is mostly subtractive.

| Primary group | Pre-selected |
|---------------|--------------|
| `work` | `work_coding`, `code_review`, `meetings`, `work_chat`, `work_email`, `tickets_planning`, `work_research` + `personal_browsing`, `social_media`, `video`, `messaging` |
| `personal_projects` | `project_coding`, `learning`, `reading`, `project_writing` + `work_chat`, `work_email`, `meetings` + `personal_browsing`, `social_media`, `video`, `entertainment`, `messaging` |

## Data model

### `activity_types`

`is_work INTEGER NOT NULL` → `activity_group TEXT NOT NULL`. `group` alone is a SQL keyword.

The schema is created today with `CREATE TABLE IF NOT EXISTS` in two places (`DatabaseClient.createTablesIfNeeded`, `DatabaseHelper`), with no migration mechanism. This change introduces a GRDB `DatabaseMigrator` shared by both paths, with the column change as its first registered migration after a baseline.

Migration mapping:

| Existing row | New group |
|--------------|-----------|
| `is_work = 1` | `work` |
| `professional_development` | `personal_projects` |
| `personal_ai_use` | `personal_projects` (dropped from the catalog, kept in an existing selection) |
| any other `is_work = 0` | `personal` |

Only ids Zeit itself shipped are remapped by name. Guessing a group for a user-written type would write wrong knowledge into a migration.

### `ActivityStat`

```swift
struct ActivityStat {
    let activity: Activity
    let count: Int
    let percentage: Double
    let group: ActivityGroup?   // nil = the type no longer exists
}
```

`category` is replaced by `group`. `idle` keeps its own treatment, excluded from breakdowns unless `includeIdle` is set. `workPercentage(from:)` becomes `share(of:in:)` over a group. A `nil` group renders as **Unclassified** and never silently counts as personal.

The group lives on the type only, never copied onto an entry. Re-labelling a type therefore re-groups history, which is the current behaviour and keeps one source of truth.

### `ActivityEntry`

Add `let device: String?`, filled from the host name at capture.

Entries are stored as a JSON array inside `daily_activities`, so existing rows decode with `nil` and no migration is needed. This costs one optional field now and is unrecoverable later: without it, any future export and import of two machines produces a merged day that cannot be split again. Nothing else about devices is in scope — no device table, no identity, no sync.

## Configuration

Full config, personal MacBook:

```yaml
device:
  name: 'Personal MBP'

tracking:
  schedule: always
  interval_seconds: 300
  skip_on_battery: true
  day_start_hour: 0

classification:
  primary_group: personal_projects

models:
  vision: 'qwen3-vl:4b'
  text:
    provider: 'mlx'
    model: 'qwen3:8b'
```

Full config, work laptop:

```yaml
device:
  name: 'Work MBP'

tracking:
  schedule:
    windows:
      - days: ['mon', 'tue', 'wed', 'thu', 'fri']
        from: '09:00'
        to: '17:30'
  interval_seconds: 60
  skip_on_battery: false
  day_start_hour: 0

classification:
  primary_group: work

models:
  vision: 'qwen3-vl:4b'
  text:
    provider: 'mlx'
    model: 'qwen3:8b'
```

| Key | Default | Notes |
|-----|---------|-------|
| `device.name` | host name | Display only |
| `tracking.schedule` | one window, Mon–Fri 09:00–17:30 | `always` or `windows:` |
| `tracking.interval_seconds` | 60 | Minimum 60, the launchd tick |
| `tracking.skip_on_battery` | `false` | |
| `tracking.day_start_hour` | 0 | Midnight, unchanged from today. Set `4` when an evening window crosses midnight |
| `classification.primary_group` | `work` | |

Legacy: a `work_hours:` block is read as a single window with its `work_days` as `days`. Writes always use the new shape.

## User-facing surface

### Onboarding

The four steps stay. Step 3 and step 4 change.

1. Permissions — unchanged.
2. Model download — unchanged.
3. **Activities.** Opens with the question "What do you want to spend your time on?" and two answers, **My job** and **My own projects**, which set the primary group. The type picker below is pre-selected per the table above. Each row shows an editable name and description; twins are flagged with a hint to add what separates them. Under each group's selected rows is a line of unselected suggestion chips (`+ Code Review`, `+ Learning`); one click adds the type with its description and removes the chip. "Reset to Defaults" becomes "Reset to suggested set". A counter shows the selection size against the 30 cap, with the note that 8 to 14 types classify best.
4. **Schedule.** A segmented control, **Always** or **Windows**. Under Windows, a list of rows built from the existing `WorkHoursPickerView`, with add and remove; one row looks exactly like today's picker so the common case does not read as a schedule editor. Below: cadence and "pause while on battery".

### Settings

- "Work Hours" tab → **Schedule**, the same control as onboarding step 4.
- "Activity Types" tab → three group sections, suggestion chips, and the primary-group picker (all three groups selectable here).
- Unselecting a type with entries in the current day shows a confirmation naming the count and saying those entries become Unclassified.

### Menubar

The icon keeps its percentage, now the primary group's share of non-idle tracked entries, with the group's label in the popover ("Projects 41%", "Work 62%"). The popover lists the three groups with their shares, then the per-type breakdown, then Unclassified when non-empty. The pause control stays at the top: it matters far more under an always-on schedule.

### Details panel

`DetailsView`'s hardcoded Work and Personal sections become one section per group with types in it, plus Unclassified when non-empty. Group colours: work, projects, personal, and grey for Unclassified — `MenubarView` currently picks green or blue from `isWork`.

### CLI

```bash
zeit schedule show
zeit schedule always
zeit schedule set --days mon-fri --from 09:00 --to 13:00 \
                  --days mon-fri --from 14:00 --to 18:00
zeit set-activity-types --group work --types "Coding: Code in company repos; Meetings: Video calls"
zeit list-activity-types                 # grouped output
zeit view --group personal_projects
zeit stats --group work
```

`zeit set-work-hours` stays as an alias for `zeit schedule set` with one window. `--group` on `set-activity-types` is repeatable and replaces the `--work` / `--personal` pair, which also removes its "preserve the other category" rule: a group named on the command line is replaced, a group not named is preserved.

`zeit doctor` reports the schedule form, whether this tick would track now, the cadence, the primary group, and the selection size.

## Prompts

`Prompts.activityClassification` builds three sections instead of two, each with its group label, and the closing line "If unsure between work and personal" is rewritten for three groups. The structured output schema still constrains the model to configured ids, so a classification always maps to a type that exists at write time.

The work-against-projects distinction is the one this feature can fail on: both are an IDE, a terminal and documentation. The prompt change is only half the fix; the other half is the type descriptions the user writes in step 3. Validate with `zeit track --sample` on each machine and read what the classifier does with the twin pairs.

`Prompts.daySummary` receives the group breakdown instead of the work percentage.

## Validation

`ActivityTypeValidator.validateAll` currently requires at least one work and at least one personal type, which rejects a legitimate selection. New rules:

- At least one type overall.
- At least one type in the primary group.
- Maximum 30 types total.
- Names non-empty, max 50 characters, unique across all three groups.
- Descriptions non-empty, max 200 characters.
- `idle` remains reserved.

Schedule validation: `windows` non-empty when that form is used; `from` and `to` parse as `HH:MM`; `days` non-empty per window. Overlaps and overnight spans are valid by definition and need no rule.

## Phases

1. **Model and schema** — `ActivityGroup`, `activity_group` column, `DatabaseMigrator` with the mapping above, `ActivityCatalog`, validator rules, `ActivityStat.group` and the Unclassified bucket, `ActivityEntry.device`.
2. **Config and tracker** — `tracking.schedule` with windows and `always`, `classification.primary_group`, legacy alias, cadence gate and battery check in `track`, `day_start_hour` applied where an entry's date is computed.
3. **Prompts** — three sections, rewritten closing line, day summary by group.
4. **UI** — onboarding question and picker chips, schedule list editor, three-section details, primary-group number in the menubar, unselect confirmation.
5. **CLI** — `zeit schedule`, `--group` flags, grouped `list-activity-types`, `doctor` output.

Phases 1 and 2 are independent of each other. Phase 3 depends only on 1.

## Tests

`Tests/ZeitAppTests` holds one file today. The parts of this feature that are pure functions and easy to get wrong need real coverage:

- Schedule containment: single window, several windows, overlapping windows, overnight window, non-listed day, `always`.
- The `is_work` migration, including the two remapped ids and a user-written type.
- Day attribution across `day_start_hour`: 01:00 stays on the calendar day with the default `0`, and moves to the previous day with `4`.
- `computeActivityBreakdown` with an id absent from the type table — it must land in Unclassified, not personal.
- Cadence gate: a tick inside the interval is skipped, a tick after it runs.

Classification quality is checked by running `zeit track --sample` on both machines against the twin pairs, not by unit tests.

## Out of scope

- **Syncing data between machines.** Each machine keeps its own database and its own view. `ActivityEntry.device` is added so a later export and import stays possible, nothing more. Whether classification data may leave the work laptop at all is an open question that has to be answered before any sync work starts.
- **Per-project breakdown** inside `personal_projects` (the fine-grained idea in `ideas.md`).
- **Intent against schedule** — "I meant to be on projects between 09:00 and 18:00". That is an objectives concern, not a schedule one.
- **Normalising `daily_activities`** into one row per entry. It is the right shape and would remove a read-modify-write of a whole day per tick, but nothing in this feature needs it.
