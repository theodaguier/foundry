import CoreGraphics
import CoreML
import Foundation
import ImageIO
@preconcurrency import StableDiffusion
import UniformTypeIdentifiers

enum PluginLogoProgress: Equatable {
    case preparing(String)
    case generating(String)
    case writing(String)

    var message: String {
        switch self {
        case .preparing(let message), .generating(let message), .writing(let message):
            message
        }
    }
}

enum PluginLogoError: LocalizedError {
    case modelDownloadFailed(String)
    case invalidModelResources
    case generationTimedOut
    case noImageGenerated
    case invalidOutputImage
    case outputWriteFailed(String)
    case extractionFailed(String)
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelDownloadFailed(let message):
            "Couldn't download the image model. \(message)"
        case .invalidModelResources:
            "The downloaded image model is incomplete."
        case .generationTimedOut:
            "Logo generation timed out."
        case .noImageGenerated:
            "No logo image was produced."
        case .invalidOutputImage:
            "The generated logo image was invalid."
        case .outputWriteFailed(let message):
            "Couldn't save the generated logo. \(message)"
        case .extractionFailed(let message):
            "Couldn't prepare the image model. \(message)"
        case .generationFailed(let message):
            "Couldn't generate the logo. \(message)"
        }
    }
}

enum PluginLogoService {

    static let outputSize = 512

    private static let modelArchiveURL = URL(string: "https://huggingface.co/apple/coreml-stable-diffusion-2-1-base-palettized/resolve/main/coreml-stable-diffusion-2-1-base-palettized_original_compiled.zip")!
    private static let modelArchiveName = "coreml-stable-diffusion-2-1-base-palettized_original_compiled.zip"
    private static let modelDirectoryName = "coreml-stable-diffusion-2-1-base-palettized"

    private static var modelBaseDirectory: URL {
        FoundryPaths.imageModelsDirectory.appendingPathComponent(modelDirectoryName, isDirectory: true)
    }

    private static var modelResourcesDirectory: URL {
        modelBaseDirectory.appendingPathComponent("original_compiled", isDirectory: true)
    }

