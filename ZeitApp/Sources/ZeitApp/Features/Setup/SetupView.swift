import ComposableArchitecture
import SwiftUI

struct SetupView: View {
    let store: StoreOf<SetupFeature>

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Welcome to Zeit")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Activity Tracking for macOS")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    store.send(.close)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape)
            }

            Text("""
                Zeit tracks your computer activity throughout the day, helping you \
                understand how you spend your time.
                """)
            .foregroundStyle(.secondary)

            Divider()

            // Cards
            VStack(spacing: 12) {
                SetupCard(
                    icon: "square.and.arrow.down",
                    iconColor: .blue,
                    title: "What will be installed"
                ) {
                    BulletPoint(
                        title: "CLI Tool",
                        description: "(~/.local/bin/zeit) - Command-line interface"
                    )
                    BulletPoint(
                        title: "Background Tracker",
                        description: "LaunchAgent that captures screenshots every minute"
                    )
                }

                SetupCard(
                    icon: "lock.shield",
                    iconColor: .orange,
                    title: "Permissions required"
                ) {
                    BulletPoint(
                        title: "Screen Recording",
                        description: "to capture screenshots"
                    )
                    BulletPoint(
                        title: "Accessibility",
                        description: "to detect the active window"
                    )
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                Text("Your data stays local. Zeit uses Ollama for AI processing.")
                    .font(.caption)
            }
            .foregroundStyle(.tertiary)

            Spacer()

            // Progress/Result
            if store.isInstalling {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text(store.progress)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else if let result = store.result {
                switch result {
                case .success:
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Setup completed successfully!")
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(.green)
                    .padding(.vertical, 4)
                case .failure(let error):
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle.fill")
                        Text("Setup failed: \(error)")
                    }
                    .foregroundStyle(.red)
                    .font(.subheadline)
                    .padding(.vertical, 4)
                }
            }

            // Buttons
            HStack {
                if store.result == nil {
                    Button("Skip Setup") {
                        store.send(.skip)
                    }

                    Spacer()

                    Button {
                        store.send(.install)
                    } label: {
                        HStack(spacing: 4) {
                            if store.isInstalling {
                                ProgressView()
                                    .scaleEffect(0.5)
                                    .frame(width: 12, height: 12)
                            } else {
                                Image(systemName: "arrow.down.circle")
                                    .font(.caption)
                            }
                            Text("Install")
                        }
                    }
                    .disabled(store.isInstalling)
                    .buttonStyle(.borderedProminent)
                } else {
                    Spacer()
                }
            }
        }
        .padding(26)
        .frame(minWidth: 520, minHeight: 420)
    }
}

// MARK: - Setup Card

private struct SetupCard<Content: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(title)
                    .fontWeight(.semibold)
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
                    .font(.caption)
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.03))
        )
    }
}

// MARK: - Bullet Point

private struct BulletPoint: View {
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\u{2022}")
                .foregroundStyle(.tertiary)
            Text(title)
                .fontWeight(.medium)
                + Text(" ")
                + Text(description)
                    .foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .padding(.leading, 4)
    }
}
