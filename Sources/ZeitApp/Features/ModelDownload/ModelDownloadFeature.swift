import ComposableArchitecture
import Foundation

/// TCA feature for managing model downloads during onboarding.
@Reducer
struct ModelDownloadFeature {
    @ObservableState
    struct State: Equatable {
        var models: [ModelState] = MLXModelManager.supportedModels.map { model in
            ModelState(
                configName: model.configName,
                displayName: model.displayName,
                approximateSizeGB: model.approximateSizeGB,
                isVision: model.isVision,
                status: .notDownloaded,
                progress: 0
            )
        }

        var allDownloaded: Bool {
            models.allSatisfy { $0.status == .downloaded }
        }

        var isAnyDownloading: Bool {
            models.contains { $0.status == .downloading }
        }

        struct ModelState: Equatable, Identifiable {
            let configName: String
            let displayName: String
            let approximateSizeGB: Double
            let isVision: Bool
            var status: Status
            var progress: Double

            var id: String { configName }

            enum Status: Equatable {
                case notDownloaded
                case downloading
                case downloaded
                case error(String)
            }
        }
    }

    enum Action {
        case task
        case statusesLoaded([ModelProgress])
        case downloadAll
        case downloadModel(String)
        case downloadProgress(configName: String, progress: Double)
        case downloadCompleted(configName: String)
        case downloadFailed(configName: String, error: String)
        case continuePressed
        case allModelsReady
    }

    @Dependency(\.modelClient) var modelClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                return .run { send in
                    let statuses = await modelClient.getModelStatuses()
                    await send(.statusesLoaded(statuses))
                }

            case .statusesLoaded(let statuses):
                for status in statuses {
                    if let index = state.models.firstIndex(where: { $0.configName == status.modelName }) {
                        switch status.status {
                        case .downloaded:
                            state.models[index].status = .downloaded
                            state.models[index].progress = 1.0
                        case .downloading(let progress):
                            state.models[index].status = .downloading
                            state.models[index].progress = progress
                        case .notDownloaded:
                            state.models[index].status = .notDownloaded
                        case .error(let msg):
                            state.models[index].status = .error(msg)
                        }
                    }
                }

                if state.allDownloaded {
                    return .send(.allModelsReady)
                }
                return .none

            case .downloadAll:
                let modelsToDownload = state.models
                    .filter { $0.status != .downloaded && $0.status != .downloading }
                    .map(\.configName)

                guard !modelsToDownload.isEmpty else { return .none }

                // Start downloads sequentially to avoid memory pressure
                return .run { send in
                    for configName in modelsToDownload {
                        await send(.downloadModel(configName))
                    }
                }

            case .downloadModel(let configName):
                if let index = state.models.firstIndex(where: { $0.configName == configName }) {
                    state.models[index].status = .downloading
                    state.models[index].progress = 0
                }

                return .run { send in
                    do {
                        try await modelClient.downloadModel(configName) { progress in
                            // Fire-and-forget progress update
                            Task {
                                await send(.downloadProgress(configName: configName, progress: progress))
                            }
                        }
                        await send(.downloadCompleted(configName: configName))
                    } catch {
                        await send(.downloadFailed(
                            configName: configName,
                            error: error.localizedDescription
                        ))
                    }
                }

            case .downloadProgress(let configName, let progress):
                if let index = state.models.firstIndex(where: { $0.configName == configName }) {
                    state.models[index].progress = progress
                }
                return .none

            case .downloadCompleted(let configName):
                if let index = state.models.firstIndex(where: { $0.configName == configName }) {
                    state.models[index].status = .downloaded
                    state.models[index].progress = 1.0
                }

                if state.allDownloaded {
                    return .send(.allModelsReady)
                }
                return .none

            case .downloadFailed(let configName, let error):
                if let index = state.models.firstIndex(where: { $0.configName == configName }) {
                    state.models[index].status = .error(error)
                    state.models[index].progress = 0
                }
                return .none

            case .continuePressed:
                return .none

            case .allModelsReady:
                return .none
            }
        }
    }
}
