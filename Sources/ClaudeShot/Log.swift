import Foundation
import os

enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.duncansmith.claudeshot"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let capture = Logger(subsystem: subsystem, category: "capture")
    static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
    static let paste = Logger(subsystem: subsystem, category: "paste")
}
