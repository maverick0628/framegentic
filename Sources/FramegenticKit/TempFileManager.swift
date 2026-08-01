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
//
// Files are grouped into batches under the session directory, one per
// scheduleCleanup, because each batch's deadline is a promise made to the
// user about that batch. See scheduleCleanup.
public actor TempFileManager {
    private let sessionDir: URL
    private var batchDir: URL
    private var writtenURLs: [URL] = []
    private var cleanupTasks: [URL: Task<Void, Never>] = [:]

    public init() {
        let sessionDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("framegentic")
            .appendingPathComponent(UUID().uuidString)
        self.sessionDir = sessionDir
        self.batchDir = sessionDir.appendingPathComponent(UUID().uuidString)
    }

    /// Deletes this session's files without hopping onto the actor.
    ///
    /// For app termination, where an `await` is not a promise: the process can
    /// exit before a suspended task is ever resumed, so anything that has to
    /// finish before quitting cannot suspend. Reading `sessionDir` off the
    /// actor is safe because it is immutable. The cost is that the pending
    /// cleanup tasks aren't cancelled and `writtenURLs` isn't cleared, neither
    /// of which outlives the process this is called from.
    public nonisolated func removeSessionDirectory() {
        try? FileManager.default.removeItem(at: sessionDir)
    }

    public func write(_ data: Data, filename: String) throws -> URL {
        try FileManager.default.createDirectory(at: batchDir, withIntermediateDirectories: true)
        let fileURL = batchDir.appendingPathComponent(filename)
        try data.write(to: fileURL)
        writtenURLs.append(fileURL)
        return fileURL
    }

    /// Gives everything written since the last call its own deletion deadline,
    /// then opens a fresh directory for whatever gets written next.
    ///
    /// Per batch, not per manager. A clip is told on screen when it will be
    /// deleted, and capturing a second clip a minute later must not quietly
    /// move the first one's deadline out to match. A single shared directory
    /// could not honour that even with two timers: both clips number their
    /// frames from zero, so the second would overwrite the first's files and
    /// the first's deadline would then delete the second's frames.
    public func scheduleCleanup(after seconds: TimeInterval) {
        let expiring = batchDir
        cleanupTasks[expiring] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            // Unlike @MainActor, a custom actor isn't a global actor, so this
            // closure doesn't statically inherit its isolation — the compiler
            // requires (and this needs) an explicit await to cross back in.
            await self?.removeBatch(expiring)
        }
        batchDir = sessionDir.appendingPathComponent(UUID().uuidString)
    }

    public func cleanupAll() {
        for task in cleanupTasks.values { task.cancel() }
        cleanupTasks.removeAll()
        try? FileManager.default.removeItem(at: sessionDir)
        writtenURLs.removeAll()
        batchDir = sessionDir.appendingPathComponent(UUID().uuidString)
    }

    public func currentSessionURLs() -> [URL] {
        writtenURLs
    }

    private func removeBatch(_ dir: URL) {
        cleanupTasks[dir] = nil
        try? FileManager.default.removeItem(at: dir)
        // Not `== dir`: deletingLastPathComponent() always returns a
        // directory-flagged URL (trailing slash), but batchDir never picked
        // one up — appendingPathComponent(_:) defaults a component to
        // non-directory, and nothing here ever marks it otherwise. The two
        // URLs name the same path and still don't compare equal. .path
        // strings that trailing slash away on both sides.
        writtenURLs.removeAll { $0.deletingLastPathComponent().path == dir.path }
    }

    deinit {
        // deinit is nonisolated on any actor kind, global or plain (dealloc can
        // be triggered from any thread), but direct stored-property access is
        // safe here: nothing else can hold a reference to touch these
        // concurrently once we're deinitializing.
        for task in cleanupTasks.values { task.cancel() }
        try? FileManager.default.removeItem(at: sessionDir)
    }
}
