public struct NavigationHistory<Location: Equatable> {
    private var past: [Location] = []
    private var future: [Location] = []

    public init() {}
    public var canGoBack: Bool { !past.isEmpty }
    public var canGoForward: Bool { !future.isEmpty }

    public mutating func record(from: Location, to: Location) {
        guard from != to else { return }
        past.append(from)
        future.removeAll()
    }

    public mutating func back(from current: Location) -> Location? {
        guard let previous = past.popLast() else { return nil }
        future.append(current)
        return previous
    }

    public mutating func forward(from current: Location) -> Location? {
        guard let next = future.popLast() else { return nil }
        past.append(current)
        return next
    }
}
