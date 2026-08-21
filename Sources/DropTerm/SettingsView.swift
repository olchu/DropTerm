import AppKit
import Carbon.HIToolbox
import Observation
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    @State private var ollama = OllamaSettingsController()

    var body: some View {
        Form {
            Section("Appearance") {
                sliderRow(
                    title: "Panel height",
                    value: $settings.panelHeightRatio,
                    range: 0.2...0.8,
                    valueLabel: settings.panelHeightRatio.formatted(.percent.precision(.fractionLength(0)))
                )
                sliderRow(
                    title: "Darkening",
                    value: $settings.backgroundOpacity,
                    range: 0...0.6,
                    valueLabel: settings.backgroundOpacity.formatted(
                        .percent.precision(.fractionLength(0))
                    )
                )
                sliderRow(
                    title: "Window blur",
                    value: $settings.backgroundBlurRadius,
                    range: 0...80,
                    valueLabel: "\(Int(settings.backgroundBlurRadius)) px"
                )
                sliderRow(
                    title: "Snippet blur",
                    value: $settings.snippetBlurRadius,
                    range: 0...80,
                    valueLabel: "\(Int(settings.snippetBlurRadius)) px"
                )
                sliderRow(
                    title: "Content padding",
                    value: $settings.contentPadding,
                    range: 0...40,
                    valueLabel: "\(Int(settings.contentPadding)) px"
                )
            }

            Section("Terminal") {
                Picker("Font", selection: $settings.fontName) {
                    Text("Automatic (MesloLGS NF preferred)").tag("Automatic")
                    Text("MesloLGS NF").tag("MesloLGS-NF-Regular")
                    Text("Menlo").tag("Menlo")
                    Text("Monaco").tag("Monaco")
                }
                sliderRow(
                    title: "Font size",
                    value: $settings.fontSize,
                    range: 10...28,
                    valueLabel: "\(Int(settings.fontSize)) pt"
                )
                Picker("Cursor style", selection: $settings.cursorShape) {
                    ForEach(AppSettings.CursorShape.allCases) { shape in
                        Text(shape.title).tag(shape)
                    }
                }
                Toggle("Blink cursor", isOn: $settings.cursorBlink)
                TextField("Shell", text: $settings.shellPath)
                LabeledContent("Starting folder") {
                    HStack(spacing: 8) {
                        TextField("~/Documents/projects", text: $settings.startingDirectory)
                            .frame(minWidth: 250)
                        Button("Choose…", action: chooseStartingDirectory)
                        Button {
                            settings.startingDirectory = FileManager.default
                                .homeDirectoryForCurrentUser.path
                        } label: {
                            Image(systemName: "house")
                        }
                        .help("Use home folder")
                    }
                }
                Text("Shell and starting folder changes apply to the next terminal session.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Behavior") {
                LabeledContent("Global shortcut") {
                    HotKeyRecorder(shortcut: $settings.globalShortcut)
                        .frame(width: 150, height: 28)
                }
                Toggle("Hide when focus moves to another app", isOn: $settings.hideOnDeactivate)
                Toggle("Show terminal when DropTerm launches", isOn: $settings.showOnLaunch)
            }

            Section("Local AI") {
                TextField("Ollama URL", text: $settings.ollamaURL)
                TextField("Model", text: $settings.ollamaModel)
                HStack(spacing: 10) {
                    Circle()
                        .fill(ollama.isServerRunning ? Color.green : Color.secondary)
                        .frame(width: 8, height: 8)
                    Text(ollama.status)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !ollama.isInstalled {
                        Button("Download Ollama") { ollama.downloadInstaller() }
                    } else if !ollama.isServerRunning {
                        Button("Launch Ollama") { ollama.launch(settings: settings) }
                    } else if !ollama.hasSelectedModel(settings.ollamaModel) {
                        Button("Download model") { ollama.pullSelectedModel(settings: settings) }
                            .disabled(ollama.isDownloading)
                    }
                    Button {
                        ollama.refresh(settings: settings)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh Ollama status")
                    .disabled(ollama.isDownloading)
                }
                if ollama.isDownloading {
                    if let progress = ollama.downloadProgress {
                        ProgressView(value: progress)
                    } else {
                        ProgressView()
                    }
                    Text(ollama.downloadStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !ollama.models.isEmpty {
                    Picker("Installed model", selection: $settings.ollamaModel) {
                        ForEach(ollama.models) { model in
                            Text("\(model.name) · \(ollama.formattedSize(model.size))")
                                .tag(model.name)
                        }
                    }
                }
                Text("Press ⌘K in the terminal. The generated command is inserted but never run automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 620, height: 520)
        .task { ollama.refresh(settings: settings) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            ollama.refresh(settings: settings)
        }
    }

    private func chooseStartingDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Choose Starting Folder"
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        let expandedPath = NSString(string: settings.startingDirectory).expandingTildeInPath
        if FileManager.default.fileExists(atPath: expandedPath) {
            panel.directoryURL = URL(fileURLWithPath: expandedPath, isDirectory: true)
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.startingDirectory = url.path
    }

    private func sliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        valueLabel: String
    ) -> some View {
        LabeledContent(title) {
            HStack {
                Slider(value: value, in: range)
                    .frame(width: 210)
                Text(valueLabel)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .trailing)
            }
        }
    }
}

@MainActor
@Observable
private final class OllamaSettingsController {
    var isInstalled = false
    var isServerRunning = false
    var isDownloading = false
    var downloadProgress: Double?
    var downloadStatus = ""
    var models: [OllamaCommandService.Model] = []
    var status = "Checking Ollama…"

    private var task: Task<Void, Never>?

    func refresh(settings: AppSettings) {
        task?.cancel()
        isInstalled = ollamaApplicationURL() != nil || ollamaCLIExists()
        status = isInstalled ? "Connecting to Ollama…" : "Ollama is not installed"
        task = Task {
            do {
                let service = OllamaCommandService(
                    baseURL: settings.ollamaURL,
                    model: settings.ollamaModel
                )
                let installed = try await service.installedModels()
                guard !Task.isCancelled else { return }
                models = installed.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                isServerRunning = true
                isInstalled = true
                status = models.isEmpty ? "Ollama is running · no models installed" : "Ollama is ready"
            } catch {
                guard !Task.isCancelled else { return }
                models = []
                isServerRunning = false
                status = isInstalled ? "Ollama is installed but not running" : "Ollama is not installed"
            }
        }
    }

    func downloadInstaller() {
        guard let url = URL(string: "https://ollama.com/download/mac") else { return }
        NSWorkspace.shared.open(url)
        status = "Install Ollama from the downloaded DMG, then return here"
    }

    func launch(settings: AppSettings) {
        guard let appURL = ollamaApplicationURL() else {
            downloadInstaller()
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { [weak self] _, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.status = "Could not launch Ollama: \(error.localizedDescription)"
                    return
                }
                self.status = "Starting Ollama…"
                try? await Task.sleep(for: .seconds(2))
                self.refresh(settings: settings)
            }
        }
    }

    func pullSelectedModel(settings: AppSettings) {
        let selectedModel = settings.ollamaModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selectedModel.isEmpty else { return }
        task?.cancel()
        isDownloading = true
        downloadProgress = nil
        downloadStatus = "Preparing \(selectedModel)…"
        task = Task {
            do {
                let service = OllamaCommandService(
                    baseURL: settings.ollamaURL,
                    model: selectedModel
                )
                try await service.pullModel(selectedModel) { [weak self] progress, status in
                    self?.downloadProgress = progress
                    self?.downloadStatus = status
                }
                guard !Task.isCancelled else { return }
                isDownloading = false
                downloadProgress = 1
                downloadStatus = "Model installed"
                refresh(settings: settings)
            } catch {
                guard !Task.isCancelled else { return }
                isDownloading = false
                downloadProgress = nil
                downloadStatus = error.localizedDescription
            }
        }
    }

    func hasSelectedModel(_ name: String) -> Bool {
        models.contains { $0.name == name || $0.name == name + ":latest" }
    }

    func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func ollamaApplicationURL() -> URL? {
        let fileManager = FileManager.default
        let candidates = [
            URL(fileURLWithPath: "/Applications/Ollama.app"),
            fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications/Ollama.app")
        ]
        return candidates.first { fileManager.fileExists(atPath: $0.path) }
    }

    private func ollamaCLIExists() -> Bool {
        FileManager.default.isExecutableFile(atPath: "/usr/local/bin/ollama")
            || FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/ollama")
    }
}

private struct HotKeyRecorder: NSViewRepresentable {
    @Binding var shortcut: GlobalShortcut

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.onShortcut = { shortcut = $0 }
        return button
    }

    func updateNSView(_ button: RecorderButton, context: Context) {
        button.shortcut = shortcut
        button.onShortcut = { shortcut = $0 }
    }
}

private final class RecorderButton: NSButton {
    var shortcut: GlobalShortcut = .defaultShortcut { didSet { refreshTitle() } }
    var onShortcut: ((GlobalShortcut) -> Void)?
    private var isRecording = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        target = self
        action = #selector(beginRecording)
        refreshTitle()
    }

    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { true }

    @objc private func beginRecording() {
        isRecording = true
        title = "Press shortcut…"
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return super.keyDown(with: event) }
        if event.keyCode == UInt16(kVK_Escape) {
            isRecording = false
            refreshTitle()
            return
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbonModifiers: UInt32 = 0
        if flags.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
        if flags.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
        if flags.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if flags.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        guard carbonModifiers != 0 else {
            NSSound.beep()
            return
        }

        shortcut = GlobalShortcut(keyCode: UInt32(event.keyCode), modifiers: carbonModifiers)
        isRecording = false
        refreshTitle()
        onShortcut?(shortcut)
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        refreshTitle()
        return super.resignFirstResponder()
    }

    private func refreshTitle() {
        guard !isRecording else { return }
        title = shortcut.displayName
    }
}
