import SwiftUI
import UniformTypeIdentifiers

/// The Terminal colors picker, with imported palettes after the built-ins, and a link to import
/// or delete them. The swatch comes from Settings so both lists draw palettes the same way.
struct TerminalColorsPicker<Swatch: View>: View {
    @Binding var paletteID: String
    let swatch: (TerminalPalette.Colors) -> Swatch
    /// Read so the picker updates when a palette is imported or deleted.
    @AppStorage(CustomPalettes.key) private var stored = Data()
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let imported = CustomPalettes.decode(stored)
        Picker("Terminal colors", selection: $paletteID) {
            ForEach(TerminalPalette.all + imported) { palette in
                HStack(spacing: 10) {
                    swatch(palette.colors(dark: colorScheme == .dark))
                    Text(palette.name)
                }
                .tag(palette.id)
            }
        }
        .pickerStyle(.navigationLink)
        NavigationLink {
            ImportedPalettesView(swatch: swatch)
        } label: {
            LabeledContent("Imported colors", value: "\(imported.count)")
        }
    }
}

/// Imports `.itermcolors` themes from Files or from pasted text, and deletes them.
private struct ImportedPalettesView<Swatch: View>: View {
    let swatch: (TerminalPalette.Colors) -> Swatch
    @AppStorage(CustomPalettes.key) private var stored = Data()
    @AppStorage(SettingsKey.terminalPalette) private var paletteID = TerminalPalette.defaultID
    @State private var importing = false
    @State private var pasting = false
    @State private var status: String?

    var body: some View {
        List {
            Section {
                ForEach(CustomPalettes.decode(stored)) { palette in
                    HStack(spacing: 10) {
                        swatch(palette.dark)
                        Text(palette.name)
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
                .onDelete { offsets in
                    let palettes = CustomPalettes.decode(stored)
                    offsets.map { palettes[$0].id }.forEach { CustomPalettes().delete(id: $0) }
                    status = nil
                }
                Button("Choose a file", systemImage: "doc") { importing = true }
                Button("Paste a theme", systemImage: "doc.on.clipboard") { pasting = true }
            } footer: {
                Text(status ?? "Import an iTerm2 color preset (.itermcolors). Many terminal theme sites offer one. Swipe left on a theme to delete it.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Imported colors")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data]) { result in
            importFile(result)
        }
        .sheet(isPresented: $pasting) {
            PasteThemeForm { name in
                status = "Added \(name)."
            }
        }
    }

    /// Any file can be picked, because iOS has no type for .itermcolors. `parse` rejects the rest.
    private func importFile(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= CustomPalettes.maxFileSize else { throw CustomPalettes.ImportError.tooLarge }
            let name = String(url.deletingPathExtension().lastPathComponent.prefix(CustomPalettes.maxNameLength))
            let palette = try CustomPalettes().add(name: name, data: Data(contentsOf: url))
            paletteID = palette.id
            status = "Added \(palette.name)."
        } catch {
            status = error.localizedDescription
        }
    }
}

/// A name and the text of an .itermcolors file, for themes copied from a web page.
private struct PasteThemeForm: View {
    let onAdd: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.terminalPalette) private var paletteID = TerminalPalette.defaultID
    @State private var name = ""
    @State private var text = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                }
                Section {
                    TextEditor(text: $text)
                        .font(Theme.mono)
                        .frame(minHeight: 200)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Theme file")
                } footer: {
                    Text(error ?? "Paste the whole file, from <?xml to </plist>.")
                        .foregroundStyle(error == nil ? Theme.textSecondary : Theme.accent)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Paste a theme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import", action: add)
                        .disabled(text.isEmpty)
                }
            }
        }
    }

    private func add() {
        do {
            let palette = try CustomPalettes().add(name: name, data: Data(text.utf8))
            paletteID = palette.id
            onAdd(palette.name)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
