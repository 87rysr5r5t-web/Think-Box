import SwiftUI
import WritingLibrary

enum WorkspaceLayout: String, CaseIterable, Identifiable, Codable {
    case wide, stacked, listOnly, focus

    var id: Self { self }

    var title: String {
        switch self {
        case .wide: "Pantalla ancha"
        case .stacked: "Lista encima del documento"
        case .listOnly: "Solo lista"
        case .focus: "Solo documento"
        }
    }
}

enum InspectorSection: String, CaseIterable, Identifiable {
    case details = "Información", links = "Enlaces"
    var id: Self { self }
}

struct LibraryLocation: Equatable {
    var scope: LibraryScope = .all
    var selection: ItemDestination?
    var target: ItemDestination?
    var query = ""
}

struct LibraryTab: Identifiable {
    let id = UUID()
    var location = LibraryLocation()
    var history = NavigationHistory<LibraryLocation>()
}

struct WorkspaceDivider: View {
    let color: Color
    var vertical = true
    var extent: CGFloat
    var resize: (CGFloat) -> Void
    var toggle: () -> Void
    @ViewState private var dragStart: CGFloat?

    var body: some View {
        Rectangle().fill(color)
            .frame(width: vertical ? DesignTokens.divider : nil, height: vertical ? nil : DesignTokens.divider)
            .overlay {
                Color.clear.frame(width: vertical ? 6 : nil, height: vertical ? nil : 6)
                    .contentShape(Rectangle()).onTapGesture(count: 2, perform: toggle)
                    .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .global)
                        .onChanged { motion in
                            if dragStart == nil { dragStart = extent }
                            let change = vertical ? motion.translation.width : motion.translation.height
                            resize((dragStart ?? extent) + change)
                        }
                        .onEnded { _ in dragStart = nil })
            }
            .accessibilityHidden(true)
    }
}
