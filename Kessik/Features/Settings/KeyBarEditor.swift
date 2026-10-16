import SwiftUI

/// Add, remove and reorder the keys after the arrows on the key bar.
struct KeyBarEditor: View {
    @State private var keys = KeyBarKeys.load()
    @State private var confirmReset = false

    var body: some View {
        List {
            Section {
                ForEach(keys) { key in
                    row(key)
                }
                .onDelete { keys.remove(atOffsets: $0) }
                .onMove { keys.move(fromOffsets: $0, toOffset: $1) }
                .deleteDisabled(keys.count == 1)
            } header: {
                Text("On the bar")
            } footer: {
                Text("The bar shows these keys after the arrows, in this order. It holds up to \(KeyBarKeys.maxCount) keys.")
            }

            Section("Add a key") {
                ForEach(available) { key in
                    Button {
                        keys.append(key)
                    } label: {
                        HStack {
                            row(key)
                            Spacer()
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    .disabled(keys.count >= KeyBarKeys.maxCount)
                }
            }

            Section {
                Button("Reset to default", role: .destructive) { confirmReset = true }
                    .disabled(keys.map(\.id) == KeyBarKeys.defaultIDs)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Key bar")
        .toolbar { EditButton() }
        .onChange(of: keys) { KeyBarKeys.save(keys) }
        .confirmationDialog("Reset the key bar?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset to default", role: .destructive) {
                KeyBarKeys.reset()
                keys = KeyBarKeys.load()
            }
        } message: {
            Text(verbatim: "The bar goes back to " + KeyBarKeys.defaultIDs.joined(separator: " "))
        }
    }

    private var available: [ExtraKey] {
        ExtraKey.all.filter { !keys.contains($0) }
    }

    private func row(_ key: ExtraKey) -> some View {
        HStack(spacing: 12) {
            Text(key.title)
                .font(Theme.mono)
                .foregroundStyle(Theme.textPrimary)
                .frame(minWidth: 40, alignment: .leading)
            Text(key.label)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

#Preview {
    NavigationStack { KeyBarEditor() }
        .preferredColorScheme(.dark)
}
