import AppKit

// Custom menu-bar icon. Hand-translated from the provided 24×24 SVG so it
// renders crisply at any scale and tints automatically as a template image.
enum MenuBarIcon {
    static func make(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
            let scale = size / 24.0
            let combined = NSBezierPath()

            // Path 1: top edge + first feather
            let p1 = NSBezierPath()
            p1.move(to: NSPoint(x: 12, y: 10.9688))
            p1.line(to: NSPoint(x: 11.6212, y: 5.66555))
            p1.curve(to: NSPoint(x: 9.56394, y: 3.75),
                     controlPoint1: NSPoint(x: 11.5441, y: 4.58624),
                     controlPoint2: NSPoint(x: 10.646, y: 3.75))
            p1.line(to: NSPoint(x: 2.71875, y: 3.75))
            p1.line(to: NSPoint(x: 2.71875, y: 4.78125))
            p1.curve(to: NSPoint(x: 4.78125, y: 6.84375),
                     controlPoint1: NSPoint(x: 2.71875, y: 5.92034),
                     controlPoint2: NSPoint(x: 3.64216, y: 6.84375))
            p1.line(to: NSPoint(x: 7.25, y: 6.84375))

            // Path 2: bottom feather
            let p2 = NSBezierPath()
            p2.move(to: NSPoint(x: 7.875, y: 9.9375))
            p2.line(to: NSPoint(x: 4.78125, y: 9.9375))
            p2.line(to: NSPoint(x: 4.78125, y: 10.9688))
            p2.curve(to: NSPoint(x: 6.84375, y: 13.0312),
                     controlPoint1: NSPoint(x: 4.78125, y: 12.1078),
                     controlPoint2: NSPoint(x: 5.70466, y: 13.0312))
            p2.line(to: NSPoint(x: 9.9375, y: 13.0312))

            // Path 3: middle feather
            let p3 = NSBezierPath()
            p3.move(to: NSPoint(x: 6.84375, y: 6.84375))
            p3.line(to: NSPoint(x: 3.75, y: 6.84375))
            p3.line(to: NSPoint(x: 3.75, y: 7.875))
            p3.curve(to: NSPoint(x: 5.8125, y: 9.9375),
                     controlPoint1: NSPoint(x: 3.75, y: 9.01409),
                     controlPoint2: NSPoint(x: 4.67341, y: 9.9375))
            p3.line(to: NSPoint(x: 8.25, y: 9.9375))

            // Eye
            let r: CGFloat = 1.75313
            let eye = NSBezierPath(ovalIn: NSRect(
                x: 12.0031 - r, y: 12.9289 - r, width: r * 2, height: r * 2))

            // Path 4: head/jaw outline
            let p4 = NSBezierPath()
            p4.move(to: NSPoint(x: 6.8125, y: 13.0312))
            p4.line(to: NSPoint(x: 6.8125, y: 15.9171))
            p4.curve(to: NSPoint(x: 6.36054, y: 17.2056),
                     controlPoint1: NSPoint(x: 6.8125, y: 16.3855),
                     controlPoint2: NSPoint(x: 6.65311, y: 16.8399))
            p4.line(to: NSPoint(x: 4.91729, y: 19.0096))
            p4.curve(to: NSPoint(x: 4.75, y: 19.4866),
                     controlPoint1: NSPoint(x: 4.809, y: 19.145),
                     controlPoint2: NSPoint(x: 4.75, y: 19.3132))
            p4.curve(to: NSPoint(x: 5.51345, y: 20.25),
                     controlPoint1: NSPoint(x: 4.75, y: 19.9082),
                     controlPoint2: NSPoint(x: 5.09181, y: 20.25))
            p4.line(to: NSPoint(x: 8.18394, y: 20.25))
            p4.curve(to: NSPoint(x: 12.3649, y: 19.1397),
                     controlPoint1: NSPoint(x: 9.65048, y: 20.25),
                     controlPoint2: NSPoint(x: 11.0916, y: 19.8673))
            p4.curve(to: NSPoint(x: 15.9455, y: 18.0508),
                     controlPoint1: NSPoint(x: 13.4618, y: 18.5129),
                     controlPoint2: NSPoint(x: 14.6855, y: 18.1408))
            p4.line(to: NSPoint(x: 19.3344, y: 17.8087))
            p4.curve(to: NSPoint(x: 21.25, y: 15.7514),
                     controlPoint1: NSPoint(x: 20.4138, y: 17.7316),
                     controlPoint2: NSPoint(x: 21.25, y: 16.8335))
            p4.line(to: NSPoint(x: 21.25, y: 15.1962))
            p4.curve(to: NSPoint(x: 20.6972, y: 14.3017),
                     controlPoint1: NSPoint(x: 21.25, y: 14.8174),
                     controlPoint2: NSPoint(x: 21.036, y: 14.4711))
            p4.line(to: NSPoint(x: 19.1875, y: 13.5469))
            p4.curve(to: NSPoint(x: 12.9766, y: 7.875),
                     controlPoint1: NSPoint(x: 18.8955, y: 10.3346),
                     controlPoint2: NSPoint(x: 16.2021, y: 7.875))
            p4.line(to: NSPoint(x: 11.9688, y: 7.875))

            combined.append(p1)
            combined.append(p2)
            combined.append(p3)
            combined.append(eye)
            combined.append(p4)

            var transform = AffineTransform.identity
            transform.scale(scale)
            combined.transform(using: transform)

            combined.lineWidth = 1.5 * scale
            combined.lineCapStyle = .round
            combined.lineJoinStyle = .round
            NSColor.labelColor.setStroke()
            combined.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}
