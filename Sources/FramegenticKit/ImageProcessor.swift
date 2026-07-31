import CoreGraphics
import ImageIO
import Foundation
import Accelerate

public enum ImageProcessor {
    public static func downsample(_ image: CGImage, maxWidth: Int) -> CGImage {
        guard image.width > maxWidth else { return image }

        let scale = CGFloat(maxWidth) / CGFloat(image.width)
        let newWidth = maxWidth
        let newHeight = Int(CGFloat(image.height) * scale)

        var format = vImage_CGImageFormat(
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            colorSpace: nil,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            version: 0,
            decode: nil,
            renderingIntent: .defaultIntent
        )

        var sourceBuffer = vImage_Buffer()
        vImageBuffer_InitWithCGImage(&sourceBuffer, &format, nil, image, vImage_Flags(kvImageNoFlags))

        var destBuffer = vImage_Buffer()
        vImageBuffer_Init(&destBuffer, vImagePixelCount(newHeight), vImagePixelCount(newWidth), 32, vImage_Flags(kvImageNoFlags))

        vImageScale_ARGB8888(&sourceBuffer, &destBuffer, nil, vImage_Flags(kvImageHighQualityResampling))

        defer {
            free(sourceBuffer.data)
            free(destBuffer.data)
        }

        // vImage only fails here on an allocation/format error; the source image
        // is still valid, so fall back to it rather than crash.
        guard let downsampled = vImageCreateCGImageFromBuffer(
            &destBuffer, &format, nil, nil, vImage_Flags(kvImageNoFlags), nil
        )?.takeRetainedValue() else {
            return image
        }

        return downsampled
    }

    public static func encodeJPEG(_ image: CGImage, quality: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
