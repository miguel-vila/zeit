# Refactoring Opportunities

**Generated:** 2026-01-07 | **Commit:** 9d5c221

## Summary

| Priority | Count | Description |
|----------|-------|-------------|
| High | 4 | Should address - high impact on maintainability |
| Medium | 5 | Consider addressing - moderate complexity/impact |
| Low | 6 | Nice to have - minor improvements |

---

## Priority 1: High Impact

### 1.1 Long File: `menubar.py` (511 lines)

**Location:** `src/zeit/ui/menubar.py`

**Problem:** Exceeds 500-line threshold. Contains 3 classes that should be separated.

**Recommendation:** Split into:
- `src/zeit/ui/tracking_state.py` → `TrackingState` class (lines 35-57)
- `src/zeit/ui/details_window.py` → `DetailsWindow` class (lines 60-183)
- `src/zeit/ui/menubar.py` → `ZeitMenuBar` class only

---

### 1.2 Duplicated Menu Building Logic

**Location:** `src/zeit/ui/menubar.py` lines 307-433

**Problem:** `_update_menu_no_data()` and `_update_menu_with_data()` share ~70% identical code:
- Toggle action creation (lines 332-341 vs 405-414)
- Refresh action (lines 346-348 vs 419-421)
- Details action (lines 351-353 vs 424-426)
- Quit action (lines 358-360 vs 431-433)

**Recommendation:** Extract common menu items to helper methods:
```python
def _add_toggle_action(self, tracking_state: TrackingState):
    ...

def _add_standard_actions(self):
    """Add Refresh, View Details, Quit actions."""
    ...
```

---

### 1.3 Duplicated CSS Styling

**Location:** `src/zeit/ui/menubar.py` lines 152-175

**Problem:** Identical QProgressBar stylesheet repeated twice (only color differs).

**Current:**
```python
if entry.activity.is_work_activity():
    progress_bar.setStyleSheet("""
        QProgressBar { border: 1px solid #cccccc; ... }
        QProgressBar::chunk { background-color: #4CAF50; ... }
    """)
else:
    progress_bar.setStyleSheet("""
        QProgressBar { border: 1px solid #cccccc; ... }
        QProgressBar::chunk { background-color: #2196F3; ... }
    """)
```

**Recommendation:**
```python
PROGRESS_BAR_STYLE = """
    QProgressBar {{ border: 1px solid #cccccc; border-radius: 4px; background-color: #f0f0f0; }}
    QProgressBar::chunk {{ background-color: {color}; border-radius: 3px; }}
"""

color = "#4CAF50" if entry.activity.is_work_activity() else "#2196F3"
progress_bar.setStyleSheet(PROGRESS_BAR_STYLE.format(color=color))
```

---

### 1.4 Duplicated Activity Enum

**Location:** `src/zeit/core/activity_id.py` lines 16-78

**Problem:** `Activity` and `ExtendedActivity` enums duplicate all 16 activity values. Only difference is `ExtendedActivity` adds `IDLE`.

**Recommendation:** Use composition or inheritance:
```python
class Activity(str, Enum):
    PERSONAL_BROWSING = "personal_browsing"
    # ... all activities

class ExtendedActivity(str, Enum):
    # Include all Activity values
    PERSONAL_BROWSING = Activity.PERSONAL_BROWSING.value
    # ... or use a factory to generate from Activity
    
    # System states
    IDLE = "idle"
```

Or simpler: add `IDLE` to `Activity` and use a single enum everywhere.

---

## Priority 2: Medium Impact

### 2.1 Long Method: `DetailsWindow.update_data()`

**Location:** `src/zeit/ui/menubar.py` lines 99-183 (84 lines)

**Problem:** Complex UI building logic in single method.

**Recommendation:** Extract helper methods:
```python
def _create_activity_widget(self, entry: ActivityWithPercentage) -> QWidget:
    ...

def _create_progress_bar(self, percentage: float, is_work: bool) -> QProgressBar:
    ...
```

---

### 2.2 Long Method with Embedded Prompt: `_describe_activities()`

**Location:** `src/zeit/core/activity_id.py` lines 226-305 (79 lines)

**Problem:** 33-line prompt string embedded directly in method.

