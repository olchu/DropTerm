import SwiftUI

struct TerminalPlaceholderView: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)

            VStack(alignment: .leading) {
                HStack {
                    Circle().fill(.red.opacity(0.8)).frame(width: 10, height: 10)
                    Circle().fill(.yellow.opacity(0.8)).frame(width: 10, height: 10)
                    Circle().fill(.green.opacity(0.8)).frame(width: 10, height: 10)
                    Spacer()
                    Text("DropTerm prototype")
                        .foregroundStyle(.secondary)
                }

                Text("❯ Terminal engine and PTY are the next milestone")
                    .font(.system(size: 15, design: .monospaced))
                    .foregroundStyle(.primary)

                Spacer()
            }
            .padding(18)
        }
        .preferredColorScheme(.dark)
    }
}

