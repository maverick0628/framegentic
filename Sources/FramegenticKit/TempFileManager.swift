import Foundation

// Owns one capture session's on-disk files. Isolated to the actor that drives
// capture: the original DispatchSourceTimer-based cleanup ran its handler on a
// background queue while writes land wherever the caller runs, an unsynchronized
// mutation of writtenURLs/sessionDir. Confining the type to MainActor and doing
// the delay with a Task (instead of a background-queue timer) removes the race
// instead of papering over it with a lock.
@MainActor
public final class TempFileManager {
    private let baseDir: URL
    private let sessionID: UUID
    private var sessionDir: URL
    private var cleanupTask: Task<Void, Never>?
    private var writtenURLs: [URL] = []

    public init() {
        self.baseDir = FileManager.default.temporaryDirectory.appendingPathComponent("framesnap")
        self.sessionID = UUID()
        self.sessionDir = baseDir.appendingPathComponent(sessionID.uuidString)
    }

    public func write(_ data: Data, filename: String) throws -> URL {
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        let fileURL = sessionDir.appendingPathComponent(filename)
        try data.write(to: fileURL)
        writtenURLs.append(fileURL)
        return fileURL
    }

    public func scheduleCleanup(after seconds: TimeInterval) {
        cleanupTask?.cancel()
        cleanupTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.cleanupAll()
        }
    }

    public func cleanupAll() {
        cleanupTask?.cancel()
        cleanupTask = nil
        try? FileManager.default.removeItem(at: sessionDir)
        writtenURLs.removeAll()
        sessionDir = baseDir.appendingPathComponent(UUID().uuidString)
    }

    public func currentSessionURLs() -> [URL] {
        writtenURLs
    }

    deinit {
        // deinit runs nonisolated (dealloc can be triggered from any thread), but
        // direct stored-property access is safe here: nothing else can hold a
        // reference to touch these concurrently once we're deinitializing.
        cleanupTask?.cancel()
        try? FileManager.default.removeItem(at: sessionDir)
    }
}
