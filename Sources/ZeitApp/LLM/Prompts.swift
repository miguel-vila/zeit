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

    /// Prompt for text model to classify activity into category.
    ///
    /// Dynamically builds the category list from user-configured activity types.
    static func activityClassification(
        description: String,
        activityTypes: [ActivityType] = ActivityType.defaultTypes
    ) -> String {
        let personalTypes = activityTypes.filter { !$0.isWork }
        let workTypes = activityTypes.filter { $0.isWork }

        var personalSection = "PERSONAL ACTIVITIES:\n"
        for type in personalTypes {
            personalSection += "- \(type.id): \(type.description)\n"
        }

        var workSection = "WORK ACTIVITIES:\n"
        for type in workTypes {
            workSection += "- \(type.id): \(type.description)\n"
        }

        return """
        Based on the following description of a user's screen activity, classify it into one of these categories:

        \(personalSection)
        \(workSection)
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
        }

        if objectives != nil {
            prompt += """

            Provide:
            1. A "summary": a brief narrative (2-4 sentences) of what the user spent most of their time doing and notable patterns
            2. An "objectives_alignment": a 1-2 sentence assessment of how well the day's activities aligned with the stated objectives — what was accomplished vs. missed
            """
        } else {
            prompt += """

            Provide a "summary": a brief narrative (2-3 sentences) of what the user spent most of their time doing, notable patterns, and how productive the day appears to have been.
            """
        }

        return prompt
    }
}
