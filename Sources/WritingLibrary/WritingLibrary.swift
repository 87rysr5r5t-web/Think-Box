import Foundation

public struct Project: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var name: String
    public var tags: [String]?
    public var excludedFromTagging: Bool?
    /// Containing group; nil (and every library saved before nesting) means top level.
    public var parentID: UUID?

    public init(name: String, parentID: UUID? = nil) {
        self.name = name
        self.parentID = parentID
    }
}

/// A group with the groups nested inside it, for the sidebar tree.
public struct GroupBranch: Identifiable, Equatable, Sendable {
    public let project: Project
    public let children: [GroupBranch]?
    public var id: UUID { project.id }
}

public enum DraftStage: String, Codable, CaseIterable, Sendable {
    case draft, revision, finished

    public var title: String {
        switch self {
        case .draft: "Borrador"
        case .revision: "En revisión"
        case .finished: "Terminado"
        }
    }
}

public struct WritingDocument: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var title: String
    public var markdown: String
    public var stage: DraftStage = .draft
    public var projectIDs: Set<UUID>
    public var tags: [String] = []
    public var modifiedAt = Date()
    public var trashedAt: Date?
    public var attachment: DocumentAttachment?
    public var fragments: [DocumentFragment]?
    public var pageLayout: WritingPageLayout?
    public var pageViews: WritingPageViews?
    public var plainText: Bool?
    public var richTextData: Data?
    public var richTextFormat: String?

    public init(title: String = "Sin título", markdown: String = "", projectIDs: Set<UUID> = []) {
        self.title = title
        self.markdown = markdown
        self.projectIDs = projectIDs
    }

    public var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Sin título" : trimmed
    }

    public var url: URL { ItemDestination(id).url }
    public var markdownLink: String { ItemDestination(id).markdownLink(label: displayTitle) }

    public static func documentID(for url: URL) -> UUID? {
        ItemDestination(url: url)?.documentID
    }

    public var linkTargets: Set<ItemDestination> {
        let linkPattern = /(thinkbox:\/\/document\/[0-9a-fA-F-]{36}(?:\?base=[0-9a-fA-F-]{36})?(?:#[0-9a-fA-F-]{36})?)/
        return Set(markdown.matches(of: linkPattern).compactMap { match in
            URL(string: String(match.1)).flatMap(ItemDestination.init(url:))
        })
    }

    public var linkedDocumentIDs: Set<UUID> { Set(linkTargets.map(\.documentID)) }

    public mutating func editMarkdown(_ text: String, replaced: NSRange, replacementLength: Int) {
        markdown = text
        guard var fragments else { return }
        for index in fragments.indices {
            if case .text(var anchor) = fragments[index].location {
                anchor.adjust(for: replaced, replacementLength: replacementLength, newText: text)
                fragments[index].location = .text(anchor)
            }
        }
        self.fragments = fragments
    }
}

public struct SavedSearch: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var name: String
    public var query: String

    public init(name: String, query: String) {
        self.name = name
        self.query = query
    }
}

public enum LibraryScope: Hashable, Codable {
    case all, inbox, drafts, trash, project(UUID), savedSearch(UUID), tag(String)
}

public struct WritingLibrary: Codable, Equatable, Sendable {
    public var formatVersion = 2
    public var projects: [Project] = []
    public var documents: [WritingDocument] = []
    public var savedSearches: [SavedSearch] = []
    public var catalogTags: [String]?
    public var tagSettings: TagSettings?

    public init() {}

    public var activeDocuments: [WritingDocument] { documents.filter { $0.trashedAt == nil } }

    /// Groups as a tree. A group whose parent is missing, or that would close a cycle, is shown
    /// at the top level so it never disappears.
    public var groupTree: [GroupBranch] {
        let known = Set(projects.map(\.id))
        let byParent = Dictionary(grouping: projects) { project -> UUID? in
            guard let parent = project.parentID, known.contains(parent), !ancestors(of: project.id).contains(project.id)
            else { return nil }
            return parent
        }
        func branches(under parent: UUID?) -> [GroupBranch] {
            (byParent[parent] ?? []).map { project in
                let children = branches(under: project.id)
                return GroupBranch(project: project, children: children.isEmpty ? nil : children)
            }
        }
        return branches(under: nil)
    }