    static func prepareModelIfNeeded(
        onProgress: @escaping @Sendable (PluginLogoProgress) -> Void = { _ in }
    ) async throws -> URL {
        if resourcesAreValid(at: modelResourcesDirectory) {
            return modelResourcesDirectory
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: modelBaseDirectory, withIntermediateDirectories: true)

        let stagingDirectory = modelBaseDirectory.appendingPathComponent("staging-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: stagingDirectory) }

        onProgress(.preparing("Downloading image model…"))

        var request = URLRequest(url: modelArchiveURL)
        request.timeoutInterval = 900

        let temporaryArchiveURL: URL
        do {
            let (downloadURL, response) = try await URLSession.shared.download(for: request)
            guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
                throw PluginLogoError.modelDownloadFailed("The server returned an unexpected response.")
            }

            temporaryArchiveURL = stagingDirectory.appendingPathComponent(modelArchiveName)
            try fileManager.moveItem(at: downloadURL, to: temporaryArchiveURL)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as PluginLogoError {
            throw error
        } catch {
            throw PluginLogoError.modelDownloadFailed(error.localizedDescription)
        }

        onProgress(.preparing("Preparing image model…"))

        do {
            try runProcess(
                executablePath: "/usr/bin/ditto",
                arguments: ["-x", "-k", temporaryArchiveURL.path, stagingDirectory.path]
            )
        } catch let error as PluginLogoError {
            throw error
        } catch {
            throw PluginLogoError.extractionFailed(error.localizedDescription)
        }

        guard let extractedDirectory = findExtractedResourceDirectory(in: stagingDirectory) else {
            throw PluginLogoError.invalidModelResources
        }

        let replacementDirectory = modelBaseDirectory.appendingPathComponent("original_compiled-\(UUID().uuidString)", isDirectory: true)
        do {
            if fileManager.fileExists(atPath: replacementDirectory.path) {
                try fileManager.removeItem(at: replacementDirectory)
            }
            try fileManager.moveItem(at: extractedDirectory, to: replacementDirectory)
            if fileManager.fileExists(atPath: modelResourcesDirectory.path) {
                try fileManager.removeItem(at: modelResourcesDirectory)
            }
            try fileManager.moveItem(at: replacementDirectory, to: modelResourcesDirectory)
        } catch {
            throw PluginLogoError.extractionFailed(error.localizedDescription)
        }

        guard resourcesAreValid(at: modelResourcesDirectory) else {
            throw PluginLogoError.invalidModelResources
        }

        return modelResourcesDirectory
    }

    static func generateLogo(
        for plugin: Plugin,
        onProgress: @escaping @Sendable (PluginLogoProgress) -> Void = { _ in }
    ) async throws -> Plugin {
        let resourcesURL = try await prepareModelIfNeeded(onProgress: onProgress)
        try Task.checkCancellation()

        let timeoutState = TimeoutState()
        let generationTask = Task.detached(priority: .userInitiated) {
            try generateLogoImage(for: plugin, resourcesURL: resourcesURL, onProgress: onProgress)
        }
        let timeoutTask = Task.detached {
            try await Task.sleep(nanoseconds: 90 * NSEC_PER_SEC)
            timeoutState.markTimedOut()
            generationTask.cancel()
        }

        defer { timeoutTask.cancel() }

        do {
            let logoFileURL = try await generationTask.value
            var updatedPlugin = plugin
            updatedPlugin.logoAssetPath = logoFileURL.path
            return updatedPlugin
        } catch is CancellationError {
            if timeoutState.didTimeout {
                throw PluginLogoError.generationTimedOut
            }
            throw CancellationError()
        } catch let error as PluginLogoError {
            throw error
        } catch {
            throw PluginLogoError.generationFailed(error.localizedDescription)
        }
    }

    private static func generateLogoImage(
        for plugin: Plugin,
        resourcesURL: URL,
        onProgress: @escaping @Sendable (PluginLogoProgress) -> Void
    ) throws -> URL {
        try Task.checkCancellation()

        let modelConfiguration = MLModelConfiguration()
        modelConfiguration.computeUnits = .cpuAndGPU

        onProgress(.generating("Loading image model…"))

        let pipeline = try StableDiffusionPipeline(
            resourcesAt: resourcesURL,
            controlNet: [],
            configuration: modelConfiguration,
            disableSafety: true,
            reduceMemory: true
        )
        try pipeline.loadResources()
        defer { pipeline.unloadResources() }

        try Task.checkCancellation()

        var configuration = StableDiffusionPipeline.Configuration(prompt: positivePrompt(for: plugin))
        configuration.negativePrompt = negativePrompt
        configuration.imageCount = 1
        configuration.stepCount = 20
        configuration.seed = seed(for: plugin)
        configuration.guidanceScale = 8
        configuration.schedulerType = .dpmSolverMultistepScheduler

        let images = try pipeline.generateImages(configuration: configuration) { progress in
            onProgress(.generating("Generating logo… \(min(progress.step + 1, progress.stepCount))/\(progress.stepCount)"))
            return !Task.isCancelled
        }

        try Task.checkCancellation()

        guard let image = images.first ?? nil else {
            throw PluginLogoError.noImageGenerated
        }
        guard image.width == outputSize, image.height == outputSize else {
            throw PluginLogoError.invalidOutputImage
        }

        onProgress(.writing("Saving generated logo…"))
        return try writeLogoImage(image, for: plugin)
    }

    private static func writeLogoImage(_ image: CGImage, for plugin: Plugin) throws -> URL {
        let fileManager = FileManager.default
        let logoDirectory = FoundryPaths.pluginLogoDirectory(for: plugin.id)
        let finalURL = FoundryPaths.pluginLogoFile(for: plugin.id)
        let temporaryURL = logoDirectory.appendingPathComponent("logo-\(UUID().uuidString).tmp.png")

        do {
            try fileManager.createDirectory(at: logoDirectory, withIntermediateDirectories: true)
            try savePNG(image, to: temporaryURL)

            if fileManager.fileExists(atPath: finalURL.path) {
                try fileManager.removeItem(at: finalURL)
            }
            try fileManager.moveItem(at: temporaryURL, to: finalURL)
            return finalURL
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw PluginLogoError.outputWriteFailed(error.localizedDescription)
        }
    }

    private static func savePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw PluginLogoError.outputWriteFailed("Could not create a PNG destination.")
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw PluginLogoError.outputWriteFailed("PNG encoding failed.")
        }
    }

    private static func positivePrompt(for plugin: Plugin) -> String {
        let inspiration = plugin.prompt
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        let typeLanguage: String = switch plugin.type {
        case .instrument:
            "bright, expressive, energetic, musical glow"
        case .effect:
            "transformative, textured, tense, cinematic signal shaping"
        case .utility:
            "precise, technical, restrained, analytical clarity"
        }

        return """
        premium app icon logo for an audio plugin named \(plugin.name), abstract centered brand mark, single dominant symbol, clean geometric composition, high contrast, dark refined background, minimal, polished, iconic, \(typeLanguage), inspired by: \(inspiration), no text, no letters
        """
    }

    private static let negativePrompt = """
    text, letters, words, typography, photo, photorealistic, human, face, clutter, multiple subjects, complex scene, watermark, blurry, low contrast, UI screenshot, realistic object scene
    """

    private static func seed(for plugin: Plugin) -> UInt32 {
        let baseSeed = withUnsafeBytes(of: plugin.id.uuid) { bytes in
            bytes.reduce(UInt32(2166136261)) { partialResult, byte in
                (partialResult ^ UInt32(byte)) &* 16777619
            }
        }
        return baseSeed ^ UInt32.random(in: 1...UInt32.max)
    }

    private static func resourcesAreValid(at resourceDirectory: URL) -> Bool {
        let fileManager = FileManager.default
        let requiredNames = [
            "TextEncoder.mlmodelc",
            "Unet.mlmodelc",
            "VAEDecoder.mlmodelc",
            "vocab.json",
            "merges.txt",
        ]

        return requiredNames.allSatisfy { name in
            fileManager.fileExists(atPath: resourceDirectory.appendingPathComponent(name).path)
        }
    }

    private static func findExtractedResourceDirectory(in directory: URL) -> URL? {
        (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ))?.first(where: { url in
            url.lastPathComponent.hasSuffix("_compiled")
        })
    }

    private static func runProcess(executablePath: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw PluginLogoError.extractionFailed(error.localizedDescription)
        }

        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw PluginLogoError.extractionFailed(message ?? "The archive could not be extracted.")
        }
    }
}

private final class TimeoutState: @unchecked Sendable {
    private let lock = NSLock()
    private var timedOut = false

    func markTimedOut() {
        lock.withLock {
            timedOut = true
        }
    }

    var didTimeout: Bool {
        lock.withLock { timedOut }
    }
}

private extension NSLock {
    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
