import CoreGraphics

public enum DHash {
    public static func hash(_ image: CGImage) -> UInt64 {
        let width = 9
        let height = 8
        let bytesPerRow = width
        var grayPixels = [UInt8](repeating: 0, count: width * height)

        guard let context = CGContext(
            data: &grayPixels, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return 0 }

        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var hash: UInt64 = 0
        for row in 0..<height {
            for col in 0..<(width - 1) {
                let leftPixel = grayPixels[row * width + col]
                let rightPixel = grayPixels[row * width + col + 1]
                hash <<= 1
                if leftPixel > rightPixel {
                    hash |= 1
                }
            }
        }
        return hash
    }

    public static func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }

    public static func areSimilar(_ a: UInt64, _ b: UInt64, threshold: Double = 0.9) -> Bool {
        let distance = hammingDistance(a, b)
        let similarity = 1.0 - (Double(distance) / 64.0)
        return similarity >= threshold
    }
}
