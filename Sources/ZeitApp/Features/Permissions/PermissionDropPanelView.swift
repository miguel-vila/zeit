import AppKit
import SwiftUI

/// The contents of the panel that floats over System Settings: a line telling
/// the user where to aim, and a chip that drags Zeit itself.
///
/// Dropping the chip on the privacy list adds Zeit to it and switches it on,
/// which is the whole point — the alternative is the `+` button and a file
/// dialog, or hunting for Zeit in a list it is not in yet.
struct PermissionDropPanelView: View {
    let permission: Permission
    let onClose: () -> Void

    private var subject: URL { Permission.tccSubject }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up")
                    .font(.caption.weight(.bold))

                Text("Drag \(Self.appName) into the \(permission.displayName) list above")
                    .font(.callout.weight(.medium))

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Close")
            }

            chip
                .onDrag({ NSItemProvider(object: subject as NSURL) }, preview: { chip })
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.separator, lineWidth: 1)
        )
    }

    private var chip: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: subject.path))
                .resizable()
                .frame(width: 22, height: 22)

            Text(Self.appName)
                .font(.callout)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        .contentShape(RoundedRectangle(cornerRadius: 8))
    }

    private static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Zeit"
    }
}
