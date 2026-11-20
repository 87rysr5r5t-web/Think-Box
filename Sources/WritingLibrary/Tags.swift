import Foundation

public struct TagSettings: Codable, Equatable {
    public var projectNames = false
    public var inheritProjectTags = false
    public var hashtags = false
    public var finderTags = true
    public var pdfKeywords = false

    public init() {}
}

public struct TagBranch: Identifiable {
    public let id: String
    public let name: String
    public let children: [TagBranch]?
}

public enum TagPath {
    public static func normalize(_ text: String) -> String {
        text.split(separator: "/").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.joined(separator: "/")
    }

    public static func list(_ text: String) -> [String] {
        unique(text.split(separator: ",").map(String.init))
    }

    public static func unique(_ paths: [String]) -> [String] {
        var seen: Set<String> = []
        return paths.map(normalize).filter { !$0.isEmpty && seen.insert(key($0)).inserted }
    }

    static func key(_ path: String) -> String { path.lowercased().precomposedStringWithCanonicalMapping }

    public static func includes(_ assignment: String, tag: String) -> Bool {
        let assignment = key(normalize(assignment))
        let tag = key(normalize(tag))
        return !tag.isEmpty && (assignment == tag || assignment.hasPrefix(tag + "/"))
    }

    static func ancestors(of path: String) -> [String] {
        let parts = normalize(path).split(separator: "/")
        return parts.indices.map { parts.prefix($0 + 1).joined(separator: "/") }
    }
}

struct TagQuery {
    let tags: [String]
    let words: [String]

    var isEmpty: Bool { tags.isEmpty && words.isEmpty }

    init(exactTag: String) {
        tags = [exactTag]
        words = []
    }

    init(_ query: String) {
        let pattern = /(?:^|\s)tag:(?:"([^"]+)"|([^\s"]+))/
        tags = query.matches(of: pattern).compactMap { match in (match.1 ?? match.2).map(String.init) }
        words = query.replacing(pattern, with: " ").split(whereSeparator: \.isWhitespace).map(String.init)
    }

    func matches(title: String, body: String, tags assignments: [String]) -> Bool {
        tags.allSatisfy { tag in assignments.contains { TagPath.includes($0, tag: tag) } }
            && words.allSatisfy { word in
                title.localizedStandardContains(word) || body.localizedStandardContains(word)
                    || assignments.contains { $0.localizedStandardContains(word) }
            }
    }
}

public extension WritingLibrary {
    var tagging: TagSettings { tagSettings ?? TagSettings() }

    func effectiveTags(of document: WritingDocument) -> [String] {
        var tags = document.tags
        if tagging.projectNames || tagging.inheritProjectTags {
            for project in projects where document.projectIDs.contains(project.id) && project.excludedFromTagging != true {
                if tagging.projectNames { tags.append(project.name.replacingOccurrences(of: "/", with: "∕")) }
                if tagging.inheritProjectTags { tags.append(contentsOf: project.tags ?? []) }
            }
        }
        if tagging.hashtags && document.attachment == nil {
            let pattern = /#([\p{L}\p{N}_\/-]+)/
            for line in document.markdown.split(whereSeparator: \.isNewline) {
                let tokens = line.split(whereSeparator: \.isWhitespace)
                let matches = tokens.compactMap { $0.wholeMatch(of: pattern) }
                if tokens.count == matches.count { tags.append(contentsOf: matches.map { String($0.1) }) }
            }
        }
        return TagPath.unique(tags)
    }

    var availableTags: [String] {
        let projectTags = projects.flatMap { $0.tags ?? [] }
        let assigned = activeDocuments.flatMap { document in
            effectiveTags(of: document) + (document.fragments ?? []).flatMap(\.tags)
        }
        return TagPath.unique(((catalogTags ?? []) + projectTags + assigned).flatMap(TagPath.ancestors))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var tagTree: [TagBranch] {
        let children = Dictionary(grouping: availableTags) { path in
            TagPath.key(path.split(separator: "/").dropLast().joined(separator: "/"))
        }
        func branches(of parent: String) -> [TagBranch] {
            (children[TagPath.key(parent)] ?? []).map { path in
                let descendants = branches(of: path)
                return TagBranch(id: path, name: String(path.split(separator: "/").last ?? ""),
                                 children: descendants.isEmpty ? nil : descendants)
            }
        }
        return branches(of: "")
    }

    mutating func createTag(_ name: String) {
        catalogTags = TagPath.unique((catalogTags ?? []) + [name])
    }

    mutating func replaceTag(_ oldPath: String, with newPath: String?) {
        let depth = oldPath.split(separator: "/").count
        func update(_ tags: [String]) -> [String] {
            TagPath.unique(tags.compactMap { tag in
                guard TagPath.includes(tag, tag: oldPath) else { return tag }
                guard let newPath else { return nil }
                return ([newPath] + tag.split(separator: "/").dropFirst(depth).map(String.init)).joined(separator: "/")
            })
        }
        catalogTags = update(catalogTags ?? [])
        for index in projects.indices {
            projects[index].tags = projects[index].tags.map(update)
        }
        for index in documents.indices {
            documents[index].tags = update(documents[index].tags)
            if var fragments = documents[index].fragments {
                for fragment in fragments.indices { fragments[fragment].tags = update(fragments[fragment].tags) }
                documents[index].fragments = fragments
            }
        }
    }
}
