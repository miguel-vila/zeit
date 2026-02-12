import ComposableArchitecture
import SwiftUI

struct OnboardingView: View {
    let store: StoreOf<OnboardingFeature>

    var body: some View {
        PermissionsView(
            store: store.scope(state: \.permissions, action: \.permissions)
        )
    }
}
