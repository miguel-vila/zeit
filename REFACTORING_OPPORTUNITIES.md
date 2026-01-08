# Refactoring Opportunities

**Generated:** 2026-01-07 | **Analyzed files:** 23 Python files in src/zeit/

## Summary

The codebase is well-structured with no severely long files (max: 316 lines) or functions (max: ~80 lines). Several refactoring opportunities have been identified and addressed.

---

## Completed Fixes

### ✅ 1. Hardcoded Prompt Strings (DONE)

**Status:** Completed

**Changes:**
- Created `src/zeit/core/prompts.py` with all LLM prompt templates
- Updated `activity_id.py` to import from `prompts.py`
- Reduced `activity_id.py` from 364 → 316 lines

---

### ✅ 2. Missing Error Handling in DaySummarizer (DONE)

**Status:** Completed

**Changes:**
- Added try/except around Ollama LLM call in `day_summarizer.py`
- Added logging import and logger instance
- Now matches error handling pattern from `activity_id.py`

---

### ✅ 3. Legacy Wrapper Functions (DONE)

**Status:** Completed

**Changes:**
- Verified functions were unused (grep found no callers)
- Removed 5 unused legacy wrapper functions from `view_data.py`
- Reduced file from 160 → 138 lines

---

### ✅ 4. Repeated CLI Separator Pattern (DONE)

**Status:** Completed

**Changes:**
- Added `SEPARATOR_WIDTH`, `SEPARATOR_DOUBLE`, `SEPARATOR_SINGLE` constants
- Created `print_header()`, `print_footer()`, `print_section_divider()` helpers
- Refactored all print statements to use the helpers

---

### ✅ 5. Duplicated Logging Setup (DONE)

**Status:** Completed

**Changes:**
- Created `src/zeit/core/logging_config.py` with `setup_logging()` function
- Updated `run_tracker.py` to use centralized logging
- Updated `menubar.py` to use centralized logging
- Removed ~25 lines of duplicated logging setup code

---

## Remaining Opportunities

### 6. Inconsistent Date Handling

**Priority:** Low | **Locations:** Multiple files

**Issue:** `today_str()` exists in utils but manual strftime calls are scattered:

```python
# In utils.py:
def today_str() -> str:
    return datetime.now().strftime("%Y-%m-%d")

# But elsewhere:
yesterday = (datetime.now() - timedelta(days=1)).strftime("%Y-%m-%d")  # view_data.py
date_str = timestamp.strftime("%Y-%m-%d")  # db.py
```

**Suggested Fix:** Add more date utilities:

```python
# src/zeit/core/utils.py
def yesterday_str() -> str:
    return (datetime.now() - timedelta(days=1)).strftime("%Y-%m-%d")

def format_date(dt: datetime) -> str:
    return dt.strftime("%Y-%m-%d")
```

---

### 7. AppleScript Execution Duplication

**Priority:** Low | **Locations:** `active_window.py`, `qt_helpers.py`

**Issue:** Similar subprocess + osascript patterns with timeout handling.

**Suggested Fix:** Extract to shared helper:

```python
# src/zeit/core/macos_helpers.py
def run_applescript(script: str, timeout: int = 5) -> str:
    """Execute AppleScript and return output."""
    ...
```

---

### 8. Property Recalculation

**Priority:** Very Low | **Location:** `menubar.py` lines 34-36

**Issue:** Property reads config on every access (negligible performance impact).

---

### 9. Generic Variable Names

**Priority:** Very Low | **Locations:** Various

**Issue:** `response` and `result` used for different types throughout codebase.

---

## Structural Suggestions

### 10. Consider Splitting `activity_id.py`

**Priority:** Low

**Current state:** 316 lines with enums, Pydantic models, and LLM logic.

**Suggested structure:**
```
src/zeit/core/
├── activity_id.py      # Just ActivityIdentifier class
├── activity_types.py   # Activity, ExtendedActivity enums
├── prompts.py          # All prompt templates ✅ (done)
└── models.py           # Pydantic response models
```

---

### 11. Add `__all__` Exports

**Priority:** Low

**Issue:** No explicit exports in most `__init__.py` files (they're empty).

---

## What's Already Good

- **No excessively long files** (max 316 lines, threshold was 500)
- **No excessively long functions** (max ~80 lines, threshold was 250)
- **Consistent type hints** throughout
- **Good use of Pydantic models** for data validation
- **Proper context managers** for resources (DB, screenshots)
- **Consistent error handling** in all LLM calls ✅
- **Clean separation** between CLI, core, UI, and data layers
- **Centralized logging configuration** ✅
- **Extracted prompt templates** ✅

---

## Progress Summary

| Priority | Item | Status |
|----------|------|--------|
| High | Extract prompts to separate module | ✅ Done |
| High | Add error handling to DaySummarizer | ✅ Done |
| Medium | Remove legacy wrapper functions | ✅ Done |
| Medium | Extract CLI separator helpers | ✅ Done |
| Medium | Centralize logging setup | ✅ Done |
| Low | Inconsistent date handling | Pending |
| Low | AppleScript execution duplication | Pending |
| Low | Split activity_id.py further | Pending |
| Low | Add `__all__` exports | Pending |
| Very Low | Property recalculation | Pending |
| Very Low | Generic variable names | Pending |
