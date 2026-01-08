# Refactoring Opportunities

**Generated:** 2026-01-07 | **Analyzed files:** 23 Python files in src/zeit/

## Summary

The codebase is well-structured with no severely long files (max: 224 lines) or functions (max: ~80 lines). All identified refactoring opportunities have been addressed.

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

### ✅ 6. Inconsistent Date Handling (DONE)

**Status:** Completed

**Changes:**
- Added `DATE_FORMAT` constant to `utils.py`
- Added `yesterday_str()` and `format_date()` functions to `utils.py`
- Updated `view_data.py` to use `yesterday_str()` instead of manual strftime

---

### ✅ 7. AppleScript Execution Duplication (DONE)

**Status:** Completed

**Changes:**
- Created `src/zeit/core/macos_helpers.py` with:
  - `AppleScriptError` exception class
  - `run_applescript()` function with timeout handling
  - `run_applescript_safe()` function for non-throwing usage
- Updated `active_window.py` to use shared helper
- Updated `qt_helpers.py` to use shared helper
- Removed ~20 lines of duplicated subprocess handling code

---

### ✅ 8. Property Recalculation (DONE)

**Status:** Completed

**Changes:**
- Changed `_stop_flag_path` from a property to an instance variable in `menubar.py`
- Now cached once in `__init__` instead of reading config on every access

---

### ✅ 9. Generic Variable Names (SKIPPED)

**Status:** Skipped - Very low priority, subjective

---

### ✅ 10. Split activity_id.py (DONE)

**Status:** Completed

**Changes:**
- Created `src/zeit/core/activity_types.py` with `Activity` and `ExtendedActivity` enums
- Created `src/zeit/core/models.py` with Pydantic models:
  - `MultiScreenDescription`
  - `ActivitiesResponse`
  - `ActivitiesResponseWithTimestamp`
- Updated `activity_id.py` to import from new modules
- Updated `db.py`, `activity_summarization.py`, `day_summarizer.py` imports
- Reduced `activity_id.py` from 316 → 224 lines

New structure:
```
src/zeit/core/
├── activity_id.py      # Just ActivityIdentifier class (224 lines)
├── activity_types.py   # Activity, ExtendedActivity enums (65 lines)
├── models.py           # Pydantic response models (47 lines)
├── prompts.py          # All prompt templates ✅
└── ...
```

---

### ✅ 11. Add `__all__` Exports (DONE)

**Status:** Completed

**Changes:**
- Added `__all__` exports to `src/zeit/__init__.py`
- Added `__all__` exports to `src/zeit/core/__init__.py` with main public API
- Added `__all__` exports to `src/zeit/cli/__init__.py`
- Added `__all__` exports to `src/zeit/ui/__init__.py`
- Added `__all__` exports to `src/zeit/processing/__init__.py`

---

## What's Already Good

- **No excessively long files** (max 224 lines, threshold was 500)
- **No excessively long functions** (max ~80 lines, threshold was 250)
- **Consistent type hints** throughout
- **Good use of Pydantic models** for data validation
- **Proper context managers** for resources (DB, screenshots)
- **Consistent error handling** in all LLM calls ✅
- **Clean separation** between CLI, core, UI, and data layers
- **Centralized logging configuration** ✅
- **Extracted prompt templates** ✅
- **Shared macOS helpers** ✅
- **Explicit module exports** ✅

---

## Progress Summary

| Priority | Item | Status |
|----------|------|--------|
| High | Extract prompts to separate module | ✅ Done |
| High | Add error handling to DaySummarizer | ✅ Done |
| Medium | Remove legacy wrapper functions | ✅ Done |
| Medium | Extract CLI separator helpers | ✅ Done |
| Medium | Centralize logging setup | ✅ Done |
| Low | Inconsistent date handling | ✅ Done |
| Low | AppleScript execution duplication | ✅ Done |
| Low | Split activity_id.py further | ✅ Done |
| Low | Add `__all__` exports | ✅ Done |
| Very Low | Property recalculation | ✅ Done |
| Very Low | Generic variable names | ⏭️ Skipped |
