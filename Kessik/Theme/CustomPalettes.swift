import Foundation

/// Terminal palettes the user imports from iTerm2 `.itermcolors` files, kept in UserDefaults.
///
/// Imported palettes have one look on every app theme, as the fixed built-ins do. Their ids start
/// with `custom-`, so they never match a built-in id, and the built-ins always win a lookup.
struct CustomPalettes {
    static let key = "customPalettes"
    static let idPrefix = "custom-"
    static let maxCount = 50
    static let maxNameLength = 40
    /// Real `.itermcolors` files are under 20 KB. The cap bounds the work a hostile file can cause.
    static let maxFileSize = 256 * 1024

    enum ImportError: Error, Equatable, LocalizedError {
        case tooLarge
        case notAPlist
        case missingColor(String)
        case badColor(String)
        case badName
        case nameTooLong
        case tooMany

        var errorDescription: String? {
            switch self {
            case .tooLarge: "The file is larger than \(CustomPalettes.maxFileSize / 1024) KB."
            case .notAPlist: "This is not an .itermcolors file. Export the theme from iTerm2 or copy the whole file."
            case .missingColor(let key): "The theme has no \(key)."
            case .badColor(let key): "\(key) needs Red, Green and Blue components from 0 to 1."
            case .badName: "Give the theme a name."
            case .nameTooLong: "The name can have at most \(CustomPalettes.maxNameLength) characters."
            case .tooMany: "You can keep at most \(CustomPalettes.maxCount) imported themes. Delete one first."
            }
        }
    }

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The saved palettes, oldest first. Stored entries that fail validation are left out.
    var palettes: [TerminalPalette] {
        Self.decode(defaults.data(forKey: Self.key) ?? Data())
    }

    /// Validates the name and the theme, then saves it as a new palette.
    @discardableResult
    func add(name: String, data: Data) throws -> TerminalPalette {
        let name = try Self.validName(name)
        let colors = try Self.parse(data)
        var records = Self.records(defaults.data(forKey: Self.key) ?? Data())
        guard records.count < Self.maxCount else { throw ImportError.tooMany }
        let record = Record(id: Self.idPrefix + UUID().uuidString, name: name, foreground: colors.foreground,
                            background: colors.background, cursor: colors.cursor, ansi: colors.ansi)
        records.append(record)
        save(records)
        return record.palette
    }

    /// Removes the palette. When it was the selected one, the selection goes back to Default.
    func delete(id: String) {
        let records = Self.records(defaults.data(forKey: Self.key) ?? Data())
        save(records.filter { $0.id != id })
        if defaults.string(forKey: SettingsKey.terminalPalette) == id {
            defaults.set(TerminalPalette.defaultID, forKey: SettingsKey.terminalPalette)
        }
    }

    private func save(_ records: [Record]) {
        if let data = try? JSONEncoder().encode(records) {
            defaults.set(data, forKey: Self.key)
        }
    }

    static func decode(_ data: Data) -> [TerminalPalette] {
        records(data).map(\.palette)
    }

    private static func records(_ data: Data) -> [Record] {
        guard let records = try? JSONDecoder().decode([Record].self, from: data) else { return [] }
        return Array(records.filter(\.isValid).prefix(maxCount))
    }

    /// The trimmed name, or an error when it is empty, too long or has control characters.
    static func validName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw ImportError.badName
        }
        guard trimmed.count <= maxNameLength else { throw ImportError.nameTooLong }
        return trimmed
    }

    /// Reads an iTerm2 color preset, in XML or binary plist form.
    ///
    /// Ansi 0 to 15, Background and Foreground are required. Cursor is optional and falls back to
    /// the text color. Components are taken as sRGB; iTerm2's older Calibrated color space differs
    /// from it by a few steps at most. Selection Color has no place in a palette, so it is ignored.
    static func parse(_ data: Data) throws -> TerminalPalette.Colors {
        guard data.count <= maxFileSize else { throw ImportError.tooLarge }
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let entries = plist as? [String: Any] else { throw ImportError.notAPlist }

        func color(_ key: String) throws -> String? {
            guard let value = entries[key] else { return nil }
            guard let components = value as? [String: Any],
                  let red = component(components["Red Component"]),
                  let green = component(components["Green Component"]),
                  let blue = component(components["Blue Component"]) else { throw ImportError.badColor(key) }
            return String(format: "#%02X%02X%02X", red, green, blue)
        }
        func required(_ key: String) throws -> String {
            guard let hex = try color(key) else { throw ImportError.missingColor(key) }
            return hex
        }

        let ansi = try (0..<16).map { try required("Ansi \($0) Color") }
        let background = try required("Background Color")
        let foreground = try required("Foreground Color")
        let cursor = try color("Cursor Color") ?? foreground
        return TerminalPalette.Colors(foreground: foreground, background: background, cursor: cursor, ansi: ansi)
    }

    /// A component from 0 to 1 as an 8-bit value. Booleans, strings and NaN are not numbers here.
    private static func component(_ value: Any?) -> UInt8? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        guard double.isFinite, (0...1).contains(double) else { return nil }
        return UInt8((double * 255).rounded())
    }

    private struct Record: Codable {
        var id: String
        var name: String
        var foreground: String
        var background: String
        var cursor: String
        var ansi: [String]

        var isValid: Bool {
            id.hasPrefix(CustomPalettes.idPrefix)
                && (try? CustomPalettes.validName(name)) == name
                && ansi.count == 16
                && ([foreground, background, cursor] + ansi).allSatisfy { RGB8(hex: $0) != nil }
        }

        var palette: TerminalPalette {
            TerminalPalette(id: id, name: name,
                            dark: .init(foreground: foreground, background: background, cursor: cursor, ansi: ansi))
        }
    }
}
