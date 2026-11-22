import AppKit
import SwiftUI
import WritingLibrary

struct SwipeTree<Node: Identifiable, Row: View>: View {
    var nodes: [Node]
    var children: (Node) -> [Node]?
    var row: (Node) -> Row

    var body: some View {
        ForEach(nodes) { node in
            SwipeTreeBranch(node: node, children: children, row: row)
        }
    }
}

private struct SwipeTreeBranch<Node: Identifiable, Row: View>: View {
    var node: Node
    var children: (Node) -> [Node]?
    var row: (Node) -> Row
    @ViewState private var expanded = false

    var body: some View {
        if let descendants = children(node), !descendants.isEmpty {
            DisclosureGroup(isExpanded: $expanded) {
                SwipeTree(nodes: descendants, children: children, row: row)
            } label: {
                row(node).background(NodeSwipeMarker { direction in expanded = direction == .right })
            }
        } else {
            row(node)
        }
    }
}

struct NodeSwipeMarker: NSViewRepresentable {
    var change: (SwipeDirection) -> Void
    func makeNSView(context: Context) -> Marker { Marker() }
    func updateNSView(_ view: Marker, context: Context) { view.change = change }

    final class Marker: NSView {
        var change: ((SwipeDirection) -> Void)?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
