import ComposableArchitecture
import SwiftUI

struct PermissionsView: View {
    let store: StoreOf<PermissionsFeature>

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with close button
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Permissions Required")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(
                        "Grant permissions to the 'zeit' binary in System Settings."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    store.send(.skip)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape)
            }

            Text(
                "Note: You may need to grant permissions to both the CLI binary "
                    + "and this app separately."
            )
            .font(.caption)
            .foregroundStyle(.tertiary)

            Divider()

            // Permission rows
            VStack(spacing: 8) {
                PermissionRow(
                    name: "Screen Recording",
                    icon: "camera.fill",
                    description: "Required to capture screenshots for activity tracking",
                    isGranted: store.screenRecordingGranted,
                    onOpenSettings: { store.send(.openScreenRecordingSettings) }
                )

                PermissionRow(
                    name: "Accessibility",
                    icon: "hand.point.up.fill",
                    description: "Required to detect which window is currently active",
                    isGranted: store.accessibilityGranted,
                    onOpenSettings: { store.send(.openAccessibilitySettings) }
                )
            }

            Spacer()

            // Buttons
            HStack(spacing: 10) {
                Button {
                    store.send(.checkPermissions)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                        Text("Check Again")
                    }
                }

                Spacer()

                Button("Skip for Now") {
                    store.send(.skip)
                }

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

// MARK: - Permission Row

private struct PermissionRow: View {
    let name: String
    let icon: String
    let description: String
    let isGranted: Bool
    let onOpenSettings: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isGranted ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                    .frame(width: 36, height: 36)

                Image(systemName: isGranted ? "checkmark.circle.fill" : icon)
                    .foregroundStyle(isGranted ? .green : .secondary)
                    .font(.body)
            }

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
            if !isGranted {
                Button("Open Settings") {
                    onOpenSettings()
                }
                .controlSize(.small)
            } else {
                Text("Granted")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.green)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.primary.opacity(0.03) : Color.primary.opacity(0.015))
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
