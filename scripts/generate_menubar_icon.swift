#!/usr/bin/env swift
import Cocoa

func makeIcon(px: Int, outPath: String) {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!

    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let g = ctx.cgContext

    let s = CGFloat(px)
    let black = CGColor(red: 0, green: 0, blue: 0, alpha: 1.0)
    g.setStrokeColor(black)
    g.setFillColor(black)
    g.setLineCap(.round)

    let lw = s * 0.09
    g.setLineWidth(lw)

    let cx = s / 2, cy = s / 2
    let boxHalf = s * 0.34
    let cornerLen = s * 0.18

    g.move(to: CGPoint(x: cx - boxHalf, y: cy + boxHalf - cornerLen))
    g.addLine(to: CGPoint(x: cx - boxHalf, y: cy + boxHalf))
    g.addLine(to: CGPoint(x: cx - boxHalf + cornerLen, y: cy + boxHalf))
    g.strokePath()

    g.move(to: CGPoint(x: cx + boxHalf - cornerLen, y: cy + boxHalf))
    g.addLine(to: CGPoint(x: cx + boxHalf, y: cy + boxHalf))
    g.addLine(to: CGPoint(x: cx + boxHalf, y: cy + boxHalf - cornerLen))
    g.strokePath()

    g.move(to: CGPoint(x: cx + boxHalf, y: cy - boxHalf + cornerLen))
    g.addLine(to: CGPoint(x: cx + boxHalf, y: cy - boxHalf))
    g.addLine(to: CGPoint(x: cx + boxHalf - cornerLen, y: cy - boxHalf))
    g.strokePath()

    g.move(to: CGPoint(x: cx - boxHalf + cornerLen, y: cy - boxHalf))
    g.addLine(to: CGPoint(x: cx - boxHalf, y: cy - boxHalf))
    g.addLine(to: CGPoint(x: cx - boxHalf, y: cy - boxHalf + cornerLen))
    g.strokePath()

    let dotR = s * 0.06
    g.fillEllipse(in: CGRect(x: cx - dotR, y: cy - dotR, width: dotR * 2, height: dotR * 2))

    NSGraphicsContext.current = nil

    guard let png = rep.representation(using: .png, properties: [:]) else { return }
    try! png.write(to: URL(fileURLWithPath: outPath))
}

let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp"
makeIcon(px: 18, outPath: "\(dir)/MenuBarIcon.png")
makeIcon(px: 36, outPath: "\(dir)/MenuBarIcon@2x.png")
print("Menu bar icons created (18px + 36px)")
