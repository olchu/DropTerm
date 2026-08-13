import Foundation

struct CommandSnippet: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var command: String

    init(id: UUID = UUID(), name: String, command: String) {
        self.id = id
        self.name = name
        self.command = command
    }
}

struct SnippetGroup: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var snippets: [CommandSnippet]

    init(id: UUID = UUID(), name: String, snippets: [CommandSnippet] = []) {
        self.id = id
        self.name = name
        self.snippets = snippets
    }
}

@MainActor
final class SnippetStore {
    private static let storageKey = "snippets.groups"

    private(set) var groups: [SnippetGroup]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        groups = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode([SnippetGroup].self, from: $0) }
            ?? []
    }

    func addGroup(named name: String) {
        groups.append(SnippetGroup(name: name))
        persist()
    }

    func removeGroup(id: UUID) {
        groups.removeAll { $0.id == id }
        persist()
    }

    func renameGroup(id: UUID, to name: String) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].name = name
        persist()
    }

    func addSnippet(name: String, command: String, to groupID: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return }
        groups[index].snippets.append(CommandSnippet(name: name, command: command))
        persist()
    }

    func removeSnippet(id: UUID, from groupID: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return }
        groups[index].snippets.removeAll { $0.id == id }
        persist()
    }

    func updateSnippet(id: UUID, in groupID: UUID, name: String, command: String) {
        guard let groupIndex = groups.firstIndex(where: { $0.id == groupID }),
              let snippetIndex = groups[groupIndex].snippets.firstIndex(where: { $0.id == id }) else {
            return
        }
        groups[groupIndex].snippets[snippetIndex].name = name
        groups[groupIndex].snippets[snippetIndex].command = command
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(groups) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
