import AppKit
import SwiftUI
import WritingLibrary

enum SwipePane: Equatable { case navigation, results, inspector }

struct PaneSwipeTarget {
    var pane: SwipePane
    var isOpen: Bool
    var extent: CGFloat
}

struct PaneScrollMonitor: NSViewRepresentable {
    var options: GestureOptions
    var target: (CGPoint, SwipeDirection) -> PaneSwipeTarget?
    var update: (PaneSwipeTarget, CGFloat) -> Void
    var finish: (PaneSwipeTarget, Bool) -> Void

    func makeNSView(context: Context) -> MonitorView { MonitorView() }
    func updateNSView(_ view: MonitorView, context: Context) { view.configuration = self }
    static func dismantleNSView(_ view: MonitorView, coordinator: ()) { view.stop() }

    final class MonitorView: NSView {
        var configuration: PaneScrollMonitor?
        private var token: Any?
        private var gesture = PaneSwipe()
        private var origin: CGPoint?
        private var active: PaneSwipeTarget?
        private var skipped = false
        private var nodeConsumed = false
        private var swallowMomentum = false
        private var lastWheelAction: TimeInterval = -.infinity

        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            if window != nil {
                token = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                    guard let self else { return event }
                    return self.handle(event)
                }
            }
        }

        func stop() {
            if let token { NSEvent.removeMonitor(token); self.token = nil }
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard let configuration, configuration.options.enabled, event.window === window else { return event }
            // Only the innermost monitor under the pointer owns a document gesture.
            let pointInWindow = event.locationInWindow
            if (event.phase.contains(.began) || event.phase.isEmpty), let root = window?.contentView, nestedMonitor(in: root, at: pointInWindow, event: event) { return event }

            if event.phase.isEmpty && event.momentumPhase.isEmpty && !event.hasPreciseScrollingDeltas {
                guard configuration.options.horizontalWheel == true,
                      let direction = HorizontalWheel.direction(x: event.scrollingDeltaX, y: event.scrollingDeltaY,
                        invertedByDevice: event.isDirectionInvertedFromDevice, reverse: configuration.options.reverse),
                      !scrollableContentConsumes(event) else { return event }
                let point = convert(event.locationInWindow, from: nil)
                guard bounds.contains(point), let target = configuration.target(point, direction) else { return event }
                // A wheel can emit several events for one movement; do not cascade through panels accidentally.
                if event.timestamp - lastWheelAction >= 0.35 {
                    lastWheelAction = event.timestamp
                    configuration.finish(target, true)
                }
                return nil
            }
            guard event.hasPreciseScrollingDeltas else { return event }

            if !event.momentumPhase.isEmpty {
                let consume = swallowMomentum
                if event.momentumPhase.contains(.ended) { swallowMomentum = false }
                return consume ? nil : event
            }
            if event.phase.contains(.began) {
                if let active { configuration.finish(active, false) }
                gesture = PaneSwipe()
                active = nil
                skipped = false
                nodeConsumed = false
                swallowMomentum = false
                let point = convert(event.locationInWindow, from: nil)
                origin = bounds.contains(point) ? point : nil
            }
            if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
                if nodeConsumed { nodeConsumed = false; origin = nil; return nil }
                let completed = active
                active = nil
                origin = nil
                if let completed {
                    let toggle = !event.phase.contains(.cancelled) && gesture.shouldToggle(
                        extent: completed.extent, fraction: configuration.options.threshold, endedAt: event.timestamp)
                    swallowMomentum = true
                    configuration.finish(completed, toggle)
                    return nil
                }
                return event
            }
            if nodeConsumed { return nil }
            guard !event.phase.isEmpty, let origin, !skipped else { return event }
            let horizontal = PaneSwipe.fingerDelta(event.scrollingDeltaX,
                invertedByDevice: event.isDirectionInvertedFromDevice, reverse: configuration.options.reverse)
            gesture.add(x: horizontal, y: event.scrollingDeltaY, at: event.timestamp,
                        sensitivity: configuration.options.sensitivity ?? .medium)
            guard let direction = gesture.direction else { return event }
            if active == nil {
                if configuration.options.foldNodes != false,
                   let root = window?.contentView,
                   let marker = nodeMarker(in: root, at: convert(origin, to: nil)) {
                    marker.change?(direction)
                    nodeConsumed = true
                    swallowMomentum = true
                    return nil
                }
                guard !scrollableContentConsumes(event), let target = configuration.target(origin, direction) else {
                    skipped = true
                    return event
                }
                active = target
            }
            if let active { configuration.update(active, gesture.distance) }
            return nil
        }

        private func nestedMonitor(in view: NSView, at point: CGPoint, event: NSEvent) -> Bool {
            guard !view.isHidden else { return false }
            if let monitor = view as? MonitorView, monitor !== self,
               monitor.isDescendant(of: superview ?? self),
               monitor.visibleRect.contains(monitor.convert(point, from: nil)),
               let child = monitor.configuration {
                let x = PaneSwipe.fingerDelta(event.scrollingDeltaX,
                    invertedByDevice: event.isDirectionInvertedFromDevice, reverse: child.options.reverse)
                let location = monitor.convert(point, from: nil)
                if event.phase.contains(.began) {
                    if child.target(location, .left) != nil || child.target(location, .right) != nil { return true }
                } else if child.target(location, x < 0 ? .left : .right) != nil { return true }
            }
            return view.subviews.contains { nestedMonitor(in: $0, at: point, event: event) }
        }

        private func nodeMarker(in view: NSView, at point: CGPoint) -> NodeSwipeMarker.Marker? {
            guard !view.isHidden else { return nil }
            if let marker = view as? NodeSwipeMarker.Marker,
               marker.visibleRect.contains(marker.convert(point, from: nil)) { return marker }
            for child in view.subviews {
                if let marker = nodeMarker(in: child, at: point) { return marker }
            }
            return nil
        }

        private func scrollableContentConsumes(_ event: NSEvent) -> Bool {
            guard let root = window?.contentView else { return false }
            let point = root.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow
            var view = root.hitTest(point)
            while let current = view {
                if let scroll = current as? NSScrollView, let document = scroll.documentView {
                    let visible = scroll.documentVisibleRect
                    let bounds = document.bounds
                    // A few points of overflow (PDFView pads its pages) is not real horizontal
                    // content; only a genuinely wider document (a zoomed page) keeps the swipe.
                    if bounds.width - visible.width > 4, HorizontalScrollPriority.canScroll(delta: event.scrollingDeltaX, offset: visible.minX,
                        minimum: bounds.minX, maximum: max(bounds.minX, bounds.maxX - visible.width)) {
                        return true
                    }
                }
                view = current.superview
            }
            return false
        }
    }
}
