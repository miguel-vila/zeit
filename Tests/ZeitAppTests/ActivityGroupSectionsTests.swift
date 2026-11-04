import SwiftUI
import Testing

@testable import ZeitApp

/// The sections the details panel renders, derived from the group enum.
@Suite
struct ActivityStatSectionTests {
    private func stat(
        _ id: String, _ group: ActivityGroup?, percentage: Double = 10
    ) -> ActivityStat {
        ActivityStat(
            activity: Activity(rawValue: id),
            count: Int(percentage),
            percentage: percentage,
            group: group
        )
    }

    @Test
    func sections_followTheOrderOfTheGroupEnumWithUnclassifiedLast() {
        let stats = [
            stat("retired_type", nil),
            stat("social_media", .personal),
            stat("project_coding", .personalProjects),
            stat("work_coding", .work),
        ]

        let sections = groupSections(in: stats)

        #expect(sections.map(\.group) == ActivityGroup.allCases + [nil])
        #expect(sections.map(\.title) == ["Work", "Personal Projects", "Personal", "Unclassified"])
    }

    @Test
    func sections_dropEveryGroupWithoutStats() {
        let sections = groupSections(in: [stat("work_coding", .work)])

        #expect(sections.map(\.group) == [.work])
        #expect(sections.map(\.stats) == [[stat("work_coding", .work)]])
    }

    /// An id missing from the type table gets its own section, never folded into
    /// a group it was not labelled with.
    @Test
    func sections_showUnclassifiedOnlyWhenAnIDIsMissing() {
        let classified = [stat("work_coding", .work), stat("social_media", .personal)]
        #expect(!groupSections(in: classified).contains { $0.group == nil })

        let withOrphan = classified + [stat("retired_type", nil)]
        let unclassified = groupSections(in: withOrphan).first { $0.group == nil }
        #expect(unclassified?.stats.map(\.id) == ["retired_type"])
        #expect(unclassified?.title == "Unclassified")
    }

    /// Idle is not a group, and in particular is not Unclassified.
    @Test
    func sections_leaveIdleOut() {
        let sections = groupSections(in: [stat("work_coding", .work), stat("idle", nil)])

        #expect(sections.map(\.group) == [.work])
        #expect(!sections.flatMap(\.stats).contains { $0.isIdle })
    }

    @Test
    func sectionIDs_areStableAndDistinct() {
        let ids = (ActivityGroup.allCases.map { Optional($0) } + [nil]).map {
            ActivityStatSection(group: $0, stats: []).id
        }

        #expect(Set(ids).count == ids.count)
        #expect(ids.last == "unclassified")
    }
}

/// Each group is drawn in its own colour, with grey for Unclassified.
@Suite
struct ActivityGroupStyleTests {
    @Test
    func everyGroupHasItsOwnColourAndIcon() {
        let colors = ActivityGroup.allCases.map(\.color)
        let icons = ActivityGroup.allCases.map(\.iconName)

        #expect(Set(colors).count == ActivityGroup.allCases.count)
        #expect(Set(icons).count == ActivityGroup.allCases.count)
    }

    @Test
    func unclassifiedIsGreyAndUnlikeEveryGroup() {
        let absent: ActivityGroup? = nil

        #expect(absent.sectionColor == Color.gray)
        #expect(absent.sectionTitle == ActivityGroup.unclassifiedLabel)
        #expect(!ActivityGroup.allCases.map(\.color).contains(absent.sectionColor))
    }

    @Test(arguments: ActivityGroup.allCases)
    func aPresentGroupStylesAsItself(group: ActivityGroup) {
        let optional: ActivityGroup? = group

        #expect(optional.sectionColor == group.color)
        #expect(optional.sectionIconName == group.iconName)
        #expect(optional.sectionTitle == group.displayName)
    }
}
