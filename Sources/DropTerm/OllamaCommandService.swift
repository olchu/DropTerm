import Foundation

struct OllamaCommandService: Sendable {
    struct Model: Decodable, Identifiable, Sendable {
        let name: String
        let size: Int64
        var id: String { name }
    }

    enum ServiceError: LocalizedError {
        case invalidURL
        case unavailable
        case server(String)
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                "Invalid Ollama URL in Settings."
            case .unavailable:
                "Ollama is not running. Start it, then try again."
            case .server(let message):
                message
            case .emptyResponse:
                "The model returned an empty command."
            }
        }
    }

    let baseURL: String
    let model: String

    func installedModels() async throws -> [Model] {
        guard let url = endpoint("/api/tags") else { throw ServiceError.invalidURL }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw ServiceError.unavailable
            }
            return try JSONDecoder().decode(TagsResponse.self, from: data).models
        } catch let error as ServiceError {
            throw error
        } catch {
            throw ServiceError.unavailable
        }
    }

    func pullModel(
        _ model: String,
        progress: @MainActor @Sendable (Double?, String) -> Void
    ) async throws {
        guard let url = endpoint("/api/pull") else { throw ServiceError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60 * 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(PullRequest(model: model, stream: true))

        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await URLSession.shared.bytes(for: request)
        } catch {
            throw ServiceError.unavailable
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ServiceError.server("Ollama could not download model ‘\(model)’.")
        }

        for try await line in bytes.lines {
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let update = try? JSONDecoder().decode(PullUpdate.self, from: data) else { continue }
            if let error = update.error { throw ServiceError.server(error) }
            let fraction: Double? = if let completed = update.completed,
                                       let total = update.total,
                                       total > 0 {
                Double(completed) / Double(total)
            } else {
                nil
            }
            await progress(fraction, update.status ?? "Downloading…")
        }
    }

    func command(
        for request: String,
        workingDirectory: String,
        projectCandidates: [String] = [],
        commandContext: String? = nil
    ) async throws -> String {
        if let matchedProject = projectCandidates.first {
            return "cd -- \(Self.shellQuote(matchedProject))"
        }

        let isCommitRequest = Self.isCommitRequest(request)

        guard let url = endpoint("/api/generate") else {
            throw ServiceError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 120
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let generationPrompt: String = if isCommitRequest {
            """
            Write one concise Conventional Commit subject based only on the Git status and diff below.
            Output the subject only, not a shell command, quotes, Markdown, explanation, cd, git add, or git commit.
            Mention the concrete feature or fix and its main behavior. Maximum 72 characters.
            Forbidden vague wording: update project, project files, improvements, misc changes, various fixes.

            Git context:
            \(commandContext ?? "(no changes available)")

            User request: \(request)
            """
        } else {
            """
            Convert the user's request into one safe shell command for macOS zsh.
            Current working directory: \(workingDirectory)
            Known project directories that may match the user's wording:
            \(projectCandidates.isEmpty ? "(none found)" : projectCandidates.joined(separator: "\n"))
            Read-only command output collected from the current directory:
            \(commandContext ?? "(not needed for this request)")
            Return only the command, without Markdown fences, explanation, or a leading prompt symbol.
            Never execute anything. Prefer a non-destructive command when the request is ambiguous.
            Never return cd unless the user explicitly asks to navigate, open, or change directories.

            User request: \(request)
            """
        }
        urlRequest.httpBody = try JSONEncoder().encode(GenerateRequest(
            model: model,
            prompt: generationPrompt,
            stream: false
        ))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: urlRequest)
        } catch {
            throw ServiceError.unavailable
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.unavailable
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let serverError = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            let message = serverError?.error ?? "Ollama request failed (HTTP \(httpResponse.statusCode))."
            if message.localizedCaseInsensitiveContains("model") {
                throw ServiceError.server("Model ‘\(model)’ is unavailable. Run: ollama pull \(model)")
            }
            throw ServiceError.server(message)
        }

        let generated = try JSONDecoder().decode(GenerateResponse.self, from: data)
        let command = Self.clean(generated.response)
        guard !command.isEmpty else { throw ServiceError.emptyResponse }
        if isCommitRequest {
            let subject = Self.cleanCommitSubject(command)
            guard Self.isUsefulCommitSubject(subject) else {
                throw ServiceError.server("The model produced a vague commit message. Try a larger Ollama model.")
            }
            return "git add -A && git commit -m \(Self.shellQuote(subject))"
        }
        if Self.isChangeDirectoryCommand(command),
           let matchedProject = await ProjectDirectoryIndex.findMatches(
               for: request,
               currentDirectory: workingDirectory
           ).first {
            return "cd -- \(Self.shellQuote(matchedProject))"
        }
        return command
    }

    private func endpoint(_ path: String) -> URL? {
        let trimmedBaseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: trimmedBaseURL + path)
    }

    private static func clean(_ response: String) -> String {
        var value = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("```") {
            value = value
                .replacingOccurrences(of: "```zsh", with: "")
                .replacingOccurrences(of: "```bash", with: "")
                .replacingOccurrences(of: "```sh", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if value.count >= 2, value.first == "`", value.last == "`" {
            value.removeFirst()
            value.removeLast()
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return value
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func isChangeDirectoryCommand(_ command: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == "cd" || trimmed.hasPrefix("cd ")
    }

    private static func isCommitRequest(_ request: String) -> Bool {
        let value = request.lowercased()
        return value.contains("commit") || value.contains("коммит")
    }

    private static func cleanCommitSubject(_ response: String) -> String {
        var value = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("git commit"),
           let range = value.range(of: "-m") {
            value = String(value[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "`\"' "))
        return String(value.prefix(72))
    }

    private static func isUsefulCommitSubject(_ subject: String) -> Bool {
        let value = subject.lowercased()
        let forbidden = ["update project", "project files", "improvements", "misc changes", "various fixes", "/path/to/"]
        return subject.count >= 12
            && !value.contains("git commit")
            && !value.contains("git add")
            && !value.contains("cd ")
            && !forbidden.contains(where: value.contains)
    }

    private struct GenerateRequest: Encodable {
        let model: String
        let prompt: String
        let stream: Bool
    }

    private struct GenerateResponse: Decodable {
        let response: String
    }

    private struct ErrorResponse: Decodable {
        let error: String
    }

    private struct TagsResponse: Decodable {
        let models: [Model]
    }

    private struct PullRequest: Encodable {
        let model: String
        let stream: Bool
    }

    private struct PullUpdate: Decodable {
        let status: String?
        let completed: Int64?
        let total: Int64?
        let error: String?
    }
}

struct SafeCommandContext: Sendable {
    static func collect(for request: String, workingDirectory: String) async -> String? {
        guard isGitRequest(request) else { return nil }
        return await Task.detached(priority: .utility) {
            collectGitContext(workingDirectory: workingDirectory)
        }.value
    }

    private static func isGitRequest(_ request: String) -> Bool {
        let value = request.lowercased()
        return [
            "git", "commit", "коммит", "изменен", "изменён", "статус",
            "diff", "дифф", "ветк", "staged"
        ].contains { value.contains($0) }
    }

    private static func collectGitContext(workingDirectory: String) -> String? {
        let commands: [(title: String, arguments: [String])] = [
            ("git status", ["status", "--short", "--branch"]),
            ("unstaged changes", ["diff", "--no-ext-diff", "--stat"]),
            ("unstaged files", ["diff", "--no-ext-diff", "--name-status"]),
            ("unstaged patch", ["diff", "--no-ext-diff", "--unified=2"]),
            ("staged changes", ["diff", "--cached", "--no-ext-diff", "--stat"]),
            ("staged files", ["diff", "--cached", "--no-ext-diff", "--name-status"]),
            ("staged patch", ["diff", "--cached", "--no-ext-diff", "--unified=2"])
        ]
        var sections: [String] = []
        for command in commands {
            guard let output = runGit(command.arguments, in: workingDirectory), !output.isEmpty else { continue }
            sections.append("## \(command.title)\n\(output)")
        }
        return sections.isEmpty ? nil : sections.joined(separator: "\n\n")
    }

    private static func runGit(_ arguments: [String], in directory: String) -> String? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: directory, isDirectory: true)
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(decoding: data.prefix(32_000), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
}

struct ProjectDirectoryIndex: Sendable {
    static func matches(for query: String, currentDirectory: String) async -> [String] {
        guard isNavigationRequest(query) else { return [] }
        return await findMatches(for: query, currentDirectory: currentDirectory)
    }

    static func findMatches(for query: String, currentDirectory: String) async -> [String] {
        return await Task.detached(priority: .utility) {
            scan(query: query, currentDirectory: currentDirectory)
        }.value
    }

    private static func isNavigationRequest(_ query: String) -> Bool {
        let value = query
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        let navigationPhrases = [
            "перейди", "перейти", "зайди", "зайти", "открой проект", "открыть проект",
            "открой папку", "открыть папку", "cd ", "go to", "navigate", "open project",
            "open folder", "change directory"
        ]
        return navigationPhrases.contains { value.contains($0) }
    }

    private static func scan(query: String, currentDirectory: String) -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let currentURL = URL(fileURLWithPath: currentDirectory, isDirectory: true)
        let roots = uniqueExistingDirectories([
            home.appendingPathComponent("Documents/projects", isDirectory: true),
            home.appendingPathComponent("Projects", isDirectory: true),
            currentURL.deletingLastPathComponent(),
            currentURL
        ])
        let queryTerms = normalizedTerms(query)
        guard !queryTerms.isEmpty else { return [] }

        var scored: [(score: Int, path: String)] = []
        let skippedNames: Set<String> = [
            ".git", ".build", ".swiftpm", "node_modules", "Pods", "DerivedData",
            "build", "dist", ".next", ".cache", "vendor"
        ]

        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator {
                let relativeDepth = url.pathComponents.count - root.pathComponents.count
                if relativeDepth > 5 {
                    enumerator.skipDescendants()
                    continue
                }
                if skippedNames.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                    continue
                }
                guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                    continue
                }
                let score = matchScore(queryTerms: queryTerms, url: url)
                if score > 0 { scored.append((score, url.path)) }
            }
        }

        return scored
            .sorted { $0.score == $1.score ? $0.path.count < $1.path.count : $0.score > $1.score }
            .reduce(into: [String]()) { result, candidate in
                if result.count < 8, !result.contains(candidate.path) { result.append(candidate.path) }
            }
    }

    private static func uniqueExistingDirectories(_ urls: [URL]) -> [URL] {
        var paths = Set<String>()
        return urls.filter { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                && isDirectory.boolValue
                && paths.insert(url.standardizedFileURL.path).inserted
        }
    }

    private static func normalizedTerms(_ value: String) -> [String] {
        let ignored: Set<String> = [
            "перейти", "перейди", "открыть", "открой", "папка", "папку", "папке",
            "проект", "проекта", "проекте", "директория", "директорию", "найди",
            "please", "open", "change", "folder", "directory", "project", "find", "into"
        ]
        let original = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 3 && !ignored.contains($0) }

        return Array(Set(original.flatMap { term in
            let latin = transliterate(term)
            var variants = [term, latin]
            if latin.contains("veb") { variants.append(latin.replacingOccurrences(of: "veb", with: "web")) }
            return variants.filter { $0.count >= 3 }
        }))
    }

    private static func matchScore(queryTerms: [String], url: URL) -> Int {
        let nameTerms = normalizedTerms(url.lastPathComponent)
        let name = nameTerms.joined()
        let path = normalizedTerms(url.path).joined(separator: " ")
        var score = 0
        for term in queryTerms {
            if name == term { score += 120 }
            else if name.contains(term) || term.contains(name) { score += 75 }
            else if isSubsequence(term, of: name) { score += 40 }
            else if path.contains(term) { score += 18 }

            for nameTerm in nameTerms where nameTerm.count >= 3 {
                if term.contains(nameTerm) || nameTerm.contains(term) { score += 32 }
            }
        }
        return score
    }

    private static func transliterate(_ value: String) -> String {
        let mutable = NSMutableString(string: value)
        CFStringTransform(mutable, nil, kCFStringTransformToLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripCombiningMarks, false)
        return (mutable as String)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var index = needle.startIndex
        for character in haystack where index < needle.endIndex {
            if character == needle[index] { needle.formIndex(after: &index) }
        }
        return index == needle.endIndex
    }
}
