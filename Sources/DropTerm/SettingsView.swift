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
                    valueLabel: settings.backgroundOpacity.formatted(.percent.precision(.fractionLength(0)))
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
                Text("Changing the shell takes effect after restarting DropTerm.")
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
        .frame(width: 520, height: 480)
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
