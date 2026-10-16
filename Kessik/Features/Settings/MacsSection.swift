import SwiftUI

/// The saved Macs. A tap on a Mac makes the Sessions tab use it, the info button edits it, and a
/// swipe deletes it. With no Mac saved yet, the form for the first one shows here.
struct MacsSection: View {
    @Environment(AppStore.self) private var store
    @Environment(MacLink.self) private var link
    @State private var editing: Host?
    @State private var adding = false
    @State private var pendingDelete: Host?

    var body: some View {
        if store.hosts.isEmpty {
            MacForm(editing: nil)
        } else {
            Section {
                ForEach(store.hosts) { host in
                    row(host)
                }
                .onDelete { offsets in
                    pendingDelete = offsets.first.map { store.hosts[$0] }
                }
                Button("Add Mac", systemImage: "plus") { adding = true }
            } header: {
                Text("Macs")
            } footer: {
                Text(footer)
            }
            .sheet(item: $editing) { host in MacFormSheet(editing: host) }
            .sheet(isPresented: $adding) { MacFormSheet(editing: nil) }
            .confirmationDialog("Delete \(pendingDelete?.name ?? "Mac")?", isPresented: deleting,
                                titleVisibility: .visible, presenting: pendingDelete) { host in
                Button("Delete", role: .destructive) { delete(host) }
            } message: { host in
                Text(deleteMessage(host))
            }
        }
    }

