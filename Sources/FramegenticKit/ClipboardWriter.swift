import AppKit

public enum ClipboardWriter {
    /// Returns the change count the write left behind, so a caller that means
    /// to expire this entry later can tell it from someone else's.
    @discardableResult
    public static func writeFileURLs(_ urls: [URL]) -> Int {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
        return pasteboard.changeCount
    }
}
