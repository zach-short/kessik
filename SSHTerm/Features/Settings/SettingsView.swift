import SwiftUI

enum SettingsKey {
    static let terminalFontSize = "terminalFontSize"
    static let hapticsEnabled = "hapticsEnabled"
}

struct SettingsView: View {
    @AppStorage(SettingsKey.terminalFontSize) private var fontSize = 13.0
    @AppStorage(SettingsKey.hapticsEnabled) private var hapticsEnabled = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Terminal") {
                    Stepper(value: $fontSize, in: 9...24, step: 1) {
                        HStack {
                            Text("Text size")
                            Spacer()
                            Text("\(Int(fontSize)) pt")
                                .font(Theme.mono)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    Text("claude --continue")
                        .font(.system(size: fontSize, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                }

                Section("Feedback") {
                    Toggle("Haptics on key taps", isOn: $hapticsEnabled)
                }

                Section {
                    LabeledContent("Version", value: Bundle.main.shortVersion)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Settings")
        }
    }
}

private extension Bundle {
    var shortVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
    }
}

#Preview {
    SettingsView()
        .preferredColorScheme(.dark)
}
