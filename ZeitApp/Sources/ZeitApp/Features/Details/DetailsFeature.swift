import ComposableArchitecture
import Foundation

@Reducer
struct DetailsFeature {
    @ObservableState
    struct State: Equatable {
        var date: String
        var stats: [ActivityStat]
        var totalActivities: Int
    }

    enum Action {
        case close
    }

    @Dependency(\.dismiss) var dismiss

    var body: some ReducerOf<Self> {
        Reduce { _, action in
            switch action {
            case .close:
                return .run { _ in
                    await dismiss()
                }
            }
        }
    }
}
