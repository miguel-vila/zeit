import Foundation
import Hub
import MLXLMCommon
import MLXLLM
import MLXVLM
import os

private let logger = Logger(subsystem: "com.zeit", category: "MLXModelManager")

/// Represents a model that Zeit can manage locally via MLX
struct MLXModelInfo: Sendable, Equatable {
    /// Config name (e.g. "qwen3-vl:4b")
    let configName: String
    /// Hugging Face model ID for MLX (e.g. "mlx-community/Qwen3-VL-4B-Instruct-4bit")
    let huggingFaceID: String
    /// Human-readable display name
    let displayName: String
    /// Whether this is a vision model
    let isVision: Bool
    /// Approximate download size in GB
    let approximateSizeGB: Double
}

/// Errors thrown when model operations fail
enum MLXModelError: LocalizedError {
    case modelNotDownloaded(MLXModelInfo)

    var errorDescription: String? {
        switch self {
        case .modelNotDownloaded(let model):
            return "Model '\(model.displayName)' is not downloaded. Run the Zeit app to complete onboarding, or run 'zeit doctor' to check model status."
        }
    }
}

/// Download status for a model
enum ModelDownloadStatus: Equatable, Sendable {
    case notDownloaded
    case downloading(progress: Double)
    case downloaded
    case error(String)
}

/// Manages downloading and loading MLX models locally.
actor MLXModelManager {
    static let shared = MLXModelManager()

    /// Known models that Zeit supports
    static let visionModel = MLXModelInfo(
        configName: "qwen3-vl:4b",
        huggingFaceID: "mlx-community/Qwen3-VL-4B-Instruct-4bit",
        displayName: "Qwen3-VL 4B (Vision)",
        isVision: true,
        approximateSizeGB: 2.5
    )

    static let textModel = MLXModelInfo(
        configName: "qwen3:8b",
        huggingFaceID: "mlx-community/Qwen3-8B-4bit",
        displayName: "Qwen3 8B (Text)",
        isVision: false,
        approximateSizeGB: 5.0
    )

    static let supportedModels: [MLXModelInfo] = [visionModel, textModel]

    /// Cached model containers for reuse
    private var loadedModels: [String: ModelContainer] = [:]

    // MARK: - Model Status

    /// The default HubApi download location: ~/Documents/huggingface/models/{repo-id}
    private static var hubCacheBase: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("huggingface")
            .appendingPathComponent("models")
    }

    /// Check if a model's weights are already cached locally.
    /// Checks the HubApi default cache directory for .safetensors files.
    func isModelDownloaded(model: MLXModelInfo) -> Bool {
        let cacheDir = Self.hubCacheBase.appendingPathComponent(model.huggingFaceID)
        let fm = FileManager.default

        // Check for the presence of safetensors files as a sign of complete download
        guard fm.fileExists(atPath: cacheDir.path) else { return false }

        let contents = (try? fm.contentsOfDirectory(atPath: cacheDir.path)) ?? []
        return contents.contains { $0.hasSuffix(".safetensors") }
    }

    /// Get the download status for a specific model
    func downloadStatus(for model: MLXModelInfo) -> ModelDownloadStatus {
        if isModelDownloaded(model: model) {
            return .downloaded
        }
        return .notDownloaded
    }

    // MARK: - Download

    /// Download a model's files from Hugging Face without loading into memory.
    /// Uses HubApi.snapshot() to fetch weights to disk only.
    func downloadModel(
        _ model: MLXModelInfo,
        progressHandler: @Sendable @escaping (Double) -> Void
    ) async throws {
        logger.info("Starting download: \(model.huggingFaceID)")

        let hub = HubApi()
        let repo = Hub.Repo(id: model.huggingFaceID)

        try await hub.snapshot(
            from: repo,
            matching: ["*.safetensors", "*.json"],
            progressHandler: { progress in
                let fraction = progress.fractionCompleted
                progressHandler(fraction)
                logger.debug("Download progress for \(model.huggingFaceID): \(fraction * 100)%")
            }
        )

        logger.info("Download complete: \(model.huggingFaceID)")
    }

    // MARK: - Loading

    /// Load or retrieve a cached model container for inference
    func loadModel(_ model: MLXModelInfo) async throws -> ModelContainer {
        if let cached = loadedModels[model.huggingFaceID] {
            return cached
        }

        // Guard: ensure model is downloaded before attempting to load.
        // Without this, loadContainer() silently downloads multi-GB weights
        // AND loads them into Metal memory simultaneously, causing system freezes.
        guard isModelDownloaded(model: model) else {
            throw MLXModelError.modelNotDownloaded(model)
        }

        logger.info("Loading model: \(model.huggingFaceID)")
        let config = ModelConfiguration(id: model.huggingFaceID)

        let container: ModelContainer
        if model.isVision {
            container = try await VLMModelFactory.shared.loadContainer(configuration: config)
        } else {
            container = try await LLMModelFactory.shared.loadContainer(configuration: config)
        }

        loadedModels[model.huggingFaceID] = container
        logger.info("Model loaded: \(model.huggingFaceID)")
        return container
    }

    /// Unload a model from memory
    func unloadModel(_ model: MLXModelInfo) {
        loadedModels.removeValue(forKey: model.huggingFaceID)
        logger.info("Model unloaded: \(model.huggingFaceID)")
    }

    /// Unload all models from memory
    func unloadAll() {
        loadedModels.removeAll()
        logger.info("All models unloaded")
    }

    // MARK: - Lookup

    /// Find the MLXModelInfo for a given config name (e.g. "qwen3-vl:4b")
    static func modelInfo(forConfigName name: String) -> MLXModelInfo? {
        supportedModels.first { $0.configName == name }
    }

    /// Check if all required models are downloaded
    func allModelsDownloaded() -> Bool {
        Self.supportedModels.allSatisfy { isModelDownloaded(model: $0) }
    }
}
