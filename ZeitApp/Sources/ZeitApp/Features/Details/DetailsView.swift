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

    private var workStats: [ActivityStat] {
        store.stats.filter { $0.activity.isWork }
    }

    private var personalStats: [ActivityStat] {
        store.stats.filter { !$0.activity.isWork }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Activity Summary")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(store.date)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Summary badges
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption2)
                        Text(formattedTrackedTime)
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.blue.opacity(0.1), in: Capsule())
                    .foregroundStyle(.blue)

                    Text("\(store.totalActivities) tracked")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

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

            Divider()

            // Activity breakdown
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !workStats.isEmpty {
                        ActivitySection(title: "Work", stats: workStats, isWork: true)
                    }

                    if !personalStats.isEmpty {
                        ActivitySection(title: "Personal", stats: personalStats, isWork: false)
                    }
                }
            }

            Spacer()
        }
        .padding(20)
        .frame(minWidth: 440, minHeight: 380)
    }
}

// MARK: - Activity Section

private struct ActivitySection: View {
    let title: String
    let stats: [ActivityStat]
    let isWork: Bool

    private var sectionColor: Color {
        isWork
            ? Color(red: 0.2, green: 0.7, blue: 0.6)
            : Color(red: 0.6, green: 0.4, blue: 0.8)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(sectionColor)
                    .frame(width: 6, height: 6)
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }

            VStack(spacing: 6) {
                ForEach(stats) { stat in
                    ActivityRow(stat: stat, color: sectionColor)
                }
            }
        }
    }
}

// MARK: - Activity Row

private struct ActivityRow: View {
    let stat: ActivityStat
    let color: Color

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(stat.activity.displayName)
                    .font(.body)

                Spacer()

                Text("\(String(format: "%.1f", stat.percentage))%")
                    .font(.body)
                    .fontWeight(.semibold)
                    .monospacedDigit()

                Text("\(stat.count) min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 46, alignment: .trailing)
            }

            ActivityProgressBar(percentage: stat.percentage, color: color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.primary.opacity(0.04) : Color.clear)
        )
        .onHover { hovering in
            isHovered = hovering
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
                RoundedRectangle(cornerRadius: 3)
                    .fill(color.opacity(0.12))

                // Filled portion
                RoundedRectangle(cornerRadius: 3)
                    .fill(color)
                    .frame(width: max(0, geometry.size.width * percentage / 100))
            }
        }
        .frame(height: 6)
    }
}
