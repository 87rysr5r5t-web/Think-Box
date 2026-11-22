import AppKit
import SwiftUI

/// Think Box's own linear icon set: drawn on a 24-unit grid, rendered at 16 pt with a
/// 1.5 pt stroke, round caps and joins, as monochrome template images so they take the
/// colour of the surrounding text (secondary at rest, primary on hover or when active).
/// Original drawings in the style of Lucide/Codicons; no third-party artwork is bundled.
///
/// Icons are looked up by the SF Symbol name the code used before, so call sites keep their
/// meaning. Names without a drawing fall back to the SF Symbol.
enum LineIcon {
    static let stroke: CGFloat = 1.5

    static func has(_ name: String) -> Bool { drawings[name] != nil }

    /// Template image of the icon at `size` points, or nil when the set has no drawing for it.
    @MainActor static func image(_ name: String, size: CGFloat = DesignTokens.icon) -> NSImage? {
        let key = "\(name)@\(size)"
        if let cached = cache[key] { return cached }
        guard let draw = drawings[name] else { return nil }
        let path = CGMutablePath()
        draw(Pen(path: path))
        let scale = size / 24
        let width = size < 12 ? stroke * 0.85 : stroke
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.scaleBy(x: scale, y: scale)
            context.addPath(path)
            context.setLineWidth(width / scale)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.setStrokeColor(NSColor.black.cgColor)
            context.strokePath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = nil
        cache[key] = image
        return image
    }

    @MainActor private static var cache: [String: NSImage] = [:]

    /// Small drawing helper over a CGMutablePath in 24-unit coordinates (y grows downwards).
    struct Pen: @unchecked Sendable {
        let path: CGMutablePath

