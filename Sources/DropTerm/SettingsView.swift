import AppKit
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
                LabeledContent("Global shortcut", value: "⇧⌘E")
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
