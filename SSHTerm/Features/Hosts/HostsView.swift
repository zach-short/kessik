import SwiftUI

struct HostsView: View {
    @Environment(AppStore.self) private var store
    @State private var command = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    CommandBar(text: $command)
                        .padding(.bottom, 8)

                    SectionLabel("Hosts")
                    ForEach(store.hosts) { host in
                        HostCard(host: host)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Hosts")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add host", systemImage: "plus") {}
                }
            }
        }
    }
}

struct HostCard: View {
    var host: Host

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "laptopcomputer")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 40, height: 40)
                .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(host.name)
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    StatusDot(status: host.status)
                }
                Text(host.address)
                    .font(Theme.mono)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let last = host.lastConnected {
                Text(last, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(14)
        .card()
        .contentShape(Rectangle())
    }
}

struct SectionLabel: View {
    var text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(Theme.textTertiary)
            .padding(.top, 4)
    }
}

#Preview {
    HostsView()
        .environment(AppStore.preview)
        .preferredColorScheme(.dark)
}
