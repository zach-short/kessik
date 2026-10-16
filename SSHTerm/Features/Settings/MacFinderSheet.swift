import SwiftUI

/// Lists the Macs on this Wi-Fi that have Remote Login on. Picking one fills the Mac fields in
/// Settings. The username stays empty, because Bonjour does not announce it.
struct MacFinderSheet: View {
    var onPick: (MacFinder.Found) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var finder = MacFinder()
    @State private var waited = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(finder.found) { mac in
                        Button {
                            onPick(mac)
                            dismiss()
                        } label: {
                            row(mac)
                        }
                        .disabled(mac.hostname == nil)
                    }
                    if finder.found.isEmpty {
                        status
                    }
                } footer: {
                    Text("A Mac shows here when Remote Login is on and it uses the same Wi-Fi as this phone.")
                }
                .listRowBackground(Theme.surface)

                if finder.found.isEmpty, waited || finder.problem != nil {
                    Section {
                        NavigationLink {
                            GuideView(guide: .connectMac, from: .settings)
                        } label: {
                            Label("How to connect to a Mac", systemImage: "questionmark.circle")
                        }
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Macs on this Wi-Fi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                finder.start()
                try? await Task.sleep(for: .seconds(6))
                waited = true
            }
            .onDisappear { finder.stop() }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.background)
    }

    @ViewBuilder
    private var status: some View {
        if let problem = finder.problem {
            Label(problem, systemImage: "exclamationmark.triangle")
                .font(.subheadline)
                .foregroundStyle(Theme.warning)
        } else if waited {
            Text("No Macs found. Turn on Remote Login on the Mac, and join the same Wi-Fi.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        } else {
            HStack(spacing: 10) {
                ProgressView()
                Text("Searching…")
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func row(_ mac: MacFinder.Found) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "laptopcomputer")
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(mac.name)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if let hostname = mac.hostname {
                    Text(mac.port == 22 ? hostname : "\(hostname):\(mac.port)")
                        .font(Theme.mono)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("Finding its address…")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .contentShape(Rectangle())
    }
}
