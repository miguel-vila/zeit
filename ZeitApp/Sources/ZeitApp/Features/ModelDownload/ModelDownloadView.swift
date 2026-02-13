import ComposableArchitecture
import SwiftUI

struct ModelDownloadView: View {
    let store: StoreOf<ModelDownloadFeature>

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with close button
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI Models Setup")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(
                        "Download the AI models needed for activity tracking."
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
                "Models are downloaded once and run entirely on your Mac."
                    + " No internet connection needed after setup."
            )
            .font(.caption)
            .foregroundStyle(.tertiary)

            Divider()

            // Model rows
            VStack(spacing: 8) {
                ForEach(store.models) { model in
                    ModelRow(model: model) {
                        store.send(.downloadModel(model.configName))
                    }
                }
            }

            Spacer()

            // Buttons
            HStack(spacing: 10) {
                if !store.allDownloaded && !store.isAnyDownloading {
                    Button("Download All") {
                        store.send(.downloadAll)
                    }
                    .controlSize(.small)
                }

                Spacer()

                Button("Skip for Now") {
                    store.send(.skip)
                }

                Button("Continue") {
                    store.send(.continuePressed)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!store.allDownloaded)
            }
        }
        .padding(22)
        .frame(minWidth: 500, minHeight: 350)
        .task {
            await store.send(.task).finish()
        }
    }
}

// MARK: - Model Row

private struct ModelRow: View {
    let model: ModelDownloadFeature.State.ModelState
    let onDownload: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(statusColor.opacity(0.1))
                    .frame(width: 36, height: 36)

                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                    .font(.body)
            }

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName)
                    .fontWeight(.semibold)

                Text(statusDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Progress or action
            switch model.status {
            case .notDownloaded:
                Button("Download") {
                    onDownload()
                }
                .controlSize(.small)

            case .downloading:
                VStack(alignment: .trailing, spacing: 2) {
                    ProgressView(value: model.progress)
                        .frame(width: 80)

                    Text("\(Int(model.progress * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

            case .downloaded:
                Text("Ready")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.green)

            case .error:
                Button("Retry") {
                    onDownload()
                }
                .controlSize(.small)
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

    private var statusColor: Color {
        switch model.status {
        case .downloaded: return .green
        case .downloading: return .blue
        case .error: return .red
        case .notDownloaded: return .secondary
        }
    }

    private var statusIcon: String {
        switch model.status {
        case .downloaded: return "checkmark.circle.fill"
        case .downloading: return "arrow.down.circle"
        case .error: return "exclamationmark.circle.fill"
        case .notDownloaded: return model.isVision ? "eye.fill" : "text.bubble.fill"
        }
    }

    private var statusDescription: String {
        switch model.status {
        case .notDownloaded:
            return "\(model.isVision ? "Vision" : "Text") model (~\(String(format: "%.1f", model.approximateSizeGB)) GB)"
        case .downloading:
            return "Downloading..."
        case .downloaded:
            return "Downloaded and ready"
        case .error(let msg):
            return "Error: \(msg)"
        }
    }
}
