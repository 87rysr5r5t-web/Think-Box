import Foundation

public enum WritingViewMode: String, Codable, CaseIterable, Sendable {
    case source, preview, split
}

public enum WritingPaper: String, Codable, CaseIterable, Sendable {
    case a4, a5, b5, letter, legal, executive, custom

    public var title: String {
        switch self {
        case .a4: "A4"
        case .a5: "A5"
        case .b5: "B5 (ISO)"
        case .letter: "Carta"
        case .legal: "Legal"
        case .executive: "Ejecutivo"
        case .custom: "Personalizado"
        }
    }

    var millimeters: CGSize {
        switch self {
        case .a4, .custom: CGSize(width: 210, height: 297)
        case .a5: CGSize(width: 148, height: 210)
        case .b5: CGSize(width: 176, height: 250)
        case .letter: CGSize(width: 215.9, height: 279.4)
        case .legal: CGSize(width: 215.9, height: 355.6)
        case .executive: CGSize(width: 184.15, height: 266.7)
        }
    }
}

public enum WritingMargins: String, Codable, CaseIterable, Sendable {
    case normal, narrow, wide, mirrored, custom

    public var title: String {
        switch self {
        case .normal: "Normal"
        case .narrow: "Estrecho"
        case .wide: "Ancho"
        case .mirrored: "Espejo para libro"
        case .custom: "Personalizado"
        }
    }
}

public struct PageInsets: Codable, Equatable, Sendable {
    public var top: Double = 24
    public var bottom: Double = 24
    public var left: Double = 24
    public var right: Double = 24

    public init() {}
}

public struct PageLabels: Codable, Equatable, Sendable {
    public var header = ""
    public var footer = "{pagina}"

    public init() {}
}

public struct WritingPageLayout: Codable, Equatable, Sendable {
    public static let pageBreak = "<div style=\"page-break-after: always\"></div>"

    public var paper = WritingPaper.a4
    public var width = 210.0
    public var height = 297.0
    public var landscape = false
    public var margins = WritingMargins.normal
    public var customInsets = PageInsets()
    public var columns = 1
    public var labels = PageLabels()
    public var firstLabels: PageLabels?
    public var evenLabels: PageLabels?
    public var firstNumber = 1

    public init() {}

    public var paperSize: CGSize {
        let size = paper == .custom
            ? CGSize(width: Self.clamp(width, 100...900), height: Self.clamp(height, 100...900))
            : paper.millimeters
        return CGSize(width: (landscape ? size.height : size.width) * 72 / 25.4,
                      height: (landscape ? size.width : size.height) * 72 / 25.4)
    }

    public func contentRect(page: Int) -> CGRect {
        var insets = PageInsets()
        switch margins {
        case .normal: break
        case .narrow:
            insets.top = 12; insets.bottom = 12; insets.left = 12; insets.right = 12
        case .wide:
            insets.left = 38; insets.right = 38
        case .mirrored:
            insets.left = page.isMultiple(of: 2) ? 30 : 18
            insets.right = page.isMultiple(of: 2) ? 18 : 30
        case .custom: insets = customInsets
        }
        let size = paperSize
        let capX = (size.width - 144) / 2
        let capY = (size.height - 96) / 2
        func points(_ mm: Double, cap: CGFloat) -> CGFloat { min(cap, Self.clamp(mm, 8...300) * 72 / 25.4) }
        let left = points(insets.left, cap: capX)
        let right = points(insets.right, cap: capX)
        let top = points(insets.top, cap: capY)
        let bottom = points(insets.bottom, cap: capY)
        return CGRect(x: left, y: top, width: size.width - left - right, height: size.height - top - bottom)
    }

    public var columnCount: Int { min(3, max(1, columns)) }

    public func labels(page: Int) -> PageLabels {
        if page == 0, let firstLabels { return firstLabels }
        if page % 2 == 1, let evenLabels { return evenLabels }
        return labels
    }

    public func pageNumber(_ index: Int) -> Int { min(99999, max(1, firstNumber)) + index }

    private static func clamp(_ number: Double, _ range: ClosedRange<Double>) -> Double {
        number.isFinite ? min(range.upperBound, max(range.lowerBound, number)) : range.lowerBound
    }
}

public struct WritingPageViews: Codable, Equatable, Sendable {
    public var mode = WritingViewMode.source
    public var editor = false
    public var preview = false

    public init() {}
}
