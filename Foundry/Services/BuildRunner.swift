import Foundation

enum BuildRunner {

    struct BuildResult {
        var success: Bool
        var output: String
        var errors: String
    }

    // MARK: - Build

    static func build(projectDir: URL, timeoutSeconds: Int = 360) async throws -> BuildResult {
        // 1. Configure with CMake
        let configResult = await runProcess(
            "/usr/bin/env", args: ["cmake", "-B", "build",
                                    "-DCMAKE_BUILD_TYPE=Release",
                                    "-DCMAKE_OSX_ARCHITECTURES=arm64;x86_64"],
            workingDirectory: projectDir,
            timeout: timeoutSeconds
        )

        guard configResult.exitCode == 0 else {
            return BuildResult(
                success: false,
                output: configResult.stdout,
                errors: "CMake configuration failed:\n\(configResult.stderr)"
            )
        }

        // 2. Build with cmake
        let buildResult = await runProcess(
            "/usr/bin/env", args: ["cmake", "--build", "build", "--config", "Release"],
            workingDirectory: projectDir,
            timeout: timeoutSeconds
        )

        return BuildResult(
            success: buildResult.exitCode == 0,
            output: buildResult.stdout,
            errors: buildResult.exitCode == 0 ? "" : parseErrors(buildResult.stderr + "\n" + buildResult.stdout)
        )
    }

    // MARK: - Smoke test

    static func smokeTest(projectDir: URL) async -> Bool {
        // Check that the built plugin bundles exist and have valid structure
        let fm = FileManager.default
        let buildDir = projectDir.appendingPathComponent("build")

        guard fm.fileExists(atPath: buildDir.path) else { return false }

        // Look for .component or .vst3 bundles
        let hasAU = findBundle(in: buildDir, ext: "component")
        let hasVST3 = findBundle(in: buildDir, ext: "vst3")

        guard hasAU || hasVST3 else { return false }

        // Run auval validation if AU was built (quick check)
        if hasAU {
            let result = await runProcess(
                "/usr/bin/auval", args: ["-a"],
                workingDirectory: projectDir,
                timeout: 30
            )
            // auval -a just lists AU components — if it runs, the AU subsystem is healthy
            return result.exitCode == 0
        }

        return true
    }

    // MARK: - Error parsing

    private static func parseErrors(_ raw: String) -> String {
        let lines = raw.components(separatedBy: .newlines)
        let errorLines = lines.filter { line in
            line.contains("error:") || line.contains("Error:") ||
            line.contains("fatal error") || line.contains("undefined reference") ||
            line.contains("linker command failed")
        }

        if errorLines.isEmpty {
            // Return last 30 lines as context
            return lines.suffix(30).joined(separator: "\n")
        }

        return errorLines.joined(separator: "\n")
    }

    private static func findBundle(in dir: URL, ext: String) -> Bool {
        guard let enumerator = FileManager.default.enumerator(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return false }

        for case let url as URL in enumerator where url.pathExtension == ext {
            return true
        }
        return false
    }

    // MARK: - Process runner

    struct ProcessResult {
        var exitCode: Int32
        var stdout: String
        var stderr: String
    }

    static func runProcess(
        _ executable: String,
        args: [String],
        workingDirectory: URL,
        timeout: Int
    ) async -> ProcessResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = args
                process.currentDirectoryURL = workingDirectory
                process.environment = DependencyChecker.shellEnvironment

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                // Collect output in background threads to avoid pipe buffer deadlock
                let stdoutCollector = DataCollector()
                let stderrCollector = DataCollector()

                stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty else {
                        stdoutPipe.fileHandleForReading.readabilityHandler = nil
                        return
                    }
                    stdoutCollector.append(data)
                }

                stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty else {
                        stderrPipe.fileHandleForReading.readabilityHandler = nil
                        return
                    }
                    stderrCollector.append(data)
                }

                // Timeout
                let timer = DispatchSource.makeTimerSource()
                timer.schedule(deadline: .now() + .seconds(timeout))
                timer.setEventHandler { process.terminate() }
                timer.resume()

                do {
                    try process.run()
                    process.waitUntilExit()
                } catch {
                    timer.cancel()
                    continuation.resume(returning: ProcessResult(exitCode: -1, stdout: "", stderr: error.localizedDescription))
                    return
                }

                timer.cancel()
                Thread.sleep(forTimeInterval: 0.1)
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil

                continuation.resume(returning: ProcessResult(
                    exitCode: process.terminationStatus,
                    stdout: String(data: stdoutCollector.data, encoding: .utf8) ?? "",
                    stderr: String(data: stderrCollector.data, encoding: .utf8) ?? ""
                ))
            }
        }
    }
}

// MARK: - Thread-safe data collector

private final class DataCollector: @unchecked Sendable {
    private var buffer = Data()
    private let lock = NSLock()

    func append(_ newData: Data) {
        lock.lock()
        buffer.append(newData)
        lock.unlock()
    }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }
}
