import CoreGraphics

public struct DisplayInfo: Equatable, Sendable {
    public let id: CGDirectDisplayID
    public let pointWidth: Int
    public let pointHeight: Int

    public init(id: CGDirectDisplayID, pointWidth: Int, pointHeight: Int) {
        self.id = id
        self.pointWidth = pointWidth
        self.pointHeight = pointHeight
    }
}

public func selectCaptureDisplay(from displays: [DisplayInfo],
                                 mainDisplayID: CGDirectDisplayID) -> DisplayInfo? {
    displays.first(where: { $0.id == mainDisplayID }) ?? displays.first
}
