import ComposableArchitecture
import Foundation

/// First-run setup feature for installing CLI and LaunchAgents.
/// Note: This is a placeholder - the full implementation will invoke
/// the bundled Python CLI for setup operations.
@Reducer
struct SetupFeature {
    @ObservableState
    struct State: Equatable {
        var isInstalling: Bool = false
        var progress: String = ""
        var result: SetupResult?

        enum SetupResult: Equatable {
            case success
            case failure(String)
        }
    }

    enum Action {
        case install
        case installProgress(String)
        case installCompleted(Result<Void, Error>)
        case skip
        case close
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .install:
                state.isInstalling = true
                state.progress = "Installing..."

                // TODO: Invoke bundled CLI for installation
                // The CLI is bundled at Contents/Resources/zeit/zeit
                return .run { send in
                    await send(.installProgress("Installing CLI binary..."))

                    // Simulate installation for now
                    try? await Task.sleep(for: .seconds(1))

                    await send(.installCompleted(.success(())))
                }

            case .installProgress(let message):
                state.progress = message
                return .none

            case .installCompleted(.success):
                state.isInstalling = false
                state.result = .success
                return .none

            case .installCompleted(.failure(let error)):
                state.isInstalling = false
                state.result = .failure(error.localizedDescription)
                return .none

            case .skip:
                // Parent handles dismissal
                return .none

            case .close:
                // Parent handles dismissal
                return .none
            }
        }
    }
}
