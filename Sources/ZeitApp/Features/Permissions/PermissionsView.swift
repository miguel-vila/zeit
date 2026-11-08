import ComposableArchitecture
import SwiftUI

struct PermissionsView: View {
    let store: StoreOf<PermissionsFeature>

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Permissions Required")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Zeit needs these to see what you are working on.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            PermissionRows(
                granted: store.granted,
                guiding: store.guiding,
                onGrant: { store.send(.grantRequested($0)) }
            )

            Spacer()

            HStack(spacing: 10) {
                Text("Permissions refresh automatically")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Spacer()

                Button("Continue") {
                    store.send(.continuePressed)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!store.allGranted)
            }
        }
        .padding(22)
        .frame(minWidth: 500, minHeight: 300)
        .task {
            await store.send(.task).finish()
        }
    }
}
