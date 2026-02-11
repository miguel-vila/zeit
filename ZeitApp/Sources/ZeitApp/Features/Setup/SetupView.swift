import ComposableArchitecture
import SwiftUI

struct SetupView: View {
    let store: StoreOf<SetupFeature>

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Welcome to Zeit")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Activity Tracking for macOS")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Description
            VStack(alignment: .leading, spacing: 12) {
                Text("""
                    Zeit tracks your computer activity throughout the day, helping you \
                    understand how you spend your time.
                    """)

                Group {
                    Text("What will be installed:")
                        .fontWeight(.semibold)

                    BulletPoint(
                        title: "CLI Tool",
                        description: "(~/.local/bin/zeit) - Command-line interface"
                    )
                    BulletPoint(
                        title: "Background Tracker",
                        description: "LaunchAgent that captures screenshots every minute"
                    )
                }

                Group {
                    Text("Permissions required:")
                        .fontWeight(.semibold)

                    BulletPoint(
                        title: "Screen Recording",
                        description: "to capture screenshots"
                    )
                    BulletPoint(
                        title: "Accessibility",
                        description: "to detect the active window"
                    )
                }

                Text("Note: Your data stays local. Zeit uses Ollama for AI processing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Progress/Result
            if store.isInstalling {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(store.progress)
                        .foregroundStyle(.secondary)
                }
            } else if let result = store.result {
                switch result {
                case .success:
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Setup completed successfully!")
                            .foregroundStyle(.green)
                    }
                case .failure(let error):
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                        Text("Setup failed: \(error)")
                            .foregroundStyle(.red)
                    }
                }
            }

            // Buttons
            HStack {
                if store.result == nil {
                    Button("Skip Setup") {
                        store.send(.skip)
                    }

                    Spacer()

                    Button("Install") {
                        store.send(.install)
                    }
                    .disabled(store.isInstalling)
                    .buttonStyle(.borderedProminent)
                } else {
                    Spacer()
                    Button("Close") {
                        store.send(.close)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 500, minHeight: 400)
    }
}

// MARK: - Bullet Point

private struct BulletPoint: View {
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
            Text(title)
                .fontWeight(.medium)
                + Text(" ")
                + Text(description)
                    .foregroundStyle(.secondary)
        }
        .padding(.leading, 8)
    }
}
