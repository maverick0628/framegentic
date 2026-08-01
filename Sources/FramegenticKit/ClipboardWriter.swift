import AppKit

public enum ClipboardWriter {
    /// Returns the change count the write left behind, so a caller that means
    /// to expire this entry later can tell it from someone else's — or `nil`
    /// if the pasteboard refused the write.
    ///
    /// Not `@discardableResult`. Discarding it was how a refused write came
    /// back as "6 frames copied": `clearContents()` had already happened, so
    /// the clipboard held nothing at all while the toast said otherwise.
    public static func writeFileURLs(_ urls: [URL]) -> Int? {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.writeObjects(urls as [NSURL]) else { return nil }
        return pasteboard.changeCount
    }
}
