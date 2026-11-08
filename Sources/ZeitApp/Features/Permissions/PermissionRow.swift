import SwiftUI

/// One permission's state and the button that grants it. Shared by the
/// onboarding step and the Settings tab, which show the same thing.
struct PermissionRow: View {
    let permission: Permission
    let isGranted: Bool
    /// The drop panel is open over System Settings for this permission.
    let isGuiding: Bool
    let onGrant: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isGranted ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                    .frame(width: 36, height: 36)

                Image(systemName: isGranted ? "checkmark.circle.fill" : permission.iconName)
                    .foregroundStyle(isGranted ? .green : .secondary)
                    .font(.body)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(permission.displayName)
                    .fontWeight(.semibold)

                Text(isGuiding ? "Drag Zeit into the list in System Settings" : permission.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isGranted {
                Text("Granted")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.green)
            } else {
                Button(isGuiding ? "Waiting…" : "Grant") {
                    onGrant()
                }
                .controlSize(.small)
                .disabled(isGuiding)
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

/// The list of every permission Zeit needs, driven by `PermissionsFeature`.
struct PermissionRows: View {
    let granted: Set<Permission>
    let guiding: Permission?
    let onGrant: (Permission) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Permission.allCases, id: \.self) { permission in
                PermissionRow(
                    permission: permission,
                    isGranted: granted.contains(permission),
                    isGuiding: guiding == permission,
                    onGrant: { onGrant(permission) }
                )
            }
        }
    }
}
