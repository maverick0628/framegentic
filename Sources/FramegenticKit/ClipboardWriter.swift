import AppKit

public enum ClipboardWriter {
    public static func writeFileURLs(_ urls: [URL]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
    }
}
