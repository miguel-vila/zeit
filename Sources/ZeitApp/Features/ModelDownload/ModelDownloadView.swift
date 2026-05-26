import ComposableArchitecture
import SwiftUI

struct ModelDownloadView: View {
    let store: StoreOf<ModelDownloadFeature>
    var mode: Mode = .onboarding

    enum Mode {
        case onboarding
        case settings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(mode == .onboarding ? "AI Models Setup" : "AI Models")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(headerSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Text(
                "Models run entirely on your Mac via MLX. Larger models are more accurate but use more memory and disk."
            )
            .font(.caption)
            .foregroundStyle(.tertiary)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ModelSection(
                        title: "Vision model",
                        subtitle: "Describes what's on screen.",
                        models: store.visionModels,
                        selected: store.selectedVision,
                        onSelect: { store.send(.selectVision($0)) },
                        onDownload: { store.send(.downloadModel($0)) },
                        onDelete: { store.send(.deleteModel($0)) }
                    )

                    ModelSection(
                        title: "Text model",
                        subtitle: "Classifies the activity from the description.",
                        models: store.textModels,
                        selected: store.selectedText,
                        onSelect: { store.send(.selectText($0)) },
                        onDownload: { store.send(.downloadModel($0)) },
                        onDelete: { store.send(.deleteModel($0)) }
                    )
                }
            }

            HStack(spacing: 10) {
                if !store.allDownloaded && !store.isAnyDownloading {
                    Button("Download Selected") {
                        store.send(.downloadSelected)
                    }
                    .controlSize(.small)
                }

                Spacer()

                if mode == .onboarding {
                    Button("Continue") {
                        store.send(.continuePressed)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!store.allDownloaded)
                }
            }
        }
        .padding(22)
        .frame(minWidth: 560, minHeight: 460)
        .task {
            await store.send(.task).finish()
        }
    }

    private var headerSubtitle: String {
        switch mode {
        case .onboarding:
            return "Pick the on-device models Zeit should use for activity tracking."
        case .settings:
            return "Switch which on-device models Zeit uses, or download more."
        }
    }
}

// MARK: - Section

private struct ModelSection: View {
    let title: String
    let subtitle: String
    let models: [ModelDownloadFeature.State.ModelState]
    let selected: String
    let onSelect: (String) -> Void
    let onDownload: (String) -> Void
    let onDelete: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 6) {
                ForEach(models) { model in
                    ModelRow(
                        model: model,
                        isSelected: model.configName == selected,
                        onSelect: { onSelect(model.configName) },
                        onDownload: { onDownload(model.configName) },
                        onDelete: { onDelete(model.configName) }
                    )
                }
            }
        }
    }
}

// MARK: - Row

private struct ModelRow: View {
    let model: ModelDownloadFeature.State.ModelState
    let isSelected: Bool
    let onSelect: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onSelect) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help(isSelected ? "Currently selected" : "Select this model")

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(statusColor.opacity(0.1))
                    .frame(width: 32, height: 32)

                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                    .font(.body)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName)
                    .fontWeight(.semibold)

                HStack(spacing: 6) {
                    Text("~\(formattedSize) GB")
                    Text("·")
                    Text("Released \(formattedReleaseDate)")
                    if case .error(let msg) = model.status {
                        Text("·")
                        Text("Error: \(msg)")
                            .foregroundStyle(.red)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            switch model.status {
            case .notDownloaded:
                Button("Download", action: onDownload)
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
                HStack(spacing: 6) {
                    Text("Ready")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.green)

                    if !isSelected {
                        Button(role: .destructive, action: onDelete) {
                            Image(systemName: "trash")
                        }
                        .controlSize(.small)
                        .help("Delete from disk")
                    }
                }

            case .error:
                Button("Retry", action: onDownload)
                    .controlSize(.small)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected
                      ? Color.accentColor.opacity(0.08)
                      : Color.primary.opacity(0.015))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.5) : .clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }

    private var formattedSize: String {
        String(format: "%.1f", model.approximateSizeGB)
    }

    private var formattedReleaseDate: String {
        let inFormatter = DateFormatter()
        inFormatter.dateFormat = "yyyy-MM-dd"
        inFormatter.locale = Locale(identifier: "en_US_POSIX")
        guard let date = inFormatter.date(from: model.releaseDate) else {
            return model.releaseDate
        }
        let outFormatter = DateFormatter()
        outFormatter.dateStyle = .medium
        return outFormatter.string(from: date)
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
}
