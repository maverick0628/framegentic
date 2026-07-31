public enum PasteBlockReason: Equatable, Sendable {
    case accessibilityDenied
    case wrongFrontmostApp(actual: String?)
}

public enum KeystrokeDecision: Equatable, Sendable {
    case allowed
    case blocked(PasteBlockReason)
}

public enum PasteGuard {
    public static func evaluate(frontmostBundleID: String?,
                                expectedBundleID: String,
                                axTrusted: Bool) -> KeystrokeDecision {
        guard axTrusted else {
            return .blocked(.accessibilityDenied)
        }
        guard frontmostBundleID == expectedBundleID else {
            return .blocked(.wrongFrontmostApp(actual: frontmostBundleID))
        }
        return .allowed
    }
}
