import Foundation
import Testing
@testable import DropTerm

@MainActor
@Suite("Snippet store")
struct SnippetStoreTests {
    @Test("Groups and commands persist")
    func persistence() throws {
        let suiteName = "DropTermTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SnippetStore(defaults: defaults)
        store.addGroup(named: "Git")
        let groupID = try #require(store.groups.first?.id)
        store.addSnippet(name: "Status", command: "git status", to: groupID)

        let restored = SnippetStore(defaults: defaults)
        #expect(restored.groups.count == 1)
        #expect(restored.groups.first?.name == "Git")
        #expect(restored.groups.first?.snippets.first?.name == "Status")
        #expect(restored.groups.first?.snippets.first?.command == "git status")
    }

    @Test("Groups and commands can be removed")
    func removal() throws {
        let suiteName = "DropTermTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SnippetStore(defaults: defaults)
        store.addGroup(named: "Docker")
        let groupID = try #require(store.groups.first?.id)
        store.addSnippet(name: "Containers", command: "docker ps", to: groupID)
        let snippetID = try #require(store.groups.first?.snippets.first?.id)

        store.removeSnippet(id: snippetID, from: groupID)
        #expect(store.groups.first?.snippets.isEmpty == true)

        store.removeGroup(id: groupID)
        #expect(store.groups.isEmpty)
    }

    @Test("Groups and commands can be renamed and edited")
    func editing() throws {
        let suiteName = "DropTermTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SnippetStore(defaults: defaults)
        store.addGroup(named: "Old group")
        let groupID = try #require(store.groups.first?.id)
        store.addSnippet(name: "Old snippet", command: "echo old", to: groupID)
        let snippetID = try #require(store.groups.first?.snippets.first?.id)

        store.renameGroup(id: groupID, to: "New group")
        store.updateSnippet(
            id: snippetID,
            in: groupID,
            name: "New snippet",
            command: "echo first\necho second"
        )

        let restored = SnippetStore(defaults: defaults)
        #expect(restored.groups.first?.name == "New group")
        #expect(restored.groups.first?.snippets.first?.name == "New snippet")
        #expect(restored.groups.first?.snippets.first?.command == "echo first\necho second")
    }
}
