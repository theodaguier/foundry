import Foundation

enum BuildDirectoryCleaner {

    private static let prefix = "foundry-build-"
    private static let tmpDirectory = URL(fileURLWithPath: "/tmp")
    private static let staleThreshold: TimeInterval = 86_400 // 24 hours

    /// Remove a specific build directory after a short grace period.
    static func cleanAfterInstall(_ directory: URL) {
        Task.detached(priority: .background) {
            try? await Task.sleep(for: .seconds(10))
            try? FileManager.default.removeItem(at: directory)
        }
    }

    /// Remove any `/tmp/foundry-build-*` directories older than 24 hours.
    static func sweepStaleDirectories() {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: tmpDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else { return }

        let cutoff = Date().addingTimeInterval(-staleThreshold)

        for dir in contents where dir.lastPathComponent.hasPrefix(prefix) {
            let created = (try? dir.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            if created < cutoff {
                try? fm.removeItem(at: dir)
            }
        }
    }
}
