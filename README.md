# zeit

Logs what you are doing in your computer and summarizes it using local models:

- `qwen3-vl` for image captioning
- `qwen2` to infer the activity based on the captions

## Configs

- **Work hours and days**: Edit `run_tracker.sh` to set `WORK_START_HOUR` and `WORK_END_HOUR`
- **Screenshot interval**: Edit `co.invariante.zeit.plist` to change `StartInterval` (default: 60 seconds)
- **Idle threshold**: Set `IDLE_THRESHOLD_SECONDS` environment variable in `.env` file (default: 300 seconds / 5 minutes)
- **Activities enumeration**: Defined in `activity_id.py` as `Activity` enum

## TODOs

- add last half an hour summary in the menubar app
- show when not collecting data due outside work hours
- collect only necessary data