**Recommendation:** Extract prompts to module constants or separate file:
```python
# activity_id.py or prompts.py
ACTIVITY_CLASSIFICATION_PROMPT = """You are given a description of a screenshot...
...
"""

def _describe_activities(self, image_description: str, ...):
    prompt = ACTIVITY_CLASSIFICATION_PROMPT.format(
        image_description=image_description,
        secondary_context=secondary_context_section
    )
```

---

### 2.3 Hardcoded Model Names

**Locations:**
- `src/zeit/core/activity_id.py` lines 141-142: `self.vlm = "qwen3-vl:4b"`, `self.llm = "qwen3:8b"`
- `src/zeit/processing/day_summarizer.py` line 19: `self.llm = "qwen3:8b"`

**Recommendation:** Move to `conf.yml`:
```yaml
models:
  vision: "qwen3-vl:4b"
  text: "qwen3:8b"
```

---

### 2.4 Unused Class: `EphemeralScreenshot`

**Location:** `src/zeit/core/screen.py` lines 12-41

**Problem:** Only `MultiScreenCapture` is imported/used elsewhere. `EphemeralScreenshot` appears dead.

**Recommendation:** Verify unused via grep, then remove if confirmed dead code.

---

### 2.5 Class Doing Too Much: `ZeitMenuBar`

**Location:** `src/zeit/ui/menubar.py` lines 186-480 (~300 lines)

**Responsibilities:**
1. Tracking state management (flag file)
2. Menu building (2 variants)
3. Notification dispatch
4. Details window management
5. Timer management

**Recommendation:** Consider extracting:
- `TrackingController` - flag file management, state logic
- Keep `ZeitMenuBar` focused on UI/menu only

---

## Priority 3: Low Impact

### 3.1 Magic Path String

**Location:** `src/zeit/ui/menubar.py` line 189

**Current:** `STOP_FLAG = Path.home() / ".zeit_stop"`

**Recommendation:** Move to config or constants module.

---

### 3.2 Repeated Date Formatting

**Locations:** 6+ occurrences across files

**Pattern:** `datetime.now().strftime("%Y-%m-%d")`

**Recommendation:** Add utility function:
```python
# src/zeit/core/utils.py
def today_str() -> str:
    return datetime.now().strftime("%Y-%m-%d")
```

---

### 3.3 Inconsistent Import Paths

**Location:** `run_tracker.py` lines 8-11

**Current:** `from src.zeit.core.activity_id import ...`

**Expected:** `from zeit.core.activity_id import ...`

**Problem:** Indicates package not installed in editable mode.

**Recommendation:** Ensure `pip install -e .` or `uv pip install -e .` is run.

---

### 3.4 Type Error: Nullable Passed to Non-Nullable

**Location:** `src/zeit/core/activity_id.py` line 214

**Problem:** `response.thinking` can be `str | None` but `model_validate_json()` requires `str | bytes | bytearray`.

**Fix:**
```python
if response.thinking:
    return MultiScreenDescription.model_validate_json(response.thinking)
else:
    raise RuntimeError("Expected thinking output from vision model")
```

---

### 3.5 Unresolved Import

**Location:** `src/zeit/cli/view_data.py` line 7

**Error:** `Import "zeit.processing.day_summarizer" could not be resolved`

**Likely cause:** Same as 3.3 - package path issue.

---

### 3.6 Dead Code: CLI Functions Without Entry Point

**Location:** `src/zeit/cli/view_data.py`

**Problem:** Contains `view_day()`, `view_all_days()`, `view_today()`, `view_yesterday()`, `summarize_day()` but no Typer app or `if __name__ == "__main__"` block.

**Recommendation:** Either:
- Add Typer CLI app (like `manage_db.py`)
- Or document that these are meant to be imported by `run_view_data.py`

---

## Refactoring Execution Plan

### Phase 1: Quick Wins (1-2 hours)
- [x] 1.3 Extract CSS to constant
- [x] 3.4 Fix type error on line 214
- [x] 2.3 Move model names to config

### Phase 2: Deduplication (2-3 hours)
- [x] 1.2 Extract common menu methods
- [x] 2.1 Extract `update_data()` helpers
- [x] 3.2 Add date utility function

### Phase 3: Structural (4-6 hours)
- [x] 1.1 Split `menubar.py` into 3 files
- [x] 2.4 Remove unused `EphemeralScreenshot`
- [x] 2.2 Extract prompts to constants

### Phase 4: Polish
- [x] 3.1 Move magic paths to config
- [x] 3.3 Fix import paths
- [x] 3.6 Add CLI entry point or document usage
