import Foundation
import Testing

@testable import ZeitApp

/// The active screen is a hint the vision prompt can do without.
///
/// System Events answers "which screen holds the focused window" and regularly
/// fails to: it times out under load, and it is denied outright until Zeit
/// holds assistive access. A tick that already holds screenshots must survive
/// that, so the hint is optional everywhere it travels — from the prompt that
/// mentions it to the entry that is stored.
@Suite
struct ActiveScreenHintTests {
    @Test
    func anUndeterminedScreenDropsTheHintFromAMultiScreenPrompt() {
        let prompt = Prompts.visionDescription(activeScreen: nil, screenCount: 2)

        #expect(!prompt.contains("Based on system information"))
    }

    /// Dropping the hint must not drop the task: the model is still told it is
    /// looking at several screens and still asked to find the active one by
    /// what it can see.
    @Test
    func anUndeterminedScreenStillAsksForThePrimaryScreen() {
        let prompt = Prompts.visionDescription(activeScreen: nil, screenCount: 2)

        #expect(prompt.contains("Screen 1, Screen 2"))
        #expect(prompt.contains("Mouse cursor position"))
        #expect(prompt.contains("PRIMARY screen"))
    }

    @Test
    func aKnownScreenIsNamedAsAHint() {
        let prompt = Prompts.visionDescription(activeScreen: 2, screenCount: 2)

        #expect(prompt.contains("Screen 2 currently contains the focused/active window"))
    }

    /// A single screen is the active one by definition, so the hint is never
    /// needed and never mentioned.
    @Test
    func aSingleScreenNeedsNoHint() {
        let withHint = Prompts.visionDescription(activeScreen: 1, screenCount: 1)
        let withoutHint = Prompts.visionDescription(activeScreen: nil, screenCount: 1)

        #expect(withHint == withoutHint)
    }

    @Test
    func theFrontmostAppHintSurvivesAnUndeterminedScreen() {
        let prompt = Prompts.visionDescription(
            activeScreen: nil, screenCount: 2, frontmostApp: "Xcode"
        )

        #expect(prompt.contains("Xcode"))
    }
}

/// An entry is stamped with the moment it describes.
///
/// The two models run for minutes between the capture and the save, so a
/// timestamp taken at save time attributes the activity to whenever inference
/// happened to finish. The capture moment travels with the result instead.
@Suite
struct CaptureTimeTests {
    private static let capturedAt = Date(timeIntervalSince1970: 1_767_610_800)

    private func result(activeScreen: Int?) -> IdentificationResult {
        #if DEBUG
        IdentificationResult(
            activity: .workCoding,
            reasoning: "An IDE with company code",
            description: "Editing a Swift file",
            capturedAt: Self.capturedAt,
            activeScreen: activeScreen,
            screenshotPaths: nil,
            screenDebugInfo: nil,
            samplePath: nil
        )
        #else
        IdentificationResult(
            activity: .workCoding,
            reasoning: "An IDE with company code",
            description: "Editing a Swift file",
            capturedAt: Self.capturedAt,
            activeScreen: activeScreen,
            screenshotPaths: nil,
            screenDebugInfo: nil
        )
        #endif
    }

    @Test
    func anEntryCarriesTheCaptureMomentNotTheSaveMoment() {
        let entry = result(activeScreen: 1).toActivityEntry(device: "Work MBP")

        #expect(entry.timestamp == "2026-01-05T11:00:00Z")
    }

    /// The whole point of the change: a result with no active screen is still a
    /// result, and still stores.
    @Test
    func anEntryStoresWithoutAnActiveScreen() {
        let entry = result(activeScreen: nil).toActivityEntry(device: "Work MBP")

        #expect(entry.activity == .workCoding)
        #expect(entry.timestamp == "2026-01-05T11:00:00Z")
    }
}
