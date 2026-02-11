import ComposableArchitecture
import SwiftUI

struct DetailsView: View {
    let store: StoreOf<DetailsFeature>

    private var totalTrackedMinutes: Int {
        store.stats.reduce(0) { $0 + $1.count }
    }

    private var formattedTrackedTime: String {
        let hours = totalTrackedMinutes / 60
        let minutes = totalTrackedMinutes % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Activity Summary")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("\(store.date) • \(store.totalActivities) activities tracked")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Total tracked time
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
                Text("Total tracked time:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(formattedTrackedTime)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }

            Divider()

            // Activity breakdown
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(store.stats) { stat in
                        ActivityRow(stat: stat)
                    }
                }
            }

            Spacer()

            // Close button
            HStack {
                Spacer()
                Button("Close") {
                    store.send(.close)
                }
                .keyboardShortcut(.escape)
            }
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 350)
    }
}

// MARK: - Activity Row

private struct ActivityRow: View {
    let stat: ActivityStat

    private var barColor: Color {
        stat.activity.isWork
            ? Color(red: 0.2, green: 0.7, blue: 0.6)  // teal for work
            : Color(red: 0.6, green: 0.4, blue: 0.8)   // purple for personal
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle()
                    .fill(barColor)
                    .frame(width: 8, height: 8)

                Text(stat.activity.displayName)
                    .font(.body)

                Spacer()

                Text("\(String(format: "%.1f", stat.percentage))%")
                    .font(.body)
                    .fontWeight(.semibold)

                Text("(\(stat.count) min)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ActivityProgressBar(percentage: stat.percentage, color: barColor)
        }
    }
}

// MARK: - Custom Progress Bar

private struct ActivityProgressBar: View {
    let percentage: Double
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 4)
                    .fill(color.opacity(0.15))

                // Filled portion
                RoundedRectangle(cornerRadius: 4)
                    .fill(color)
                    .frame(width: max(0, geometry.size.width * percentage / 100))
            }
        }
        .frame(height: 10)
    }
}
