import ComposableArchitecture
import SwiftUI

struct OnboardingView: View {
    let store: StoreOf<OnboardingFeature>

    var body: some View {
        Group {
            switch store.step {
            case .permissions:
                PermissionsView(
                    store: store.scope(state: \.permissions, action: \.permissions)
                )
            case .setup:
                SetupView(
                    store: store.scope(state: \.setup, action: \.setup)
                )
            }
        }
        .animation(.default, value: store.step)
    }
}
