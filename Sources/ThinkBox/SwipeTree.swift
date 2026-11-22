import AppKit
import SwiftUI
import WritingLibrary

struct SwipeTree<Node: Identifiable, Row: View>: View {
    var nodes: [Node]
    var children: (Node) -> [Node]?
    var row: (Node) -> Row

    var body: some View {
        // When some siblings have a disclosure arrow, the others are inset by the same amount
        // so every icon and title in the level lines up.
        let aligned = nodes.contains { children($0)?.isEmpty == false }
        ForEach(nodes) { node in
            SwipeTreeBranch(node: node, children: children, row: row, alignLeaf: aligned)
        }
    }
}

private struct SwipeTreeBranch<Node: Identifiable, Row: View>: View {
    var node: Node
    var children: (Node) -> [Node]?
    var row: (Node) -> Row
    var alignLeaf = false
    @ViewState private var expanded = false

    var body: some View {
        if let descendants = children(node), !descendants.isEmpty {
            DisclosureGroup(isExpanded: $expanded) {
                SwipeTree(nodes: descendants, children: children, row: row)
            } label: {
                row(node).background(NodeSwipeMarker { direction in expanded = direction == .right })
            }
        } else {
            row(node).padding(.leading, alignLeaf ? SwipeTreeMetrics.disclosureInset : 0)
        }
    }
}

enum SwipeTreeMetrics {
    /// Width the sidebar's disclosure arrow takes before a row's own content.
    static let disclosureInset: CGFloat = 12
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
