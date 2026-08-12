import AppKit
import Carbon.HIToolbox
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings

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
                    title: "App transparency",
                    value: $settings.panelOpacity,
                    range: 0.45...1,
                    valueLabel: settings.panelOpacity.formatted(
                        .percent.precision(.fractionLength(0))
                    )
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
        }
        .formStyle(.grouped)
        .frame(width: 620, height: 520)
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
