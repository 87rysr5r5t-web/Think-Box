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

enum InspectorSection: String, CaseIterable, Identifiable, Codable {
    case details = "Información", links = "Enlaces"
    var id: Self { self }
}

struct LibraryLocation: Equatable, Codable {
    var scope: LibraryScope = .all
    var selection: ItemDestination?
    var target: ItemDestination?
    var query = ""
    var databaseID: UUID?
}

struct LibraryTab: Identifiable, Codable {
    var id = UUID()
    var location = LibraryLocation()
    var history = NavigationHistory<LibraryLocation>()

    enum CodingKeys: String, CodingKey { case id, location, panels }
    var panels: TabPanels?
}

struct TabPanels: Codable {
    var sidebarVisible: Bool
    var sidebarWidth: Int
    var listVisible: Bool
    var listWidth: Double
    var listHeight: Double
    var inspectorVisible: Bool
    var inspectorWidth: Double
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

struct SavedWorkspace: Identifiable, Codable {
    var id = UUID()
    var name: String
    var tabs: [LibraryTab]
    var activeTab: Int
    var layouts: Data
    var inspector: InspectorSection
    var documentWindows: [SavedDocumentWindow]?
    var mainFrame: SavedWindowFrame?
}
