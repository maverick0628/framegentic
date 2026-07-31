import Foundation

// Owns one capture session's on-disk files. A plain actor, not @MainActor:
// the original DispatchSourceTimer-based cleanup ran its handler on a
// background queue while writes land wherever the caller runs, an
// unsynchronized mutation of writtenURLs/sessionDir. Actor isolation closes
// that race the same way a global actor would — access is serialised either
// way — but this type does JPEG encoding and file I/O, and the capture loop
// (a later task) calls it on every frame at a sub-second interval. Pinning
// that to the main actor would contend with this menu bar app's UI, so a
// plain actor plus a Task (instead of a background-queue timer) for the
// delay removes the race without pinning the work to any particular thread.
public actor TempFileManager {
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
            // Unlike @MainActor, a custom actor isn't a global actor, so this
            // closure doesn't statically inherit its isolation — the compiler
            // requires (and this needs) an explicit await to cross back in.
            await self?.cleanupAll()
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
        // deinit is nonisolated on any actor kind, global or plain (dealloc can
        // be triggered from any thread), but direct stored-property access is
        // safe here: nothing else can hold a reference to touch these
        // concurrently once we're deinitializing.
        cleanupTask?.cancel()
        try? FileManager.default.removeItem(at: sessionDir)
    }
}