        func line(_ points: CGFloat...) {
            precondition(points.count >= 4 && points.count.isMultiple(of: 2))
            path.move(to: CGPoint(x: points[0], y: points[1]))
            stride(from: 2, to: points.count, by: 2).forEach { path.addLine(to: CGPoint(x: points[$0], y: points[$0 + 1])) }
        }
        func closed(_ points: CGFloat...) {
            path.move(to: CGPoint(x: points[0], y: points[1]))
            stride(from: 2, to: points.count, by: 2).forEach { path.addLine(to: CGPoint(x: points[$0], y: points[$0 + 1])) }
            path.closeSubpath()
        }
        func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, radius: CGFloat = 2) {
            path.addRoundedRect(in: CGRect(x: x, y: y, width: width, height: height), cornerWidth: radius, cornerHeight: radius)
        }
        func circle(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat) {
            path.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
        }
        /// A dot drawn as a zero-length round-capped stroke.
        func dot(_ x: CGFloat, _ y: CGFloat) { line(x, y, x + 0.01, y) }
        /// Open path with rounded corners: points are the corners, `radius` rounds every inner one.
        func rounded(_ points: CGFloat..., radius: CGFloat = 2, close: Bool = false) {
            let corners = stride(from: 0, to: points.count, by: 2).map { CGPoint(x: points[$0], y: points[$0 + 1]) }
            path.move(to: corners[0])
            for index in 1..<corners.count - 1 {
                path.addArc(tangent1End: corners[index], tangent2End: corners[index + 1], radius: radius)
            }
            path.addLine(to: corners[corners.count - 1])
            if close { path.closeSubpath() }
        }
        func pill(center: CGPoint, length: CGFloat, thickness: CGFloat, angle: CGFloat) {
            var transform = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: angle)
            let rect = CGRect(x: -length / 2, y: -thickness / 2, width: length, height: thickness)
            path.addPath(CGPath(roundedRect: rect, cornerWidth: thickness / 2, cornerHeight: thickness / 2, transform: &transform))
        }
    }

    private static let search: @Sendable (Pen) -> Void = { $0.circle(11, 11, 7); $0.line(16, 16, 21, 21) }
    private static let document: @Sendable (Pen) -> Void = { pen in
        pen.rounded(14, 2, 4, 2, 4, 22, 20, 22, 20, 8)
        pen.line(20, 8, 14, 2)
        pen.line(14, 2, 14, 8, 20, 8)
    }

    private static let drawings: [String: @Sendable (Pen) -> Void] = [
        "sidebar.left": { $0.rect(3, 4, 18, 16); $0.line(9, 4, 9, 20) },
        "sidebar.right": { $0.rect(3, 4, 18, 16); $0.line(15, 4, 15, 20) },
        "rectangle.split.2x1": { $0.rect(3, 4, 18, 16); $0.line(10, 4, 10, 20) },
        "rectangle.split.1x2": { $0.rect(3, 4, 18, 16); $0.line(3, 11, 21, 11) },
        "list.bullet.rectangle": { pen in
            pen.rect(3, 4, 18, 16)
            [9, 12, 15].forEach { pen.line(10, CGFloat($0), 17, CGFloat($0)); pen.dot(7, CGFloat($0)) }
        },
        "chevron.left": { $0.line(15, 6, 9, 12, 15, 18) },
        "chevron.right": { $0.line(9, 6, 15, 12, 9, 18) },
        "chevron.up": { $0.line(6, 15, 12, 9, 18, 15) },
        "chevron.down": { $0.line(6, 9, 12, 15, 18, 9) },
        "magnifyingglass": search,
        "plus.magnifyingglass": { search($0); $0.line(11, 8, 11, 14); $0.line(8, 11, 14, 11) },
        "minus.magnifyingglass": { search($0); $0.line(8, 11, 14, 11) },
        "plus": { $0.line(12, 5, 12, 19); $0.line(5, 12, 19, 12) },
        "minus": { $0.line(5, 12, 19, 12) },
        "xmark": { $0.line(6, 6, 18, 18); $0.line(18, 6, 6, 18) },
        "checkmark": { $0.line(4, 12.5, 9, 17.5, 20, 6.5) },
        "ellipsis": { $0.dot(5, 12); $0.dot(12, 12); $0.dot(19, 12) },
        "square.and.pencil": { pen in
            pen.rounded(11, 4, 4, 4, 4, 20, 20, 20, 20, 13)
            pen.closed(18.5, 2.5, 21.5, 5.5, 12, 15, 8, 16, 9, 12)
        },
        "pencil": { $0.closed(17, 3, 21, 7, 8, 20, 3, 21, 4, 16); $0.line(15, 5, 19, 9) },
        "list.bullet": { pen in
            [6, 12, 18].forEach { pen.line(8, CGFloat($0), 21, CGFloat($0)); pen.dot(3.5, CGFloat($0)) }
        },
        "line.3.horizontal": { pen in [6, 12, 18].forEach { pen.line(4, CGFloat($0), 20, CGFloat($0)) } },
        "list.bullet.indent": { pen in
            pen.line(3, 6, 21, 6); pen.line(9, 12, 21, 12); pen.line(9, 18, 21, 18)
            pen.line(3, 10, 5, 12, 3, 14)
        },
        "text.alignleft": { $0.line(3, 6, 21, 6); $0.line(3, 12, 15, 12); $0.line(3, 18, 18, 18) },
        "gearshape": { pen in
            pen.circle(12, 12, 3)
            var points: [CGPoint] = []
            for tooth in 0..<8 {
                let base = CGFloat(tooth) * .pi / 4
                for (offset, radius) in [(-0.39, 7.2), (-0.2, 9.5), (0.2, 9.5), (0.39, 7.2)] as [(CGFloat, CGFloat)] {
                    points.append(CGPoint(x: 12 + radius * cos(base + offset), y: 12 + radius * sin(base + offset)))
                }
            }
            pen.path.addLines(between: points)
            pen.path.closeSubpath()
        },
        "rectangle.on.rectangle.badge.plus": { pen in
            pen.rounded(7, 7, 7, 3, 21, 3, 21, 17, 17, 17)
            pen.rect(3, 7, 14, 14)
            pen.line(10, 11, 10, 17); pen.line(7, 14, 13, 14)
        },
        "rectangle.on.rectangle": { $0.rounded(7, 7, 7, 3, 21, 3, 21, 17, 17, 17); $0.rect(3, 7, 14, 14) },
        "cylinder": { pen in
            pen.path.addEllipse(in: CGRect(x: 4, y: 2, width: 16, height: 6))
            pen.line(4, 5, 4, 19); pen.line(20, 5, 20, 19)
            pen.path.move(to: CGPoint(x: 4, y: 12))
            pen.path.addCurve(to: CGPoint(x: 20, y: 12), control1: CGPoint(x: 4, y: 16), control2: CGPoint(x: 20, y: 16))
            pen.path.move(to: CGPoint(x: 4, y: 19))
            pen.path.addCurve(to: CGPoint(x: 20, y: 19), control1: CGPoint(x: 4, y: 23), control2: CGPoint(x: 20, y: 23))
        },
        "tray": { pen in
            pen.line(22, 12, 16, 12, 14, 15, 10, 15, 8, 12, 2, 12)
            pen.rounded(5.5, 5, 2, 12, 2, 20, 22, 20, 22, 12, 18.5, 5, radius: 2, close: true)
        },
        "trash": { pen in
            pen.line(3, 6, 21, 6)
            pen.rounded(19, 6, 19, 22, 5, 22, 5, 6)
            pen.rounded(8, 6, 8, 2, 16, 2, 16, 6)
            pen.line(10, 11, 10, 17); pen.line(14, 11, 14, 17)
        },
        "folder": { $0.rounded(12, 6, 22, 6, 22, 20, 2, 20, 2, 3, 9.5, 3, 12, 6, radius: 2, close: true) },
        "tag": { $0.rounded(3, 3, 11, 3, 21, 13, 13, 21, 3, 11, radius: 1.5, close: true); $0.dot(7.5, 7.5) },
        "link": { pen in
            pen.pill(center: CGPoint(x: 8.8, y: 15.2), length: 11, thickness: 6, angle: -.pi / 4)
            pen.pill(center: CGPoint(x: 15.2, y: 8.8), length: 11, thickness: 6, angle: -.pi / 4)
        },
        "doc": document,
        "doc.fill": { document($0); $0.line(8, 13, 16, 13); $0.line(8, 17, 14, 17) },
        "doc.on.doc": { $0.rect(8, 8, 14, 14); $0.rounded(4, 16, 2, 16, 2, 2, 16, 2, 16, 4) },
        "quote.opening": { pen in
            for x in [3, 13] as [CGFloat] {
                pen.rect(x, 11, 7, 7, radius: 1.5)
                pen.rounded(x, 14, x, 9, x + 6, 5, radius: 4)
            }
        },
        "ruler": { pen in
            pen.rect(2, 7, 20, 10, radius: 1.5)
            pen.line(6, 7, 6, 11); pen.line(10, 7, 10, 10); pen.line(14, 7, 14, 11); pen.line(18, 7, 18, 10)
        },
        "viewfinder": { pen in
            pen.rounded(3, 8, 3, 3, 8, 3); pen.rounded(16, 3, 21, 3, 21, 8)
            pen.rounded(21, 16, 21, 21, 16, 21); pen.rounded(8, 21, 3, 21, 3, 16)
        },
        "printer": { pen in
            pen.line(6, 9, 6, 3, 18, 3, 18, 9)
            pen.rounded(6, 18, 2, 18, 2, 9, 22, 9, 22, 18, 18, 18)
            pen.rect(6, 14, 12, 8, radius: 1)
        },
        "square.and.arrow.up": { pen in
            pen.line(12, 2, 12, 15); pen.line(8, 6, 12, 2, 16, 6)
            pen.rounded(4, 12, 4, 22, 20, 22, 20, 12)
        },
        "arrow.uturn.backward": { pen in
            pen.line(9, 14, 4, 9, 9, 4)
            pen.rounded(4, 9, 20, 9, 20, 20, 11, 20, radius: 5.5)
        },
        "bookmark": { $0.rounded(19, 21, 19, 3, 5, 3, 5, 21, radius: 2); $0.line(5, 21, 12, 16, 19, 21) },
        "arrow.up.left.and.arrow.down.right": { pen in
            pen.line(15, 3, 21, 3, 21, 9); pen.line(9, 21, 3, 21, 3, 15)
            pen.line(21, 3, 14, 10); pen.line(3, 21, 10, 14)
        },
        "arrow.up.forward.app": { pen in
            pen.line(15, 3, 21, 3, 21, 9); pen.line(10, 14, 21, 3)
            pen.rounded(18, 13, 18, 21, 3, 21, 3, 6, 11, 6)
        },
        "lock": { $0.rect(3, 11, 18, 11); $0.rounded(7, 11, 7, 2, 17, 2, 17, 11, radius: 5) },
        "book": { pen in
            pen.rounded(4, 19.5, 4, 2, 20, 2, 20, 22, 6.5, 22, radius: 2)
            pen.path.move(to: CGPoint(x: 20, y: 17))
            pen.path.addLine(to: CGPoint(x: 6.5, y: 17))
            pen.path.addArc(tangent1End: CGPoint(x: 4, y: 17), tangent2End: CGPoint(x: 4, y: 22), radius: 2.5)
            pen.path.addArc(tangent1End: CGPoint(x: 4, y: 22), tangent2End: CGPoint(x: 6.5, y: 22), radius: 2.5)
        },
        "circle.lefthalf.filled": { $0.circle(12, 12, 9); $0.line(12, 3, 12, 21) },
        "hand.point.up.left": { pen in
            pen.rounded(8, 13, 8, 4, 11, 4, 11, 11, radius: 1.5)
            pen.rounded(11, 10, 11, 8, 14, 8, 14, 11, radius: 1.5)
            pen.rounded(14, 11, 14, 9, 17, 9, 17, 12, radius: 1.5)
            pen.rounded(17, 12, 20, 12, 20, 16, 16, 21, 10, 21, 5, 15, 7, 13, 8, 14, radius: 2)
        },
        "rectangle.dashed": { pen in
            pen.line(3, 7, 3, 3, 7, 3); pen.line(17, 3, 21, 3, 21, 7)
            pen.line(21, 17, 21, 21, 17, 21); pen.line(7, 21, 3, 21, 3, 17)
            pen.line(10, 3, 14, 3); pen.line(10, 21, 14, 21); pen.line(3, 10, 3, 14); pen.line(21, 10, 21, 14)
        },
        "exclamationmark.triangle": { pen in
            pen.rounded(12, 3, 22, 20, 2, 20, radius: 2, close: true)
            pen.line(12, 9, 12, 13); pen.dot(12, 16.5)
        },
    ]
}

