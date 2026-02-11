import ComposableArchitecture
import SwiftUI

struct PermissionsView: View {
    let store: StoreOf<PermissionsFeature>

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with close button
            HStack(alignment: .top) {
                Text("Permissions Required")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                Button {
                    store.send(.skip)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape)
            }

            VStack(alignment: .leading, spacing: 4) {

                Text(
                    "The Zeit tracker (CLI) needs the following permissions. "
                        + "Grant permissions to the 'zeit' binary in System Settings."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)

                Text(
                    "Note: You may need to grant permissions to both the CLI binary "
                        + "and this app separately."
                )
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
            }

            Divider()

            // Permission rows
            VStack(spacing: 12) {
                PermissionRow(
                    name: "Screen Recording",
                    description: "Required to capture screenshots for activity tracking",
                    isGranted: store.screenRecordingGranted,
                    onOpenSettings: { store.send(.openScreenRecordingSettings) }
                )

                PermissionRow(
                    name: "Accessibility",
                    description: "Required to detect which window is currently active",
                    isGranted: store.accessibilityGranted,
                    onOpenSettings: { store.send(.openAccessibilitySettings) }
                )
            }

            Spacer()

            // Buttons
            HStack {
                Button("Check Again") {
                    store.send(.checkPermissions)
                }

                Spacer()

                Button("Skip for Now") {
                    store.send(.skip)
                }

                Button("Continue") {
                    store.send(.continuePressed)
                }
                .disabled(!store.allGranted)
            }
        }
        .padding(20)
        .frame(minWidth: 500, minHeight: 300)
        .task {
            await store.send(.task).finish()
        }
    }
}

// MARK: - Permission Row

private struct PermissionRow: View {
    let name: String
    let description: String
    let isGranted: Bool
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Image(systemName: isGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(isGranted ? .green : .red)
                .font(.title2)

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .fontWeight(.semibold)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Action button
            Button(isGranted ? "Granted" : "Open Settings") {
                onOpenSettings()
            }
            .disabled(isGranted)
        }
        .padding(.vertical, 8)
    }
}
