# Day Summarization

Generates a qualitative AI summary of a day's tracked activities, giving the user a quick narrative of how they spent their day.

## How It Works

Day summarization is a two-step process: **condensation** (grouping raw data) followed by **LLM generation** (producing a narrative summary).

### 1. Activity Condensation

Raw activity entries (one per minute) are condensed before being sent to the LLM:

- **Idle filtering** - All idle entries are excluded.
- **Consecutive grouping** - Adjacent entries with the same activity type are merged into `ActivityGroup`s, each with a start/end time, duration in minutes, and collected reasonings from the vision model.
- **Percentage breakdown** - A per-activity percentage is computed over non-idle entries, sorted by proportion.

For example, 45 raw entries might condense into 8 groups like:

```
09:15-10:30 - work coding (75 min): "Editing Swift files in Xcode; writing unit tests"
10:30-10:45 - personal browsing (15 min): "Reading Hacker News"
```

### 2. LLM Summary Generation (Structured Output)

The condensed data is formatted into a prompt with two sections:

- **Activity breakdown** - Percentage of time per activity type.
- **Chronological activities** - Each group with its time range, activity type, duration, and vision model descriptions.

If the user has set **day objectives**, they are appended to the prompt.

The LLM generates a **structured JSON response** constrained by a JSON schema (via `LLMProvider.generateStructured`). The schema is built dynamically based on whether objectives are set:

```json
{
  "type": "object",
  "properties": {
    "summary": {
      "type": "string",
      "description": "A concise 2-3 sentence narrative summary of the day's activities"
    },
    "objectives_alignment": {
      "type": "string",
      "description": "1-2 sentence assessment of how well the day's activities aligned with the stated objectives"
    }
  },
  "required": ["summary"]
}
```

- `summary` is always required.
- `objectives_alignment` is added to the schema (and marked required) only when day objectives are set.

The text model runs with `temperature=0.7`.

## Output

A `DaySummary` contains:

| Field | Description |
|-------|-------------|
| Summary text | 2-3 sentence narrative from the LLM |
| Objectives alignment | Optional 1-2 sentence assessment of objective alignment (only when objectives are set) |
| Percentage breakdown | Per-activity percentages (formatted list) |
| Start time | Timestamp of the first non-idle activity |
| End time | Timestamp of the last non-idle activity |

## CLI Usage

```bash
zeit view summarize [YYYY-MM-DD] [-m PROVIDER:MODEL]
```

| Option | Description |
|--------|-------------|
| `YYYY-MM-DD` | Date to summarize (default: today) |
| `-m, --model` | Override model in `provider:model` format (e.g. `openai:gpt-4o-mini`) |

Example output:

```
======================================================================
Day Summary for 2026-02-21
======================================================================
(09:15 - 18:02)
Main objective: Ship the new onboarding flow

Today was primarily a coding day, with roughly 70% of time spent in Xcode
working on Swift UI components and unit tests. A notable mid-afternoon
context switch to design work suggests iteration on the UI.

**Objectives Alignment:**
The day aligns well with the stated objective — most coding time was
spent on onboarding-related UI components and tests.

**Percentages Breakdown:**

- work coding: 58.3%
- work design: 12.1%
- personal browsing: 18.5%
- personal communication: 11.1%
======================================================================
```

If day objectives are set, they are displayed between the time range and the summary text.

## Model Configuration

Uses the configured text model (same as activity classification). Default: MLX on-device `qwen3:8b`. Can be overridden per-invocation with the `--model` flag, which accepts any configured provider.

## Edge Cases

- **No activities for the date** - Prints "No activities recorded for \<date\>" and exits.
- **Only idle activities** - Prints "No non-idle activities recorded for \<date\>" and exits.
- **No objectives set** - The summary is generated without objective alignment; `objectives_alignment` will be `nil`.