/// Icon view for chrome: Think Box line icon when one exists, SF Symbol otherwise.
struct ChromeSymbol: View {
    var name: String
    var size: CGFloat = DesignTokens.icon

    var body: some View {
        Group {
            if let image = LineIcon.image(name, size: size) {
                Image(nsImage: image).renderingMode(.template)
            } else {
                Image(systemName: name).font(.system(size: size * 0.85, weight: .light))
                    .symbolRenderingMode(.monochrome)
            }
        }.accessibilityHidden(true)
    }
}

extension Image {
    /// Think Box line icon as an `Image`, usable inside menus, labels and tab items.
    @MainActor static func line(_ name: String, size: CGFloat = DesignTokens.icon) -> Image {
        if let image = LineIcon.image(name, size: size) { return Image(nsImage: image).renderingMode(.template) }
        return Image(systemName: name)
    }
}

extension Label where Title == Text, Icon == Image {
    @MainActor init(_ title: String, line name: String) {
        self.init { Text(title) } icon: { Image.line(name) }
    }
}

extension Button where Label == SwiftUI.Label<Text, Image> {
    @MainActor init(_ title: String, line name: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.init(role: role, action: action) { SwiftUI.Label(title, line: name) }
    }
}

extension Menu where Label == SwiftUI.Label<Text, Image> {
    @MainActor init(_ title: String, line name: String, @ViewBuilder content: () -> Content) {
        self.init(content: content) { SwiftUI.Label(title, line: name) }
    }
}

extension ContentUnavailableView where Label == SwiftUI.Label<Text, Image>, Description == Text?, Actions == EmptyView {
    @MainActor init(_ title: String, line name: String, description: Text? = nil) {
        self.init { SwiftUI.Label(title, line: name) } description: { description }
    }
}
