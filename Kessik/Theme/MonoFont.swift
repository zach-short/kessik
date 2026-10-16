import CoreText
import SwiftUI
import UIKit

/// The monospaced face for the terminal and for hostnames, paths and session names in the app.
/// Settings stores its family name. Bold and italic come from the same family by trait matching,
/// so a family with variable fonts (one file for every weight) works as well as one with a file
/// for each face.
struct MonoFont: Hashable, Identifiable {
    enum Source { case system, bundled, imported }

    let family: String
    let source: Source

    var id: String { family }

    static let defaultFamily = "Geist Mono"

    /// SF Mono has no family name that UIKit can look up, so it goes through `monospacedSystemFont`.
    static let sfMono = MonoFont(family: "SF Mono", source: .system)
    static let builtIn = [sfMono, MonoFont(family: "Menlo", source: .system)]
    static let bundled = ["Geist Mono", "JetBrains Mono", "IBM Plex Mono", "Atkinson Hyperlegible Mono"]
        .map { MonoFont(family: $0, source: .bundled) }
    static var imported: [MonoFont] {
        FontLibrary.registerOnce()
        return FontLibrary.importedFamilies.map { MonoFont(family: $0, source: .imported) }
    }

    /// The font picked in Settings.
    static var current: MonoFont {
        named(UserDefaults.standard.string(forKey: SettingsKey.monoFont) ?? defaultFamily)
    }

    /// The saved family, or Geist Mono when that family was removed.
    static func named(_ family: String) -> MonoFont {
        let all = builtIn + bundled + imported
        return all.first { $0.family == family } ?? all.first { $0.family == defaultFamily }!
    }

    func uiFont(size: CGFloat, weight: UIFont.Weight = .regular, italic: Bool = false) -> UIFont {
        if self == .sfMono {
            let font = UIFont.monospacedSystemFont(ofSize: size, weight: weight)
            guard italic, let descriptor = font.fontDescriptor.withSymbolicTraits(.traitItalic) else { return font }
            return UIFont(descriptor: descriptor, size: size)
        }
        var traits: [UIFontDescriptor.TraitKey: Any] = [.weight: weight.rawValue]
        if italic { traits[.symbolic] = UIFontDescriptor.SymbolicTraits.traitItalic.rawValue }
        let descriptor = UIFontDescriptor(fontAttributes: [.family: family, .traits: traits])
        return UIFont(descriptor: descriptor, size: size)
    }

    /// For SwiftUI text. Scales with Dynamic Type like the system style of the same name.
    func font(_ style: Font.TextStyle = .footnote) -> Font {
        if self == .sfMono { return .system(style, design: .monospaced) }
        return .custom(family, size: Self.baseSize(style), relativeTo: style)
    }

    /// Point sizes of the text styles at the default Dynamic Type size.
    private static func baseSize(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline, .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        @unknown default: 17
        }
    }
}

/// Registers the bundled fonts and the ones added from Files with Core Text for this process,
/// and copies new ones into Application Support so they load on the next launch too.
enum FontLibrary {
    enum ImportError: LocalizedError {
        case notAFont(String)
        case notMonospaced(String)
        case included(String)

        var errorDescription: String? {
            switch self {
            case .notAFont(let file):
                "\(file) is not a font file. Use a TTF or OTF file."
            case .notMonospaced(let family):
                "\(family) is not monospaced. The terminal needs a font where every character has the same width."
            case .included(let family):
                "Kessik already includes \(family)."
            }
        }
    }

    private(set) static var importedFamilies: [String] = []
    private static var registered = false

    private static var directory: URL {
        URL.applicationSupportDirectory.appending(path: "Fonts", directoryHint: .isDirectory)
    }

    static func registerOnce() {
        guard !registered else { return }
        registered = true
        let bundled = ["ttf", "otf"].flatMap { Bundle.main.urls(forResourcesWithExtension: $0, subdirectory: nil) ?? [] }
        let added = importedFiles()
        (bundled + added).forEach(register)
        importedFamilies = Set(added.flatMap(families)).sorted()
    }

    /// Copies the files, registers them and returns the families they add, in order.
    /// Checks every file before it copies any, so a bad file in the selection adds nothing.
    @discardableResult
    static func add(_ urls: [URL]) throws -> [String] {
        registerOnce()
        let included = Set((MonoFont.builtIn + MonoFont.bundled).map(\.family))
        var checked: [(url: URL, families: [String])] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let found = families(in: url)
            guard !found.isEmpty else { throw ImportError.notAFont(url.lastPathComponent) }
            if let family = found.first(where: included.contains) { throw ImportError.included(family) }
            if let family = found.first(where: { !isMonospaced(url: url, family: $0) }) {
                throw ImportError.notMonospaced(family)
            }
            checked.append((url, found))
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var added: [String] = []
        for (url, found) in checked {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let destination = directory.appending(path: url.lastPathComponent)
            if FileManager.default.fileExists(atPath: destination.path) {
                unregister(destination)
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: url, to: destination)
            register(destination)
            added += found.filter { !added.contains($0) }
        }
        importedFamilies = Set(importedFamilies + added).sorted()
        return added
    }

    /// Unregisters and deletes every added file of the family.
    static func remove(family: String) {
        for file in importedFiles() where families(in: file).contains(family) {
            unregister(file)
            try? FileManager.default.removeItem(at: file)
        }
        importedFamilies.removeAll { $0 == family }
    }

    private static func importedFiles() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
    }

    private static func register(_ url: URL) {
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }

    private static func unregister(_ url: URL) {
        CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil)
    }

    private static func families(in url: URL) -> [String] {
        let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] ?? []
        var names: [String] = []
        for descriptor in descriptors {
            if let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute) as? String,
               !names.contains(name) {
                names.append(name)
            }
        }
        return names
    }

    /// True when narrow and wide letters have the same advance, as in every terminal font.
    private static func isMonospaced(url: URL, family: String) -> Bool {
        let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] ?? []
        guard let descriptor = descriptors.first(where: {
            CTFontDescriptorCopyAttribute($0, kCTFontFamilyNameAttribute) as? String == family
        }) else { return false }
        let font = CTFontCreateWithFontDescriptor(descriptor, 100, nil)
        var characters = Array("iW0m.".utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        guard CTFontGetGlyphsForCharacters(font, &characters, &glyphs, characters.count) else { return false }
        var advances = [CGSize](repeating: .zero, count: glyphs.count)
        CTFontGetAdvancesForGlyphs(font, .horizontal, glyphs, &advances, glyphs.count)
        let widths = advances.map(\.width)
        guard let narrowest = widths.min(), let widest = widths.max() else { return false }
        return widest - narrowest < 0.5
    }
}
