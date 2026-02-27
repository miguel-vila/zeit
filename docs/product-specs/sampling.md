# Test Data Sampling

Captures the full inputs and outputs of the two-stage LLM pipeline (vision + classification) for building test datasets, debugging model behavior, and evaluating prompt changes.

## Motivation

When iterating on prompts, models, or activity types, it's useful to have real-world samples of what the pipeline saw and produced. This feature saves the raw artifacts — screenshots, prompts, and model responses — in a structured directory so they can be reviewed, replayed, or used as regression test cases.

## Availability

Sampling (and the entire debug section) is gated behind the compile-time `DEBUG` flag. Swift defines `DEBUG` automatically for `swift build` (debug configuration) and omits it for `swift build -c release`. This means:

- **Debug builds** (`./build.sh` or `./build.sh --clean`): debug features are available — the menubar debug section, sampling buttons, and the `--sample` CLI flag are all present.
- **Release builds** (`./build.sh --release`): debug features are compiled out entirely.

There is no runtime toggle. Debug features are controlled exclusively by the build configuration.

## What Gets Sampled

Each sample captures both stages of the LLM pipeline:

### Vision model call

- Input screenshot image(s) (copied as PNGs)
- The vision prompt (constructed by `Prompts.visionDescription`)
- The vision model response (text)
- The vision model thinking output (if present)

### Classification model call

- The classification prompt (constructed by `Prompts.activityClassification`)
- The classification model response (raw JSON)
- The classification model thinking output (if present)

### Metadata

- Timestamp
- Active screen number
- Frontmost app name
- Model names (vision and text)
- The final parsed `IdentificationResult` (activity, reasoning, description)

## Storage Format

Samples are stored under `~/.local/share/zeit/samples/`, one directory per sample:

```text
~/.local/share/zeit/samples/
└── 2026-02-27T14-30-00/
    ├── screen_1.png
    ├── screen_2.png          # if multi-monitor
    ├── vision.json
    └── classification.json
```

### `vision.json`

```json
{
  "timestamp": "2026-02-27T14:30:00Z",
  "active_screen": 1,
  "frontmost_app": "Xcode",
  "model": "qwen3-vl:4b",
  "prompt": "You are viewing screenshots from the user's multiple monitors...",
  "thinking": "The user appears to be...",
  "response": "The user is writing Swift code in Xcode with a file open..."
}
```

### `classification.json`

```json
{
  "model": "qwen3:8b",
  "provider": "mlx",
  "prompt": "Classify the following activity description...",
  "thinking": "Given the description mentions Xcode and code editing...",
  "response": "{\"main_activity\": \"work_coding\", \"reasoning\": \"...\"}",
  "parsed_activity": "work_coding",
  "parsed_reasoning": "User is actively writing Swift code in Xcode"
}
```

The timestamp in the directory name uses dashes instead of colons (`T14-30-00` not `T14:30:00`) for filesystem compatibility.

## Triggering Samples

### CLI: `zeit track --force --sample`

A new `--sample` flag on the existing `track` command. It:

1. Runs the normal tracking pipeline (capture, identify, save to DB)
2. Additionally writes the sample artifacts to disk
3. Prints the sample directory path to stdout

`--sample` implies `--force` (bypass work hours / stop flag checks). Can be combined with `--delay`:

```bash
# Sample immediately
zeit track --sample

# Sample after 5 second delay
zeit track --sample --delay 5
```

The `--sample` flag is only compiled in debug builds (`#if DEBUG`).

### Menubar: debug section buttons

Two new buttons in the existing debug section (below "Force Track" and "Clear Today's Data"):

#### "Force Track & Sample"

- Icon: `tray.and.arrow.down.fill`
- Dismisses the menubar popover immediately on click (sampling runs in the background)
- Runs the tracking pipeline with sampling enabled
- On completion: notification with the activity name and the sample directory path. Clicking the notification opens the sample directory in Finder.

#### "Force Track & Sample with Delay"

- Icon: `timer`
- Opens a small input alert/popover asking for delay in seconds
- Pre-fills with the last-used delay value (stored in UserDefaults under key `lastSampleDelay`, default: `5`)
- After the user confirms, dismisses the menubar popover (sampling runs in the background with the delay)
- On completion: same notification as above (clicking opens the sample directory)

## Shared Implementation

The CLI and menubar must share the core sampling logic. This is achieved by extending `ActivityIdentifier` — **not** by duplicating logic in both call sites.

### Changes to `ActivityIdentifier`

The `identifyCurrentActivity` method gains an optional `sample: Bool` parameter:

```swift
func identifyCurrentActivity(
    keepScreenshots: Bool = false,
    debug: Bool = false,
    sample: Bool = false
) async throws -> IdentificationResult
```

When `sample` is `true`:

1. Screenshots are always kept (overrides `keepScreenshots`).
2. All intermediate artifacts are collected into a `SampleData` struct.
3. After the pipeline completes, `SampleData` is written to disk via a new `SampleWriter` utility.
4. The `IdentificationResult` is returned as usual (callers that don't sample see no difference).

### `SampleData` struct

```swift
struct SampleData {
    let timestamp: Date
    let activeScreen: Int
    let frontmostApp: String?
    let screenshotURLs: [URL]

    // Vision stage
    let visionModel: String
    let visionPrompt: String
    let visionThinking: String?
    let visionResponse: String

    // Classification stage
    let classificationModel: String
    let classificationProvider: String
    let classificationPrompt: String
    let classificationThinking: String?
    let classificationResponse: String

    // Final result
    let parsedActivity: String
    let parsedReasoning: String?
}
```

### `SampleWriter` utility

A new file `Sources/ZeitApp/LLM/SampleWriter.swift`:

```swift
enum SampleWriter {
    /// Write sample data to ~/.local/share/zeit/samples/<timestamp>/
    static func write(_ data: SampleData) throws -> URL { ... }

    /// Delete sample directories older than 30 days
    static func cleanupOldSamples() throws { ... }
}
```

- `write` creates the directory, copies screenshots, and writes `vision.json` and `classification.json`.
- `cleanupOldSamples` is called opportunistically each time a sample is written. It scans the `samples/` directory and removes subdirectories whose timestamp-based name is older than 30 days.

### Call sites

Both call sites become thin wrappers:

**CLI (`TrackCommand.swift`):**

```swift
let result = try await identifier.identifyCurrentActivity(
    keepScreenshots: debug,
    debug: debug,
    sample: sample
)
```

**Menubar (`MenubarFeature.swift`):**

```swift
let result = try await identifier.identifyCurrentActivity(sample: true)
```

No tracking/DB/notification logic is duplicated — the only new responsibility in each call site is passing `sample: true`.

## Cleanup

`SampleWriter.cleanupOldSamples()` removes sample directories older than 30 days. It is called automatically whenever a new sample is written. The cleanup is best-effort — errors during cleanup are logged but do not fail the sample operation.

## File Locations

| Change | File |
|--------|------|
| `SampleData` struct and `sample` parameter | `Sources/ZeitApp/LLM/ActivityIdentifier.swift` |
| `SampleWriter` (write + cleanup) | `Sources/ZeitApp/LLM/SampleWriter.swift` (new) |
| `--sample` CLI flag | `Sources/ZeitApp/CLI/TrackCommand.swift` |
| Menubar sample buttons | `Sources/ZeitApp/Features/Menubar/MenubarView.swift` |
| Menubar sample actions/state | `Sources/ZeitApp/Features/Menubar/MenubarFeature.swift` |
