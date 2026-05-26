import ComposableArchitecture
import Foundation

/// TCA feature for managing model downloads during onboarding.
@Reducer
struct ModelDownloadFeature {
    @ObservableState
    struct State: Equatable {
        var models: [ModelState] = MLXModelManager.supportedModels.map { ModelState(from: $0) }

        /// The vision model the user has chosen to use.
        var selectedVision: String = MLXModelManager.visionModel.configName
        /// The text model the user has chosen to use.
        var selectedText: String = MLXModelManager.textModel.configName

        var visionModels: [ModelState] {
            models.filter(\.isVision)
        }

        var textModels: [ModelState] {
            models.filter { !$0.isVision }
        }

        /// Setup is complete when the *selected* vision + text models are downloaded.
        var allDownloaded: Bool {
            let visionReady = models.first(where: { $0.configName == selectedVision })?.status == .downloaded
            let textReady = models.first(where: { $0.configName == selectedText })?.status == .downloaded
            return visionReady && textReady
        }

        var isAnyDownloading: Bool {
            models.contains { $0.status == .downloading }
        }

        /// Models that the user has selected and which still need to be downloaded.
        var pendingSelected: [String] {
            [selectedVision, selectedText].filter { name in
                guard let model = models.first(where: { $0.configName == name }) else { return false }
                return model.status != .downloaded && model.status != .downloading
            }
        }

        struct ModelState: Equatable, Identifiable {
            let configName: String
            let displayName: String
            let approximateSizeGB: Double
            let isVision: Bool
            let releaseDate: String
            var status: Status
            var progress: Double

            var id: String { configName }

            init(
                configName: String,
                displayName: String,
                approximateSizeGB: Double,
                isVision: Bool,
                releaseDate: String,
                status: Status,
                progress: Double
            ) {
                self.configName = configName
                self.displayName = displayName
                self.approximateSizeGB = approximateSizeGB
                self.isVision = isVision
                self.releaseDate = releaseDate
                self.status = status
                self.progress = progress
            }

            init(from info: MLXModelInfo) {
                self.init(
                    configName: info.configName,
                    displayName: info.displayName,
                    approximateSizeGB: info.approximateSizeGB,
                    isVision: info.isVision,
                    releaseDate: info.releaseDate,
                    status: .notDownloaded,
                    progress: 0
                )
            }

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
        case activeModelsLoaded(ActiveModels)
        case statusesLoaded([ModelProgress])
        case selectVision(String)
        case selectText(String)
        case downloadSelected
        case downloadModel(String)
        case deleteModel(String)
        case downloadProgress(configName: String, progress: Double)
        case downloadCompleted(configName: String)
        case downloadFailed(configName: String, error: String)
        case continuePressed
        case allModelsReady
        case persistSelection
        case persistSelectionFailed(String)
    }

    @Dependency(\.modelClient) var modelClient
    @Dependency(\.notificationClient) var notificationClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                return .merge(
                    .run { send in
                        let active = await modelClient.getActiveModels()
                        await send(.activeModelsLoaded(active))
                    },
                    .run { send in
                        let statuses = await modelClient.getModelStatuses()
                        await send(.statusesLoaded(statuses))
                    }
                )

            case .activeModelsLoaded(let active):
                if MLXModelManager.modelInfo(forConfigName: active.vision) != nil {
                    state.selectedVision = active.vision
                }
                if active.textProvider.lowercased() == "mlx",
                   MLXModelManager.modelInfo(forConfigName: active.text) != nil
                {
                    state.selectedText = active.text
                }
                return .none

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

            case .selectVision(let name):
                guard state.models.contains(where: { $0.configName == name && $0.isVision }) else {
                    return .none
                }
                state.selectedVision = name
                return .send(.persistSelection)

            case .selectText(let name):
                guard state.models.contains(where: { $0.configName == name && !$0.isVision }) else {
                    return .none
                }
                state.selectedText = name
                return .send(.persistSelection)

            case .downloadSelected:
                let pending = state.pendingSelected
                guard !pending.isEmpty else { return .none }
                return .run { send in
                    for configName in pending {
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

            case .deleteModel(let configName):
                // Refuse to delete a model that is currently selected as active.
                if configName == state.selectedVision || configName == state.selectedText {
                    return .none
                }
                if let index = state.models.firstIndex(where: { $0.configName == configName }) {
                    state.models[index].status = .notDownloaded
                    state.models[index].progress = 0
                }
                return .run { _ in
                    try? await modelClient.deleteModel(configName)
                }

            case .downloadProgress(let configName, let progress):
                if let index = state.models.firstIndex(where: { $0.configName == configName }) {
                    state.models[index].progress = progress
                }
                return .none

            case .downloadCompleted(let configName):
                var displayName = configName
                if let index = state.models.firstIndex(where: { $0.configName == configName }) {
                    state.models[index].status = .downloaded
                    state.models[index].progress = 1.0
                    displayName = state.models[index].displayName
                }

                let allReady = state.allDownloaded
                let modelDisplayName = displayName
                return .run { send in
                    if allReady {
                        await notificationClient.show(
                            "All Models Ready",
                            "Setup Complete",
                            "All AI models have been downloaded. Zeit is ready to start tracking your activities."
                        )
                        await send(.allModelsReady)
                    } else {
                        await notificationClient.show(
                            "Model Downloaded",
                            modelDisplayName,
                            "\(modelDisplayName) is ready."
                        )
                    }
                }

            case .downloadFailed(let configName, let error):
                if let index = state.models.firstIndex(where: { $0.configName == configName }) {
                    state.models[index].status = .error(error)
                    state.models[index].progress = 0
                }
                return .none

            case .continuePressed:
                return .send(.persistSelection)

            case .allModelsReady:
                return .none

            case .persistSelection:
                let active = ActiveModels(
                    vision: state.selectedVision,
                    textProvider: "mlx",
                    text: state.selectedText
                )
                return .run { send in
                    do {
                        try await modelClient.setActiveModels(active)
                    } catch {
                        await send(.persistSelectionFailed(error.localizedDescription))
                    }
                }

            case .persistSelectionFailed:
                // Persistence is best-effort during onboarding; surface in logs only.
                return .none
            }
        }
    }
}
