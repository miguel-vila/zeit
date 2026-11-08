import ComposableArchitecture
import Foundation
import Testing

@testable import ZeitApp

/// launchd keeps the menubar app alive, which is what brings Zeit back when
/// System Settings kills it after a permission grant. The cost is that quitting
/// has to take the job out of the login session, or launchd undoes it; and that
/// "starts at login" can no longer mean "the job is loaded", because quitting
/// unloads it.
@Suite
@MainActor
struct MenubarLifecycleTests {
    @Test
    func quittingGoesThroughTheLaunchAgentSoLaunchdDoesNotUndoIt() async {
        let quit = LockIsolated(false)

        let store = TestStore(initialState: MenubarFeature.State()) {
            MenubarFeature()
        } withDependencies: {
            $0.launchAgentClient.quitApp = { quit.setValue(true) }
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.quitApp)
        await store.finish()

        #expect(quit.value)
    }

    /// Turning the toggle off must not kill the running app: it only decides
    /// what happens at the next login.
    @Test
    func turningLaunchAtLoginOffOnlyRemovesThePlist() async {
        let disabled = LockIsolated(false)
        let quit = LockIsolated(false)

        let store = TestStore(
            initialState: MenubarFeature.State(launchAtLogin: true)
        ) {
            MenubarFeature()
        } withDependencies: {
            $0.launchAgentClient.disableLaunchAtLogin = { disabled.setValue(true) }
            $0.launchAgentClient.quitApp = { quit.setValue(true) }
            $0.notificationClient.show = { _, _, _ in }
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.toggleLaunchAtLogin)
        await store.finish()

        #expect(disabled.value)
        #expect(!quit.value)
    }
}
