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
    /// Upstream model release date (ISO-8601 day, e.g. "2025-10-15")
    let releaseDate: String
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

    // MARK: - Vision Models (Qwen3-VL Instruct, 4-bit MLX)

    static let visionModel2B = MLXModelInfo(
        configName: "qwen3-vl:2b",
        huggingFaceID: "mlx-community/Qwen3-VL-2B-Instruct-4bit",
        displayName: "Qwen3-VL 2B (Vision)",
        isVision: true,
        approximateSizeGB: 1.3,
        releaseDate: "2025-10-21"
    )

    static let visionModel4B = MLXModelInfo(
        configName: "qwen3-vl:4b",
        huggingFaceID: "mlx-community/Qwen3-VL-4B-Instruct-4bit",
        displayName: "Qwen3-VL 4B (Vision)",
        isVision: true,
        approximateSizeGB: 2.5,
        releaseDate: "2025-10-15"
    )

    static let visionModel8B = MLXModelInfo(
        configName: "qwen3-vl:8b",
        huggingFaceID: "mlx-community/Qwen3-VL-8B-Instruct-4bit",
        displayName: "Qwen3-VL 8B (Vision)",
        isVision: true,
        approximateSizeGB: 5.0,
        releaseDate: "2025-10-15"
    )

    // MARK: - Vision Models (Gemma 4, 4-bit MLX)

    static let gemma4VisionE4B = MLXModelInfo(
        configName: "gemma4-vl:e4b",
        huggingFaceID: "mlx-community/gemma-4-e4b-it-4bit",
        displayName: "Gemma 4 E4B (Vision)",
        isVision: true,
        approximateSizeGB: 3.5,
        releaseDate: "2026-04-02"
    )

    // MARK: - Text Models (Qwen3, 4-bit MLX)

    static let textModel1_7B = MLXModelInfo(
        configName: "qwen3:1.7b",
        huggingFaceID: "mlx-community/Qwen3-1.7B-4bit",
        displayName: "Qwen3 1.7B (Text)",
        isVision: false,
        approximateSizeGB: 1.0,
        releaseDate: "2025-04-28"
    )

    static let textModel4B = MLXModelInfo(
        configName: "qwen3:4b",
        huggingFaceID: "mlx-community/Qwen3-4B-4bit",
        displayName: "Qwen3 4B (Text)",
        isVision: false,
        approximateSizeGB: 2.5,
        releaseDate: "2025-04-28"
    )

    static let textModel8B = MLXModelInfo(
        configName: "qwen3:8b",
        huggingFaceID: "mlx-community/Qwen3-8B-4bit",
        displayName: "Qwen3 8B (Text)",
        isVision: false,
        approximateSizeGB: 5.0,
        releaseDate: "2025-04-28"
    )

    // MARK: - Defaults & Catalog

    /// Default vision model used when the config is missing or invalid.
    static let visionModel = visionModel4B
    /// Default text model used when the config is missing or invalid.
    static let textModel = textModel8B

    /// Full catalog of models that Zeit can download.
    static let supportedModels: [MLXModelInfo] = [
        visionModel2B, visionModel4B, visionModel8B,
        gemma4VisionE4B,
        textModel1_7B, textModel4B, textModel8B,
    ]

    static var supportedVisionModels: [MLXModelInfo] {
        supportedModels.filter(\.isVision)
    }

    static var supportedTextModels: [MLXModelInfo] {
        supportedModels.filter { !$0.isVision }
    }

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

    /// Delete a model's cached weights from disk and drop it from memory.
    func deleteModel(_ model: MLXModelInfo) throws {
        unloadModel(model)
        let cacheDir = Self.hubCacheBase.appendingPathComponent(model.huggingFaceID)
        if FileManager.default.fileExists(atPath: cacheDir.path) {
            try FileManager.default.removeItem(at: cacheDir)
            logger.info("Deleted model cache: \(model.huggingFaceID)")
        }
    }

    // MARK: - Lookup

    /// Find the MLXModelInfo for a given config name (e.g. "qwen3-vl:4b")
    static func modelInfo(forConfigName name: String) -> MLXModelInfo? {
        supportedModels.first { $0.configName == name }
    }

    /// Check whether the currently-active vision and text models (from `ZeitConfig`)
    /// are downloaded. This is the gate for "is setup complete?".
    func activeModelsDownloaded() -> Bool {
        let config = ZeitConfig.load()
        let visionReady: Bool = {
            guard let info = Self.modelInfo(forConfigName: config.models.vision) else { return false }
            return isModelDownloaded(model: info)
        }()
        // Only require the text model when it's an on-device MLX model.
        let textReady: Bool = {
            guard config.models.text.provider.lowercased() == "mlx" else { return true }
            guard let info = Self.modelInfo(forConfigName: config.models.text.model) else { return false }
            return isModelDownloaded(model: info)
        }()
        return visionReady && textReady
    }
}
