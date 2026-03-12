import Foundation

enum DependencyChecker {

    enum Dependency: String, CaseIterable {
        case xcodeTools = "Xcode CLI Tools"
        case cmake = "CMake"
        case juce = "JUCE SDK"
        case claudeCode = "Claude Code CLI"

        var detail: String {
            switch self {
            case .xcodeTools: "Compiler toolchain"
            case .cmake: "Build system"
            case .juce: "Audio framework (~200 MB)"
            case .claudeCode: "npm i -g @anthropic-ai/claude-code"
            }
        }
    }

    static func check(_ dependency: Dependency) async -> Bool {
        switch dependency {
        case .xcodeTools:
            return await runShell("xcode-select -p")
        case .cmake:
            return await runShell("cmake --version")
        case .juce:
            return FileManager.default.fileExists(atPath: jucePath)
        case .claudeCode:
            return await runShell("claude --version")
        }
    }

    static var jucePath: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Foundry/JUCE").path
    }

    // MARK: - Shell environment

    /// Resolved full PATH from the user's login shell. Cached after first call.
    /// A macOS .app doesn't inherit the user's shell PATH, so we must resolve it ourselves.
    static var shellEnvironment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = resolvedPATH
        env.removeValue(forKey: "CLAUDECODE")
        return env
    }

    /// Cached resolved PATH from user's login shell
    private static let resolvedPATH: String = {
        // Ask the user's default shell for its PATH
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        // -l = login shell, -i = interactive (loads .zshrc/.bashrc), -c = run command
        process.arguments = ["-l", "-c", "echo $PATH"]
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
                return path
            }
        } catch {}

        // Fallback: common paths
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(home)/.local/bin",
            "\(home)/.bun/bin",
            "\(home)/.npm-global/bin",
            "\(home)/.cargo/bin",
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ].joined(separator: ":")
    }()

    // MARK: - Shell execution

    /// Run a command through the user's login shell (inherits full PATH)
    private static func runShell(_ command: String) async -> Bool {
        await withCheckedContinuation { continuation in
            let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: shell)
            process.arguments = ["-l", "-c", command]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
                continuation.resume(returning: process.terminationStatus == 0)
            } catch {
                continuation.resume(returning: false)
            }
        }
    }

    // MARK: - JUCE download

    private static let juceVersion = "8.0.6"
    private static var juceDownloadURL: URL {
        URL(string: "https://github.com/juce-framework/JUCE/archive/refs/tags/\(juceVersion).zip")!
    }

    static func installJUCE(onProgress: @escaping @Sendable (Double) -> Void) async throws {
        let fm = FileManager.default
        let destDir = URL(fileURLWithPath: jucePath)
        let parentDir = destDir.deletingLastPathComponent()

        try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)

        let tempZip = parentDir.appendingPathComponent("juce-download.zip")
        defer { try? fm.removeItem(at: tempZip) }

        let (downloadURL, _) = try await downloadWithProgress(juceDownloadURL, to: tempZip, onProgress: onProgress)

        onProgress(-1)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-xk", downloadURL.path, parentDir.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw NSError(domain: "Foundry", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to extract JUCE archive"])
        }

        let extracted = parentDir.appendingPathComponent("JUCE-\(juceVersion)")
        if fm.fileExists(atPath: extracted.path) {
            try? fm.removeItem(at: destDir)
            try fm.moveItem(at: extracted, to: destDir)
        }
    }

    private static func downloadWithProgress(
        _ url: URL,
        to destination: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> (URL, URLResponse) {
        let delegate = DownloadProgressDelegate(onProgress: onProgress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let (tempURL, response) = try await session.download(from: url)
        try FileManager.default.moveItem(at: tempURL, to: destination)
        session.invalidateAndCancel()
        return (destination, response)
    }
}

// MARK: - Download delegate

private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let onProgress: (Double) -> Void

    init(onProgress: @escaping (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        if totalBytesExpectedToWrite > 0 {
            onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
        }
    }
}
