import Foundation

public enum SwipeDirection: Equatable { case left, right }

/// Discrete wheels have no gesture phases; accept only clearly horizontal input.
public enum HorizontalWheel {
    public static func direction(x: Double, y: Double, invertedByDevice: Bool, reverse: Bool) -> SwipeDirection? {
        guard x.isFinite, y.isFinite, abs(x) > 0, abs(x) > 2 * abs(y) else { return nil }
        let delta = PaneSwipe.fingerDelta(x, invertedByDevice: invertedByDevice, reverse: reverse)
        return delta < 0 ? .left : .right
    }
}

public enum HorizontalScrollPriority {
    /// Scroll-wheel deltas move content; a positive delta moves the viewport toward its minimum.
    public static func canScroll(delta: Double, offset: Double, minimum: Double, maximum: Double) -> Bool {
        guard delta.isFinite, offset.isFinite, minimum.isFinite, maximum.isFinite,
              maximum > minimum, delta != 0 else { return false }
        let tolerance = 0.5
        return delta > 0 ? offset > minimum + tolerance : offset < maximum - tolerance
    }
}

public enum SwipeSensitivity: String, Codable, CaseIterable {
    case low, medium, high

    public var title: String {
        switch self { case .low: "Baja"; case .medium: "Media"; case .high: "Alta" }
    }

    var activationDistance: Double {
        switch self { case .low: 10; case .medium: 6; case .high: 4 }
    }
}

/// The input is displacement in finger coordinates, with positive x to the right.
public struct PaneSwipe {
    public private(set) var direction: SwipeDirection?
    public private(set) var distance: Double = 0
    private var travel: Double = 0
    private var vertical: Double = 0
    private var rejected = false
    private var samples: [(time: Double, travel: Double)] = []

    public init() {}

    public mutating func add(x: Double, y: Double, at time: Double, sensitivity: SwipeSensitivity = .medium) {
        guard !rejected else { return }
        travel += x
        if direction == nil {
            vertical += abs(y)
            guard max(abs(travel), vertical) >= sensitivity.activationDistance else { return }
            guard abs(travel) > 2 * vertical else { rejected = true; return }
            direction = travel < 0 ? .left : .right
        }
        distance = max(0, direction == .left ? -travel : travel)
        samples.append((time, distance))
        samples.removeAll { time - $0.time > 0.09 }
    }

    public func shouldToggle(extent: Double, fraction: Double, endedAt time: Double) -> Bool {
        guard direction != nil, extent > 0 else { return false }
        if distance >= extent * fraction { return true }
        guard distance >= 18, let first = samples.first, let last = samples.last,
              time - last.time < 0.07, last.time > first.time else { return false }
        return (last.travel - first.travel) / (last.time - first.time) > 850
    }

    public static func fingerDelta(_ delta: Double, invertedByDevice: Bool, reverse: Bool) -> Double {
        let physical = invertedByDevice ? delta : -delta
        return reverse ? -physical : physical
    }
}
