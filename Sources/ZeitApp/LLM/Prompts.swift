import Foundation

/// LLM prompt templates for activity identification
enum Prompts {
    /// Prompt for vision model to describe what's on screen
    static func visionDescription(activeScreen: Int, screenCount: Int, frontmostApp: String? = nil) -> String {
        let frontmostAppHint = frontmostApp.map { "\nThe frontmost application detected was: \($0)." } ?? ""

        if screenCount > 1 {
            // Multi-screen: indicate which screen is active
            return """
            You are viewing screenshots from the user's multiple monitors. The images are provided in order: Screen 1, Screen 2, etc.

            IMPORTANT: Based on system information, Screen \(activeScreen) currently contains the focused/active window. Use this as a strong hint for identifying the PRIMARY screen.\(frontmostAppHint)

            Verify the PRIMARY screen by also looking for visual cues:
            - Mouse cursor position
            - Active/focused window indicators (highlighted title bar, focus rings)
            - Text input carets or selection highlights
            - The most prominent application window

            Describe the user's main activity on the PRIMARY screen in 1-2 sentences.
            Focus on what application is in use and what specific task the user appears to be doing.
            """
        } else {
            // Single screen: simple description
            return """
            You are viewing a screenshot from the user's single monitor.\(frontmostAppHint)
            Describe the user's main activity in 1-2 sentences.
            Focus on what application is in use and what specific task the user appears to be doing.
            """
        }
    }

    /// Prompt for text model to classify activity into category
    static func activityClassification(description: String) -> String {
        """
        Based on the following description of a user's screen activity, classify it into one of these categories:

        PERSONAL ACTIVITIES:
        - personal_browsing: General web browsing not related to work
        - social_media: Facebook, Twitter/X, Instagram, TikTok, etc.
        - youtube_entertainment: Watching YouTube for entertainment
        - personal_email: Personal email (Gmail, etc.)
        - personal_ai_use: Using AI tools for personal projects
        - personal_finances: Banking, budgeting, crypto, investments
        - professional_development: Learning, courses, tutorials
        - online_shopping: Amazon, eBay, other shopping sites
        - personal_calendar: Personal calendar/scheduling
        - entertainment: Games, movies, music, streaming

        WORK ACTIVITIES:
        - slack: Using Slack for work communication
        - work_email: Work email (Outlook, company email)
        - zoom_meeting: Video calls, meetings
        - work_coding: Writing code, using IDE
        - work_browsing: Work-related web browsing, documentation
        - work_calendar: Work calendar/scheduling

        Activity description:
        \(description)

        Respond with a JSON object:
        {
            "thinking": "Your reasoning for the classification",
            "main_activity": "the_activity_category",
            "reasoning": "Brief explanation of why this category was chosen",
            "secondary_context": "Any secondary activity if applicable (optional)"
        }

        Choose the single most appropriate category. If unsure between work and personal, consider the context and applications visible.
        """
    }

    /// Prompt for summarizing a day's activities
    static func daySummary(
        activitiesText: String,
        percentageBreakdown: String,
        objectives: (main: String, secondary: [String])?
    ) -> String {
        var prompt = """
        Summarize the following day's computer activity. Be concise and insightful.

        Activity breakdown:
        \(percentageBreakdown)

        Chronological activities:
        \(activitiesText)

        """

        if let obj = objectives {
            prompt += """

            Day's objectives:
            - Main: \(obj.main)
            """
            if !obj.secondary.isEmpty {
                prompt += "\n- Secondary: \(obj.secondary.joined(separator: ", "))"
            }

            prompt += """

            Consider whether the activities align with the stated objectives.
            """
        }

        prompt += """

        Provide a brief summary (2-3 sentences) of:
        1. What the user spent most of their time doing
        2. Notable patterns or observations
        3. How productive the day appears to have been
        """

        return prompt
    }
}
