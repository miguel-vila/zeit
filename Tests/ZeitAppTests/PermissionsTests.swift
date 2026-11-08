import ComposableArchitecture
import CoreGraphics
import Foundation
import Testing

@testable import ZeitApp

/// Zeit is one TCC subject, and every place that names a permission reads it
/// from `Permission`, so the pane a user is sent to and the grant that is
/// checked cannot drift apart.
@Suite
struct PermissionTests {
    @Test
    func eachPermissionNamesItsOwnPane() {
        #expect(
            Permission.screenRecording.settingsURL.absoluteString
                == "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture"
        )
        #expect(
            Permission.accessibility.settingsURL.absoluteString
                == "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
        )
    }

    /// Only Screen Recording is withheld from a process that was already
    /// running, which is why only that one is re-checked in a new process.
    @Test
    func onlyScreenRecordingIsWithheldFromRunningProcesses() {
        #expect(Permission.screenRecording.appliesOnlyToNewProcesses)
        #expect(!Permission.accessibility.appliesOnlyToNewProcesses)
    }

    /// Each permission has to name its own privacy service, or clearing a
    /// dead entry would clear a list Zeit was never asked about.
    @Test
    func eachPermissionNamesItsOwnPrivacyService() {
        #expect(
            Permission.screenRecording.listRemovalArguments(for: "co.invariante.zeit")
                == ["reset", "ScreenCapture", "co.invariante.zeit"]
        )
        #expect(
            Permission.accessibility.listRemovalArguments(for: "co.invariante.zeit")
                == ["reset", "Accessibility", "co.invariante.zeit"]
        )
    }

    /// The drag chip has to carry the file the privacy list accepts: the app
    /// bundle itself, not the executable buried inside it.
    @Test
    func theDragSubjectIsTheBundleWhenThereIsOne() {
        let subject = Permission.tccSubject
        #expect(subject.isFileURL)
        #expect(FileManager.default.fileExists(atPath: subject.path))
    }
}

/// The window server measures down from the top of the primary display and
/// AppKit up from its bottom, so the panel lands on the wrong half of the
/// screen if the flip is wrong.
@Suite
struct SystemSettingsWindowTests {
    @Test
    func aWindowAtTheTopOfTheScreenIsNearTheTopInAppKit() {
        let frame = SystemSettingsWindow.appKitFrame(
            quartzBounds: CGRect(x: 100, y: 0, width: 800, height: 600),
            primaryScreenHeight: 1000
        )

        #expect(frame == CGRect(x: 100, y: 400, width: 800, height: 600))
    }

    @Test
    func aWindowRestingOnTheBottomEdgeHasZeroY() {
        let frame = SystemSettingsWindow.appKitFrame(
            quartzBounds: CGRect(x: 0, y: 400, width: 800, height: 600),
            primaryScreenHeight: 1000
        )

        #expect(frame.minY == 0)
    }
}

/// The permissions step is what stands between a fresh install and tracking,
/// so it has to notice a grant and say so.
@Suite
@MainActor
struct PermissionsFeatureTests {
    @Test
    func itReportsWhenEveryPermissionIsHeld() async {
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        } withDependencies: {
            $0.permissionsClient.isGranted = { _ in true }
            $0.permissionsClient.observeAppActivation = { .never }
            $0.continuousClock = ImmediateClock()
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.checkPermissions)
        await store.receive(\.permissionsUpdated) {
            $0.granted = Set(Permission.allCases)
        }
        await store.receive(\.allPermissionsGranted)
    }

    @Test
    func aMissingPermissionLeavesTheStepIncomplete() async {
        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        } withDependencies: {
            $0.permissionsClient.isGranted = { $0 == .accessibility }
            $0.permissionsClient.observeAppActivation = { .never }
            $0.continuousClock = ImmediateClock()
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.checkPermissions)
        await store.receive(\.permissionsUpdated) {
            $0.granted = [.accessibility]
        }

        #expect(!store.state.allGranted)
    }

    /// Asking for a grant opens the guide and marks the row as waiting, so the
    /// user is not invited to open a second panel over the first.
    @Test
    func grantingOnePermissionMarksItAsInProgress() async {
        let guided = LockIsolated<[Permission]>([])

        let store = TestStore(initialState: PermissionsFeature.State()) {
            PermissionsFeature()
        } withDependencies: {
            $0.permissionsClient.isGranted = { _ in false }
            $0.permissionsClient.observeAppActivation = { .never }
            $0.permissionsClient.guideGrant = { permission in
                guided.withValue { $0.append(permission) }
            }
            $0.continuousClock = ImmediateClock()
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.grantRequested(.screenRecording)) {
            $0.guiding = .screenRecording
        }
        await store.receive(\.guideFinished) {
            $0.guiding = nil
        }

        #expect(guided.value == [.screenRecording])
    }
}
