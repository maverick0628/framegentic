import CoreGraphics

public struct CaptureGeometry: Equatable, Sendable {
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let logicalSize: CGSize

    public init(pointWidth: Int, pointHeight: Int, scaleFactor: CGFloat) {
        pixelWidth = Int((CGFloat(pointWidth) * scaleFactor).rounded())
        pixelHeight = Int((CGFloat(pointHeight) * scaleFactor).rounded())
        logicalSize = CGSize(width: pointWidth, height: pointHeight)
    }
}
