#!/usr/bin/env swift
// Renders the styled DMG background image as a 600x400 PNG.
// Usage: swift installer/render-background.swift <output.png>

import AppKit

guard CommandLine.arguments.count >= 2 else {
    print("usage: render-background.swift <output.png>")
    exit(2)
}
let outPath = CommandLine.arguments[1]

let width: CGFloat  = 600
let height: CGFloat = 400

let image = NSImage(size: NSSize(width: width, height: height))
image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { exit(1) }

// Brand background gradient: deep blue-black → near-black, matches the
// header.jpg in /assets.
let bgGradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        NSColor(calibratedRed: 0.06, green: 0.07, blue: 0.10, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.02, green: 0.02, blue: 0.04, alpha: 1).cgColor,
    ] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(
    bgGradient,
    start: CGPoint(x: 0, y: height),
    end: CGPoint(x: 0, y: 0),
    options: []
)

// Subtle dot grid (mirrors the assets/header.jpg pattern).
ctx.setFillColor(NSColor.white.withAlphaComponent(0.05).cgColor)
let step: CGFloat = 14
let dotSize: CGFloat = 1.4
var y: CGFloat = 0
while y < height {
    var x: CGFloat = 0
    while x < width {
        ctx.fillEllipse(in: CGRect(
            x: x - dotSize / 2, y: y - dotSize / 2,
            width: dotSize, height: dotSize))
        x += step
    }
    y += step
}

// Footer text: "Drag Snapline to Applications to install"
let footerStyle = NSMutableParagraphStyle()
footerStyle.alignment = .center
let footerAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 13, weight: .regular),
    .foregroundColor: NSColor.white.withAlphaComponent(0.55),
    .paragraphStyle: footerStyle,
]
let footer = NSAttributedString(
    string: "Drag Snapline to Applications to install",
    attributes: footerAttrs
)
footer.draw(in: NSRect(x: 0, y: 26, width: width, height: 20))

// Top brand mark: "Snapline" wordmark + tagline.
let titleStyle = NSMutableParagraphStyle()
titleStyle.alignment = .center
let titleAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
    .foregroundColor: NSColor.white.withAlphaComponent(0.95),
    .paragraphStyle: titleStyle,
]
let title = NSAttributedString(string: "Snapline", attributes: titleAttrs)
title.draw(in: NSRect(x: 0, y: height - 56, width: width, height: 30))

let taglineAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 12, weight: .regular),
    .foregroundColor: NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.30, alpha: 1.0),
    .paragraphStyle: titleStyle,
]
let tagline = NSAttributedString(string: "Snap. Paste. Done.", attributes: taglineAttrs)
tagline.draw(in: NSRect(x: 0, y: height - 78, width: width, height: 18))

// Arrow between the two icon spots.
// Icon spots will be at x=160 and x=440, both at y≈200 (icon center).
// Arrow runs roughly from x=240 to x=360 at y=200.
let arrowY: CGFloat = height - 200
let arrowStartX: CGFloat = 230
let arrowEndX: CGFloat = 370

ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.30).cgColor)
ctx.setLineWidth(1.5)
ctx.setLineCap(.round)
ctx.move(to: CGPoint(x: arrowStartX, y: arrowY))
ctx.addLine(to: CGPoint(x: arrowEndX - 8, y: arrowY))
ctx.strokePath()

// Arrowhead.
ctx.setFillColor(NSColor.white.withAlphaComponent(0.30).cgColor)
ctx.move(to: CGPoint(x: arrowEndX, y: arrowY))
ctx.addLine(to: CGPoint(x: arrowEndX - 10, y: arrowY + 5))
ctx.addLine(to: CGPoint(x: arrowEndX - 10, y: arrowY - 5))
ctx.closePath()
ctx.fillPath()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:])
else {
    print("failed to encode png")
    exit(1)
}

let url = URL(fileURLWithPath: outPath)
do {
    try png.write(to: url)
    print("✓ wrote \(outPath) (\(png.count) bytes)")
} catch {
    print("write failed: \(error)")
    exit(1)
}
