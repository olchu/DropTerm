import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            LabeledContent("Working shortcut", value: "⌥ Space")
            LabeledContent("Panel height", value: "40%")
            LabeledContent("Preferred font", value: "MesloLGS NF")
            Text("Editable settings arrive in Phase 2 after the terminal session is functional.")
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 240)
        .padding()
    }
}

