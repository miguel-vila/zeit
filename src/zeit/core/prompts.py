"""LLM prompt templates for activity identification.

This module contains all prompt templates used for:
- Multi-screen image description (vision model)
- Single-screen image description (vision model)
- Activity classification (text model)
"""

# Template for multi-screen description with vision model
MULTI_SCREEN_DESCRIPTION_PROMPT = """You are viewing screenshots from the user's multiple monitors. The images are provided in order: Screen 1, Screen 2, etc.

{active_screen_hint}

Verify the PRIMARY screen by also looking for visual cues:
- Mouse cursor position
- Active/focused window indicators (highlighted title bar, focus rings)
- Text input carets or selection highlights
- The most prominent application window

Provide:
1. The screen number (1, 2, etc.) of the PRIMARY screen
2. A description of the main activity on the PRIMARY screen
3. Brief context about what's on secondary screens (if notable)"""

# Template for active screen hint (inserted into MULTI_SCREEN_DESCRIPTION_PROMPT)
ACTIVE_SCREEN_HINT_TEMPLATE = """IMPORTANT: Based on system information, Screen {screen_number} currently contains the focused/active window. Use this as a strong hint for identifying the PRIMARY screen."""

# Fallback hint when active screen detection fails
ACTIVE_SCREEN_HINT_FALLBACK = "Identify which screen is the PRIMARY/ACTIVE screen."

# Template for single-screen description with vision model
SINGLE_SCREEN_DESCRIPTION_PROMPT = """A brief description of the user's activities based on the screenshot. Describe enough things to understand what is the main activity the user is engaged in."""

# Template for activity classification with text model
ACTIVITY_CLASSIFICATION_PROMPT = """You are given a description of a screenshot taken from a user's computer.
It describes various elements visible on the screen.
Based on this description, identify the main activity the user is engaged in.

The user might be during their day job, taking a break, or doing personal tasks.
We want to differentiate between work-related and personal activities.
The personal categories are:
- personal_browsing : User is browsing the web for personal purposes
- social_media : User is browsing or interacting on social media platforms.
- youtube_entertainment : User is watching videos on YouTube for entertainment.
- personal_email : User is reading or composing personal emails.
- personal_ai_use : User is interacting with AI tools (such as ChatGPT or Claude) for personal use.
- personal_finances : User is managing personal finances or banking.
- professional_development : User is engaged in activities related to their professional growth, such as learning new skills or attending webinars.
- online_shopping : User is browsing or purchasing items online.
- personal_calendar : User is checking or managing their personal calendar.
- entertainment : User is engaged in leisure activities, such as watching movies, playing games, or listening to music.
The work-related categories are:
- slack : User is actively using Slack for communication.
- work_email : User is reading or composing work-related emails.
- zoom_meeting : User is in a Zoom meeting or call.
- work_coding : User is writing or reviewing code, related to their job.
- work_browsing : User is browsing the web for work-related purposes: research, jira, documentation, etc.
- work_calendar : User is checking or managing their work calendar.

If multiple activities are detected, select only the main one and the most specific.
For example, if the user is looking at their calendar from a browser, select work_calendar or personal_calendar instead of work_browsing or personal_browsing.

The user is a software engineer, working at the moment for a audio streaming company.
This means he might be looking at technical content NOT related to his job (e.g. learning new skills). In
those cases, select professional_development as the main activity.

The description of the PRIMARY screen activity is as follows:
{image_description}{secondary_context_section}"""

# Template for day summarization with numeric breakdown
DAY_SUMMARIZATION_PROMPT = """This is a condensed view of the user's activities during the day.

## Time Distribution
{percentage_breakdown}

## Chronological Activities
{activities_text}

Summarize the user's day qualitatively.
- Describe what they focused on and how their time was distributed
- Reference the percentages to provide numerical context where relevant
- Note any notable patterns or transitions between activities
- Don't make value judgments (either positive or negative)
- Don't talk about balance unless the numbers clearly justify it
- Just summarize the activities in an objective manner"""

# Template for day summarization with objectives
DAY_SUMMARIZATION_WITH_OBJECTIVES_PROMPT = """This is a condensed view of the user's activities during the day.

## User's Day Objectives
**Main Objective:** {main_objective}
{secondary_objectives_section}

## Time Distribution
{percentage_breakdown}

## Chronological Activities
{activities_text}

Summarize the user's day and evaluate alignment with their objectives.
- Describe what they focused on and how their time was distributed
- Reference the percentages to provide numerical context where relevant
- Assess whether their activities aligned with their stated objectives
- Note which objectives were supported by their activities and which were not
- Be objective and factual in your assessment
- Don't make value judgments (either positive or negative)"""
