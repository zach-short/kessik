import AppKit
import ApplicationServices
import RemoteWire

/// The menu bar item. It shows whether the Mac allows input from Kessik Remote and how many
/// phones are connected.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var server: Server?
    private var trusted = false
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "av.remote", accessibilityDescription: "Kessik Remote")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item

        // The first launch shows the system prompt that adds Kessik Remote to the Accessibility list.
        let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        trusted = AXIsProcessTrustedWithOptions(prompt)

        do {
            let server = Server(token: try Token.load())
            server.isTrusted = { [weak self] in self?.trusted ?? false }
            server.start()
            self.server = server
        } catch {
            startError = "Could not save the token: \(error.localizedDescription)"
        }

        // macOS sends no notice when the permission changes, so ask on a timer.
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.checkTrust() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private var startError: String?

    private func checkTrust() {
        let now = AXIsProcessTrusted()
        guard now != trusted else { return }
        trusted = now
        server?.trustChanged(now)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(info("Kessik Remote"))
        menu.addItem(.separator())

        if let problem = startError ?? server?.problem {
            menu.addItem(info(problem))
        } else {
            let count = server?.phones ?? 0
            menu.addItem(info(count == 0 ? "No phone connected" : count == 1 ? "1 phone connected" : "\(count) phones connected"))
        }

        if trusted {
            menu.addItem(info("Accessibility: allowed"))
        } else {
            menu.addItem(info("Accessibility: not allowed. The Mac ignores the remote."))
            let open = NSMenuItem(title: "Open Accessibility Settings", action: #selector(openAccessibility), keyEquivalent: "")
            open.target = self
            menu.addItem(open)
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Kessik Remote", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func info(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func openAccessibility() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}

/// A random secret in a file only this user can read. The phone reads it over SSH, so a login to
/// the Mac is what proves the phone may use the remote.
enum Token {
    static func load() throws -> String {
        let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(RemoteWire.tokenPath)
        if let saved = try? String(contentsOf: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           saved.count == 64, saved.allSatisfy(\.isHexDigit) {
            return saved
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw CocoaError(.fileWriteUnknown)
        }
        let token = bytes.map { String(format: "%02x", $0) }.joined()
        let folder = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        FileManager.default.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600])
        try Data((token + "\n").utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        return token
    }
}