    private func row(_ host: Host) -> some View {
        let active = host.id == store.activeMac?.id
        return HStack(spacing: 12) {
            Button {
                use(host)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .opacity(active ? 1 : 0)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(host.name)
                            .foregroundStyle(Theme.textPrimary)
                        Text(host.address)
                            .font(Theme.mono)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityAddTraits(active ? .isSelected : [])
            Button {
                editing = host
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Edit \(host.name)")
        }
    }

    private var deleting: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private var footer: String {
        if store.hosts.count > 1, link.state == .connected {
            return "The Sessions tab uses the checked Mac. Picking another Mac disconnects from \(link.host.hostname)."
        }
        return "The Sessions tab uses the checked Mac."
    }

    private func deleteMessage(_ host: Host) -> String {
        var text = "The app forgets this Mac's address"
        text += store.macs.sharesLogin(with: host) ? "." : " and its saved password."
        if host.id == store.activeMac?.id, link.state == .connected {
            text += " Its open terminals close."
        }
        return text
    }

    private func use(_ host: Host) {
        store.useMac(host)
        link.use(store.activeMac ?? .unset)
    }

    private func delete(_ host: Host) {
        let wasActive = host.id == store.activeMac?.id
        store.removeMac(host)
        if wasActive { link.use(store.activeMac ?? .unset) }
        pendingDelete = nil
    }
}

/// Adds or edits one Mac on its own screen.
private struct MacFormSheet: View {
    var editing: Host?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                MacForm(editing: editing) { dismiss() }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(editing == nil ? "Add Mac" : "Edit Mac")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

/// Where the app logs in: name, hostname, port and username. Edits apply on Save, so typing
/// does not drop the connection on each key. A new Mac becomes the active one; an edit keeps
/// the active Mac as it was.
private struct MacForm: View {
    var editing: Host?
    var onSaved: () -> Void = {}

    @Environment(AppStore.self) private var store
    @Environment(MacLink.self) private var link
    @State private var name = ""
    @State private var hostname = ""
    @State private var port = ""
    @State private var username = ""
    @State private var finding = false
    @State private var foundNote = false
    @State private var loaded = false
    /// The id a new Mac gets, so each new Mac has its own.
    @State private var newID = UUID()

    var body: some View {
        Section {
            Button("Find Macs on this Wi-Fi", systemImage: "wifi") { finding = true }
            field("Name", prompt: "Mac", text: $name)
            field("Hostname", prompt: "mac.tailnet.ts.net", text: $hostname, keyboard: .URL)
            field("Port", prompt: "22", text: $port, keyboard: .numberPad)
            field("Username", prompt: "whoami on the Mac", text: $username)
            Button("Save") { save() }
                .disabled(draft == nil || !changed)
        } header: {
            Text("Mac")
        } footer: {
            Text(LocalizedStringKey(footer))
        }
        .onAppear(perform: load)
        .sheet(isPresented: $finding) { MacFinderSheet(onPick: fill) }
    }

    /// Bonjour gives the name, hostname and port. The username stays as typed.
    private func fill(_ mac: MacFinder.Found) {
        guard let found = mac.hostname else { return }
        name = mac.name
        hostname = found
        port = mac.port == 22 ? "" : String(mac.port)
        foundNote = true
    }

    private func field(_ label: String, prompt: String, text: Binding<String>,
                       keyboard: UIKeyboardType = .default) -> some View {
        LabeledContent(label) {
            TextField(label, text: text, prompt: Text(prompt))
                .multilineTextAlignment(.trailing)
                .font(Theme.mono)
                .foregroundStyle(Theme.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(keyboard)
        }
    }

    private var trimmedHostname: String { hostname.trimmingCharacters(in: .whitespaces) }
    private var trimmedUsername: String { username.trimmingCharacters(in: .whitespaces) }

    private var portNumber: Int? {
        let text = port.trimmingCharacters(in: .whitespaces)
        if text.isEmpty { return 22 }
        return Int(text).flatMap { (1...65535).contains($0) ? $0 : nil }
    }

    private var hostnameProblem: String? {
        if trimmedHostname.contains(where: \.isWhitespace) { return "The hostname cannot have spaces." }
        if trimmedHostname.contains("@") { return "Put the username in its own field." }
        return nil
    }

    /// Saving a new Mac or the active one changes the Mac the Sessions tab uses.
    private var activates: Bool { editing == nil || editing?.id == store.activeMac?.id }

    /// The host to save, or nil while a field is empty or not valid.
    private var draft: Host? {
        guard !trimmedHostname.isEmpty, !trimmedUsername.isEmpty, hostnameProblem == nil,
              !trimmedUsername.contains(where: \.isWhitespace), let portNumber else { return nil }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        var host = editing ?? Host(id: newID, name: "", hostname: "", username: "")
        host.name = trimmedName.isEmpty ? "Mac" : trimmedName
        host.hostname = trimmedHostname
        host.port = portNumber
        host.username = trimmedUsername
        return host
    }

    private var changed: Bool {
        guard let draft else { return false }
        guard let editing else { return true }
        return !draft.sameLogin(as: editing) || draft.name != editing.name
    }

    private var footer: String {
        if let hostnameProblem { return hostnameProblem }
        if portNumber == nil { return "The port is a number from 1 to 65535." }
        if let draft, activates, link.host.isSet, !draft.sameLogin(as: link.host), link.state == .connected {
            return "Saving disconnects from \(link.host.hostname) and closes its open terminals."
        }
        if foundNote {
            return trimmedUsername.isEmpty
                ? "Enter the Mac's username, then tap Save. Run `whoami` on the Mac to get it."
                : "Tap Save to \(activates ? "use" : "keep") this Mac. A `.local` name works only on this Wi-Fi."
        }
        return "Use the Mac's Tailscale name or 100.x address. Run `whoami` on the Mac to get the username."
    }

    /// Once per visit. The form appears again when the finder sheet closes, and a second load
    /// would replace the Mac the user just picked.
    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let host = editing else { return }
        name = host.name
        hostname = host.hostname
        port = host.port != 22 ? String(host.port) : ""
        username = host.username
    }

    private func save() {
        guard let host = draft else { return }
        let activates = activates
        store.saveMac(host, activate: activates)
        if activates { link.use(host) }
        foundNote = false
        onSaved()
    }
}
