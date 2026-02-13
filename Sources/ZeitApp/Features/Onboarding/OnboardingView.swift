import ComposableArchitecture
import SwiftUI

struct OnboardingView: View {
    let store: StoreOf<OnboardingFeature>

    var body: some View {
        switch store.step {
        case .permissions:
            PermissionsView(
                store: store.scope(state: \.permissions, action: \.permissions)
            )
        case .modelDownload:
            ModelDownloadView(
                store: store.scope(state: \.modelDownload, action: \.modelDownload)
            )
        case .otherSettings:
            OtherSettingsView(
                store: store.scope(state: \.otherSettings, action: \.otherSettings)
            )
        }
    }
}
