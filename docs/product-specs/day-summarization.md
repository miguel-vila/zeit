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

### 2. LLM Summary Generation

The condensed data is formatted into a prompt with two sections:

- **Activity breakdown** - Percentage of time per activity type.
- **Chronological activities** - Each group with its time range, activity type, duration, and vision model descriptions.

If the user has set **day objectives**, they are appended to the prompt. The LLM is asked to consider whether the activities align with the stated objectives.

The LLM is asked to provide a brief summary (2-3 sentences) covering:
1. What the user spent most of their time doing
2. Notable patterns or observations
3. How productive the day appears to have been

The text model runs with `temperature=0.7` (higher than classification's `0` to allow more natural prose).

## Output

A `DaySummary` contains:

| Field | Description |
|-------|-------------|
| Summary text | 2-3 sentence narrative from the LLM |
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
context switch to design work suggests iteration on the UI. The day
aligns well with the stated objective.

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
- **No objectives set** - The summary is generated without objective alignment analysis.