    /// Parent chain of a group, nearest first; stops at a cycle.
    public func ancestors(of id: UUID) -> [UUID] {
        var chain: [UUID] = []
        var current = projects.first { $0.id == id }?.parentID
        while let parent = current, !chain.contains(parent), let project = projects.first(where: { $0.id == parent }) {
            chain.append(parent)
            if parent == id { break }
            current = project.parentID
        }
        return chain
    }

    /// «Padre › Hijo» name of a group, for lists that show every group flat.
    public func groupPath(of id: UUID) -> String {
        let chain = ([id] + ancestors(of: id).filter { $0 != id }).reversed()
        return chain.compactMap { group in projects.first { $0.id == group }?.name }.joined(separator: " › ")
    }

    /// Moves a group inside another (or to the top level with nil). Refuses moves into itself
    /// or into one of its own descendants.
    @discardableResult
    public mutating func moveGroup(_ id: UUID, into parent: UUID?) -> Bool {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return false }
        if let parent {
            guard parent != id, projects.contains(where: { $0.id == parent }),
                  !ancestors(of: parent).contains(id) else { return false }
        }
        projects[index].parentID = parent
        return true
    }

    public func documents(in scope: LibraryScope, matching query: String = "") -> [WritingDocument] {
        results(in: scope, matching: query).compactMap { $0.fragment == nil ? $0.document : nil }
    }

    public func results(in scope: LibraryScope, matching query: String = "") -> [LibraryResult] {
        let scoped: [WritingDocument]
        var criteria = [TagQuery(query)]
        switch scope {
        case .all:
            scoped = activeDocuments
        case .inbox:
            scoped = activeDocuments.filter { $0.projectIDs.isEmpty }
        case .drafts:
            scoped = activeDocuments.filter { $0.attachment == nil && $0.stage == .draft }
        case .trash:
            scoped = documents.filter { $0.trashedAt != nil }
        case .project(let id):
            scoped = activeDocuments.filter { $0.projectIDs.contains(id) }
        case .savedSearch(let id):
            guard let search = savedSearches.first(where: { $0.id == id }) else { return [] }
            scoped = activeDocuments
            criteria.append(TagQuery(search.query))
        case .tag(let tag):
            scoped = activeDocuments
            criteria.append(TagQuery(exactTag: tag))
        }
        let sorted = scoped.sorted {
            if $0.modifiedAt == $1.modifiedAt { return $0.id.uuidString < $1.id.uuidString }
            return $0.modifiedAt > $1.modifiedAt
        }
        let includeFragments = criteria.contains { !$0.isEmpty }
        if !includeFragments { return sorted.map { LibraryResult(document: $0, fragment: nil) } }
        return sorted.flatMap { document -> [LibraryResult] in
            let tags = effectiveTags(of: document)
            var matches: [LibraryResult] = []
            let body = document.attachment?.searchText ?? document.markdown
            if criteria.allSatisfy({ $0.matches(title: document.displayTitle, body: body, tags: tags) }) {
                matches.append(LibraryResult(document: document, fragment: nil))
            }
            for fragment in document.fragments ?? [] where criteria.allSatisfy({
                $0.matches(title: document.displayTitle, body: fragment.quote, tags: fragment.tags)
            }) {
                matches.append(LibraryResult(document: document, fragment: fragment))
            }
            return matches
        }
    }

    public func write(to url: URL) throws {
        let data = try JSONEncoder().encode(self)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    public static func read(from url: URL, requiresExistingFile: Bool = false) throws -> Self {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile && !requiresExistingFile {
            return Self()
        }
        var library = try JSONDecoder().decode(Self.self, from: data)
        guard (1...2).contains(library.formatVersion) else { throw LibraryError.unknownVersion(library.formatVersion) }
        library.formatVersion = 2
        return library
    }
}

private enum LibraryError: LocalizedError {
    case unknownVersion(Int)

    var errorDescription: String? {
        switch self {
        case .unknownVersion(let version): "La versión \(version) de esta biblioteca requiere otra versión de Think Box."
        }
    }
}
