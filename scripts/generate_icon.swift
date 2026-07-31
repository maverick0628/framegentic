#!/usr/bin/env swift
import Cocoa

let iconSize: CGFloat = 1024
let image = NSImage(size: NSSize(width: iconSize, height: iconSize))
image.lockFocus()

let ctx = NSGraphicsContext.current!.cgContext

// Background - dark rounded rect
let bgRect = CGRect(x: 0, y: 0, width: iconSize, height: iconSize)
let bgPath = CGPath(roundedRect: bgRect, cornerWidth: 228, cornerHeight: 228, transform: nil)
ctx.setFillColor(CGColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1.0))
ctx.addPath(bgPath)
ctx.fillPath()

// Subtle border
ctx.setStrokeColor(CGColor(red: 0.22, green: 0.22, blue: 0.25, alpha: 1.0))
ctx.setLineWidth(4)
let insetRect = bgRect.insetBy(dx: 2, dy: 2)
let borderPath = CGPath(roundedRect: insetRect, cornerWidth: 226, cornerHeight: 226, transform: nil)
ctx.addPath(borderPath)
ctx.strokePath()

// Viewfinder brackets - Framegentic cyan (#4FC9D9)
let accent = CGColor(red: 0.31, green: 0.79, blue: 0.85, alpha: 1.0)
ctx.setStrokeColor(accent)
ctx.setLineCap(.round)
ctx.setLineWidth(48)

let cx: CGFloat = 512
let cy: CGFloat = 512
let boxHalf: CGFloat = 220
let cornerLen: CGFloat = 120

// Top-left corner
ctx.move(to: CGPoint(x: cx - boxHalf, y: cy + boxHalf - cornerLen))
ctx.addLine(to: CGPoint(x: cx - boxHalf, y: cy + boxHalf))
ctx.addLine(to: CGPoint(x: cx - boxHalf + cornerLen, y: cy + boxHalf))
ctx.strokePath()

// Top-right corner
ctx.move(to: CGPoint(x: cx + boxHalf - cornerLen, y: cy + boxHalf))
ctx.addLine(to: CGPoint(x: cx + boxHalf, y: cy + boxHalf))
ctx.addLine(to: CGPoint(x: cx + boxHalf, y: cy + boxHalf - cornerLen))
ctx.strokePath()

// Bottom-right corner
ctx.move(to: CGPoint(x: cx + boxHalf, y: cy - boxHalf + cornerLen))
ctx.addLine(to: CGPoint(x: cx + boxHalf, y: cy - boxHalf))
ctx.addLine(to: CGPoint(x: cx + boxHalf - cornerLen, y: cy - boxHalf))
ctx.strokePath()

// Bottom-left corner
ctx.move(to: CGPoint(x: cx - boxHalf + cornerLen, y: cy - boxHalf))
ctx.addLine(to: CGPoint(x: cx - boxHalf, y: cy - boxHalf))
ctx.addLine(to: CGPoint(x: cx - boxHalf, y: cy - boxHalf + cornerLen))
ctx.strokePath()

// Center dot
ctx.setFillColor(accent)
let dotRadius: CGFloat = 36
ctx.fillEllipse(in: CGRect(x: cx - dotRadius, y: cy - dotRadius, width: dotRadius * 2, height: dotRadius * 2))

image.unlockFocus()

guard let tiffData = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    print("Failed to create PNG")
    exit(1)
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp"
let outPath = "\(outDir)/AppIcon.png"
try! png.write(to: URL(fileURLWithPath: outPath))
print("Icon written to \(outPath)")
