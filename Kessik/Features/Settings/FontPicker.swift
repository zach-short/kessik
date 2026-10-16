import SwiftUI
import UniformTypeIdentifiers

/// The mono fonts, each shown in its own face. A choice applies to open terminals at once.
/// "Add font" copies monospaced TTF or OTF files from Files into the app.
struct FontPicker: View {
    @AppStorage(SettingsKey.monoFont) private var family = MonoFont.defaultFamily
    @State private var imported = MonoFont.imported
    @State private var importing = false
    @State private var status: String?

    var body: some View {
        List {
            Section("Built into iOS") {
                ForEach(MonoFont.builtIn) { row($0) }
            }
            Section("Included with Kessik") {
                ForEach(MonoFont.bundled) { row($0) }
            }
            Section {
                ForEach(imported) { row($0) }
                    .onDelete { offsets in offsets.map { imported[$0] }.forEach(remove) }
                Button("Add font", systemImage: "plus") { importing = true }
            } header: {
                Text("Your fonts")
            } footer: {
                Text(status ?? "Add a monospaced TTF or OTF file from Files. Add the bold and italic files of the family too, or the terminal shows bold and italic text in the regular face. Swipe left on a font to remove it.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Font")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.font], allowsMultipleSelection: true) { result in
            add(result)
        }
    }

    private var selected: String { MonoFont.named(family).family }

    private func row(_ font: MonoFont) -> some View {
        Button { family = font.family } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(font.family)
                        .font(font.font(.body))
                        .foregroundStyle(Theme.textPrimary)
                    Text("~/Projects $ claude --continue")
                        .font(font.font(.caption))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if font.family == selected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(font.family == selected ? .isSelected : [])
    }

    private func add(_ result: Result<[URL], Error>) {
        do {
            let added = try FontLibrary.add(try result.get())
            imported = MonoFont.imported
            if let first = added.first {
                family = first
                status = added.count == 1 ? "Added \(first)." : "Added \(added.joined(separator: ", "))."
            }
        } catch {
            status = error.localizedDescription
        }
    }

    private func remove(_ font: MonoFont) {
        FontLibrary.remove(family: font.family)
        imported = MonoFont.imported
        if family == font.family { family = MonoFont.defaultFamily }
        status = "Removed \(font.family)."
    }
}

#Preview {
    NavigationStack { FontPicker() }
        .preferredColorScheme(.dark)
}
