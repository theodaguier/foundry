import Foundation

enum PluginBundleInspector {

    enum BundleFormat: String {
        case au = "component"
        case vst3 = "vst3"

        var requiredArchitectures: Set<String> {
            ["arm64", "x86_64"]
        }
    }

    struct BundleDetails {
        let bundleURL: URL
        let executableURL: URL
        let architectures: Set<String>
        let binarySize: Int64
    }

    enum ValidationError: LocalizedError {
        case bundleNotFound(BundleFormat)
        case invalidBundleStructure(String)
        case missingArchitectures(path: String, expected: [String], actual: [String])
        case codeSignatureFailed(String)
        case audioUnitValidationFailed(String)

        var errorDescription: String? {
            switch self {
            case .bundleNotFound(let format):
                return "No valid \(format.rawValue.uppercased()) bundle was found in the build output."
            case .invalidBundleStructure(let message):
                return message
            case .missingArchitectures(let path, let expected, let actual):
                let expectedList = expected.joined(separator: ", ")
                let actualList = actual.joined(separator: ", ")
                return "The plugin binary at \(path) is missing required architectures. Expected \(expectedList), found \(actualList)."
            case .codeSignatureFailed(let message):
                return "Code signing verification failed: \(message)"
            case .audioUnitValidationFailed(let message):
                return "Audio Unit validation failed: \(message)"
            }
        }
    }

    static func locateBestBundle(in rootDir: URL, format: BundleFormat) -> BundleDetails? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: rootDir,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        let candidates = enumerator.compactMap { element -> BundleDetails? in
            guard let url = element as? URL, url.pathExtension == format.rawValue else {
                return nil
            }
            return inspectBundle(at: url, format: format)
        }

        return candidates.max { lhs, rhs in
            compare(lhs, rhs) == .orderedAscending
        }
    }

    static func inspectBundle(at bundleURL: URL, format: BundleFormat) -> BundleDetails? {
        guard bundleURL.pathExtension == format.rawValue else { return nil }
        guard let metadata = bundleMetadata(at: bundleURL),
              let executableName = metadata["CFBundleExecutable"] as? String,
              !executableName.isEmpty else {
            return nil
        }

        let executableURL = bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("MacOS")
            .appendingPathComponent(executableName)

        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            return nil
        }

        let architectures = executableArchitectures(at: executableURL)
        let binarySize = executableSize(at: executableURL)

        return BundleDetails(
            bundleURL: bundleURL,
            executableURL: executableURL,
            architectures: architectures,
            binarySize: binarySize
        )
    }

    static func validateInstalledBundle(at bundleURL: URL, format: BundleFormat) throws {
        guard let details = inspectBundle(at: bundleURL, format: format) else {
            throw ValidationError.invalidBundleStructure(
                "The installed \(format.rawValue.uppercased()) bundle at \(bundleURL.path) is missing its executable or has an invalid structure."
            )
        }

        let expectedArchitectures = format.requiredArchitectures
        if !expectedArchitectures.isSubset(of: details.architectures) {
            throw ValidationError.missingArchitectures(
                path: details.executableURL.path,
                expected: expectedArchitectures.sorted(),
                actual: details.architectures.sorted()
            )
        }

        let signatureResult = runProcess(
            "/usr/bin/codesign",
            arguments: ["--verify", "--deep", "--strict", bundleURL.path]
        )
        guard signatureResult.exitCode == 0 else {
            let message = signatureResult.stderr.isEmpty ? signatureResult.stdout : signatureResult.stderr
            throw ValidationError.codeSignatureFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        if format == .au {
            try validateAudioUnit(at: bundleURL)
        }
    }

    static func bundleLooksUsable(at bundleURL: URL, format: BundleFormat) -> Bool {
        guard let details = inspectBundle(at: bundleURL, format: format) else {
            return false
        }
        return format.requiredArchitectures.isSubset(of: details.architectures)
    }

    private static func validateAudioUnit(at bundleURL: URL) throws {
        guard let metadata = bundleMetadata(at: bundleURL),
              let components = metadata["AudioComponents"] as? [[String: Any]],
              let component = components.first,
              let type = component["type"] as? String,
              let subtype = component["subtype"] as? String,
              let manufacturer = component["manufacturer"] as? String else {
            throw ValidationError.invalidBundleStructure(
                "The installed Audio Unit at \(bundleURL.path) is missing AudioComponents metadata in Info.plist."
            )
        }

        var lastMessage = ""

        for attempt in 1...3 {
            let result = runProcess(
                "/usr/bin/auvaltool",
                arguments: ["-v", type, subtype, manufacturer]
            )
            if result.exitCode == 0 {
                return
            }

            lastMessage = [result.stdout, result.stderr]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard attempt < 3, isTransientAudioUnitLookupFailure(lastMessage) else {
                throw ValidationError.audioUnitValidationFailed(lastMessage)
            }

            _ = runProcess("/usr/bin/killall", arguments: ["AudioComponentRegistrar"])
            Thread.sleep(forTimeInterval: Double(attempt) * 1.5)
        }

        throw ValidationError.audioUnitValidationFailed(lastMessage)
    }

    private static func compare(_ lhs: BundleDetails, _ rhs: BundleDetails) -> ComparisonResult {
        let lhsScore = score(for: lhs)
        let rhsScore = score(for: rhs)
        if lhsScore != rhsScore {
            return lhsScore < rhsScore ? .orderedAscending : .orderedDescending
        }

        if lhs.binarySize != rhs.binarySize {
            return lhs.binarySize < rhs.binarySize ? .orderedAscending : .orderedDescending
        }

        return lhs.bundleURL.path < rhs.bundleURL.path ? .orderedAscending : .orderedDescending
    }

    private static func score(for details: BundleDetails) -> Int {
        var score = 0
        let path = details.bundleURL.path

        if path.contains("/Debug/") {
            score += 100
        } else if path.contains("/Release/") {
            score += 60
        }

        let requiredArchitectures = BundleFormat(rawValue: details.bundleURL.pathExtension)?.requiredArchitectures ?? []
        if requiredArchitectures.isSubset(of: details.architectures) {
            score += 40
        }

        if details.binarySize > 0 {
            score += min(Int(details.binarySize / 1_000_000), 20)
        }

        return score
    }

    private static func bundleMetadata(at bundleURL: URL) -> [String: Any]? {
        let plistURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }

    private static func executableArchitectures(at executableURL: URL) -> Set<String> {
        let result = runProcess("/usr/bin/lipo", arguments: ["-archs", executableURL.path])
        guard result.exitCode == 0 else { return [] }

        let output = [result.stdout, result.stderr]
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let recognizedArchitectures: Set<String> = [
            "arm64",
            "x86_64",
            "arm64e",
        ]

        return Set(
            output
                .split(whereSeparator: \.isWhitespace)
                .map(String.init)
                .filter { recognizedArchitectures.contains($0) }
        )
    }

    private static func executableSize(at executableURL: URL) -> Int64 {
        let values = try? executableURL.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    private static func isTransientAudioUnitLookupFailure(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return normalized.contains("cannot get component's name strings")
            || normalized.contains("error from retrieving component version: -50")
            || normalized.contains("fatal error: didn't find the component")
    }

    private static func runProcess(_ executable: String, arguments: [String]) -> (exitCode: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = DependencyChecker.shellEnvironment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (-1, "", error.localizedDescription)
        }

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, stdout, stderr)
    }
}
