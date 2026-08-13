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
}
