import Testing
import WritingLibrary

@Test func horizontalContentHasPriorityUntilItReachesItsEdge() {
    #expect(HorizontalScrollPriority.canScroll(delta: -5, offset: 0, minimum: 0, maximum: 100))
    #expect(!HorizontalScrollPriority.canScroll(delta: 5, offset: 0, minimum: 0, maximum: 100))
    #expect(HorizontalScrollPriority.canScroll(delta: 5, offset: 100, minimum: 0, maximum: 100))
    #expect(!HorizontalScrollPriority.canScroll(delta: -5, offset: 100, minimum: 0, maximum: 100))
    #expect(HorizontalScrollPriority.canScroll(delta: -5, offset: 50, minimum: 0, maximum: 100))
    #expect(!HorizontalScrollPriority.canScroll(delta: -5, offset: 0, minimum: 0, maximum: 0))
}

@Test func horizontalWheelRequiresADominantHorizontalDelta() {
    #expect(HorizontalWheel.direction(x: 0, y: 10, invertedByDevice: false, reverse: false) == nil)
    #expect(HorizontalWheel.direction(x: 4, y: 2, invertedByDevice: false, reverse: false) == nil)
    #expect(HorizontalWheel.direction(x: .nan, y: 0, invertedByDevice: false, reverse: false) == nil)
    #expect(HorizontalWheel.direction(x: 4, y: 1, invertedByDevice: true, reverse: false) == .right)
    #expect(HorizontalWheel.direction(x: -4, y: 1, invertedByDevice: false, reverse: false) == .right)
    #expect(HorizontalWheel.direction(x: 4, y: 1, invertedByDevice: true, reverse: true) == .left)
}

@Test func swipeSensitivityChangesActivationWithoutAcceptingVerticalMovement() {
    var low = PaneSwipe()
    var medium = PaneSwipe()
    var high = PaneSwipe()
    low.add(x: 5, y: 0, at: 0, sensitivity: .low)
    medium.add(x: 5, y: 0, at: 0, sensitivity: .medium)
    high.add(x: 5, y: 0, at: 0, sensitivity: .high)
    #expect(low.direction == nil)
    #expect(medium.direction == nil)
    #expect(high.direction == .right)
    low.add(x: 5, y: 0, at: 0.1, sensitivity: .low)
    #expect(low.direction == .right)
    var vertical = PaneSwipe()
    vertical.add(x: 3, y: 5, at: 0, sensitivity: .high)
    vertical.add(x: 30, y: 0, at: 0.1, sensitivity: .high)
    #expect(vertical.direction == nil)
}

@Test func swipeLocksDirectionAndRequiresHorizontalTravel() {
    var vertical = PaneSwipe()
    vertical.add(x: 2, y: 12, at: 0)
    vertical.add(x: 200, y: 0, at: 0.05)
    #expect(vertical.direction == nil)

    var left = PaneSwipe()
    left.add(x: -8, y: 2, at: 0)
    left.add(x: -95, y: 0, at: 0.2)
    #expect(left.direction == .left)
    #expect(left.shouldToggle(extent: 250, fraction: 0.40, endedAt: 0.21))
    left.add(x: 50, y: 0, at: 0.4)
    #expect(!left.shouldToggle(extent: 250, fraction: 0.40, endedAt: 0.5))
}

@Test func swipeAllowsAFastFlickButNotAfterAPause() {
    var swipe = PaneSwipe()
    swipe.add(x: 8, y: 0, at: 1)
    swipe.add(x: 22, y: 0, at: 1.02)
    #expect(swipe.shouldToggle(extent: 250, fraction: 0.40, endedAt: 1.03))
    #expect(!swipe.shouldToggle(extent: 250, fraction: 0.40, endedAt: 1.2))
    #expect(PaneSwipe.fingerDelta(20, invertedByDevice: true, reverse: false) == PaneSwipe.fingerDelta(-20, invertedByDevice: false, reverse: false))
    #expect(PaneSwipe.fingerDelta(20, invertedByDevice: true, reverse: true) == -20)
}
