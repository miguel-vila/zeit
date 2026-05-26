import Dependencies
import DependenciesMacros
import Foundation

/// Download progress for a single model
struct ModelProgress: Equatable, Sendable {
    let modelName: String
    let progress: Double
    let status: ModelDownloadStatus
}

/// Identifies which catalog models are currently selected as active.
struct ActiveModels: Equatable, Sendable {
    let vision: String
    let textProvider: String
    let text: String
}

// MARK: - Client Interface

@DependencyClient
struct ModelClient: Sendable {
    /// Check if a specific model is downloaded
    var isModelDownloaded: @Sendable (String) async -> Bool = { _ in false }

    /// Check if the currently-active vision + text models are downloaded
    var allModelsDownloaded: @Sendable () async -> Bool = { false }

    /// Download a model by config name, reporting progress via callback
    var downloadModel: @Sendable (String, @Sendable @escaping (Double) -> Void) async throws -> Void

    /// Delete a model's cached weights from disk
    var deleteModel: @Sendable (String) async throws -> Void

    /// Get the list of supported models with their status
    var getModelStatuses: @Sendable () async -> [ModelProgress] = { [] }

    /// Read the active vision + text model selection from config
    var getActiveModels: @Sendable () async -> ActiveModels = {
        ActiveModels(vision: "qwen3-vl:4b", textProvider: "mlx", text: "qwen3:8b")
    }

    /// Persist a new active vision + text model selection
    var setActiveModels: @Sendable (ActiveModels) async throws -> Void
}

// MARK: - Dependency Registration

extension DependencyValues {
    var modelClient: ModelClient {
        get { self[ModelClient.self] }
        set { self[ModelClient.self] = newValue }
    }
}

// MARK: - Live Implementation

extension ModelClient: DependencyKey {
    static let liveValue = ModelClient(
        isModelDownloaded: { configName in
            guard let model = MLXModelManager.modelInfo(forConfigName: configName) else {
                return false
            }
            return await MLXModelManager.shared.isModelDownloaded(model: model)
        },
        allModelsDownloaded: {
            await MLXModelManager.shared.activeModelsDownloaded()
        },
        downloadModel: { configName, progressHandler in
            guard let model = MLXModelManager.modelInfo(forConfigName: configName) else {
                throw ModelClientError.unknownModel(configName)
            }
            try await MLXModelManager.shared.downloadModel(model, progressHandler: progressHandler)
        },
        deleteModel: { configName in
            guard let model = MLXModelManager.modelInfo(forConfigName: configName) else {
                throw ModelClientError.unknownModel(configName)
            }
            try await MLXModelManager.shared.deleteModel(model)
        },
        getModelStatuses: {
            var statuses: [ModelProgress] = []
            for model in MLXModelManager.supportedModels {
                let status = await MLXModelManager.shared.downloadStatus(for: model)
                statuses.append(ModelProgress(
                    modelName: model.configName,
                    progress: status == .downloaded ? 1.0 : 0.0,
                    status: status
                ))
            }
            return statuses
        },
        getActiveModels: {
            let config = ZeitConfig.load()
            return ActiveModels(
                vision: config.models.vision,
                textProvider: config.models.text.provider,
                text: config.models.text.model
            )
        },
        setActiveModels: { models in
            try ZeitConfig.saveModels(
                vision: models.vision,
                textProvider: models.textProvider,
                textModel: models.text
            )
        }
    )
}

// MARK: - Errors

enum ModelClientError: LocalizedError {
    case unknownModel(String)

    var errorDescription: String? {
        switch self {
        case .unknownModel(let name):
            return "Unknown model: \(name)"
        }
    }
}
