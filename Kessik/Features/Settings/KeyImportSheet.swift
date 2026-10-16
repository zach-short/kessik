import SwiftUI
import UniformTypeIdentifiers

/// Imports an OpenSSH ed25519 or ECDSA private key, pasted or picked from Files, as the phone's SSH key.
/// The key text lives only in this sheet's state and is cleared when the key is saved or the sheet closes.
struct KeyImportSheet: View {
    /// Called with the new key's `authorized_keys` line after it is saved in the Keychain.
    let onImport: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var fileName: String?
    @State private var passphrase = ""
    @State private var needsPassphrase = false
    @State private var choosingFile = false
    @State private var working = false
    @State private var error: String?
    @State private var pending: DeviceKey.Key?
    @State private var confirmReplace = false

    /// Larger than any OpenSSH private key, so a wrong pick is not read into memory.
    private static let maxFileSize = 16 * 1024

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let fileName {
                        LabeledContent("File", value: fileName)
                        Button("Remove file", systemImage: "xmark.circle") { text = "" }
                    } else {
                        TextEditor(text: $text)
                            .font(Theme.mono)
                            .frame(minHeight: 180)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        Button("Choose a file", systemImage: "doc") { choosingFile = true }
                    }
                } header: {
                    Text("Private key")
                } footer: {
                    Text(error ?? "Paste the whole private key file, from -----BEGIN OPENSSH PRIVATE KEY----- to the END line, or choose the file. Ed25519 and ECDSA keys work.")
                        .foregroundStyle(error == nil ? Theme.textSecondary : Theme.accent)
                }
                if needsPassphrase {
                    Section {
                        SecureField("Passphrase", text: $passphrase)
                            .textContentType(.password)
                            .onSubmit(importKey)
                    } footer: {
                        Text("The passphrase only unlocks the key here. The app saves the key without it, in this phone's Keychain.")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Import SSH key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if working {
                        ProgressView()
                    } else {
                        Button("Import", action: importKey)
                            .disabled(text.isEmpty || (needsPassphrase && passphrase.isEmpty))
                    }
                }
            }
            .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.data]) { result in
                readFile(result)
            }
            .confirmationDialog("Replace the SSH key?", isPresented: $confirmReplace, titleVisibility: .visible) {
                Button("Replace key", role: .destructive) {
                    if let pending { save(pending) }
                }
                Button("Cancel", role: .cancel) { pending = nil }
            } message: {
                Text("Macs that have only the old key stop accepting this phone. Add the imported key to them if they do not have it.")
            }
            .onChange(of: text) {
                if text.isEmpty { fileName = nil }
                error = nil
                needsPassphrase = false
                passphrase = ""
            }
            .onDisappear(perform: clear)
        }
    }

    private func importKey() {
        let source = text
        let phrase = needsPassphrase ? passphrase : nil
        working = true
        error = nil
        Task {
            // The passphrase KDF (bcrypt) takes a moment, so it runs off the main thread.
            let result = await Task.detached { Result { try KeyImport.parse(source, passphrase: phrase) } }.value
            working = false
            switch result {
            case .success(let key):
                if DeviceKey.load() != nil {
                    pending = key
                    confirmReplace = true
                } else {
                    save(key)
                }
            case .failure(let failure as KeyImport.Failure) where failure == .passphraseNeeded:
                needsPassphrase = true
                error = failure.localizedDescription
            case .failure(let failure):
                error = failure.localizedDescription
            }
        }
    }

    private func save(_ key: DeviceKey.Key) {
        do {
            try DeviceKey.save(key)
            clear()
            onImport(DeviceKey.publicLine(for: key))
            dismiss()
        } catch {
            pending = nil
            self.error = error.localizedDescription
        }
    }

    /// Drops every copy of the key this sheet holds.
    private func clear() {
        text = ""
        passphrase = ""
        fileName = nil
        pending = nil
    }

    private func readFile(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= Self.maxFileSize, let contents = String(data: try Data(contentsOf: url), encoding: .utf8) else {
                throw KeyImport.Failure.notAKey
            }
            text = contents
            fileName = url.lastPathComponent
        } catch {
            self.error = error.localizedDescription
        }
    }
}
