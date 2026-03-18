import Foundation

enum BuildRunner {

    struct BuildResult: Sendable {
        var success: Bool
        var output: String
        var errors: String
    }

    // MARK: - Build

    static func build(projectDir: URL, skipConfigure: Bool = false, timeoutSeconds: Int = 360) async throws -> BuildResult {
        // 1. Configure with CMake (skip on retries — CMakeLists.txt is never modified)
        if !skipConfigure {
            let configResult = await runProcess(
                "/usr/bin/env", args: ["cmake", "-B", "build",
                                        "-DCMAKE_BUILD_TYPE=Release",
                                        "-DCMAKE_OSX_ARCHITECTURES=x86_64;arm64"],
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
        }

        // 2. Build with cmake (parallel for faster compilation)
        let buildResult = await runProcess(
            "/usr/bin/env", args: ["cmake", "--build", "build", "--config", "Release", "--parallel"],
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
        let buildDir = projectDir.appendingPathComponent("build")
        guard FileManager.default.fileExists(atPath: buildDir.path) else { return false }
        return PluginBundleInspector.locateBestBundle(in: buildDir, format: .au) != nil
            || PluginBundleInspector.locateBestBundle(in: buildDir, format: .vst3) != nil
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

    // MARK: - Process runner

    struct ProcessResult: Sendable {
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
