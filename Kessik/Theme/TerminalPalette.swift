import Foundation

/// A terminal color theme: text, background, cursor and the 16 ANSI colors, as hex strings.
///
/// How it meets the app theme: Default has a dark and a light set and follows the app theme,
/// as the terminal did before palettes. Every other palette has one fixed look on all three app
/// themes, so a light palette stays light on the dark app theme. The key bar and the rest of
/// the app keep the app theme.
struct TerminalPalette: Identifiable, Equatable {
    struct Colors: Equatable {
        var foreground: String
        var background: String
        var cursor: String
        /// Black, red, green, yellow, blue, magenta, cyan, white, then the bright eight.
        var ansi: [String]
    }

    let id: String
    let name: String
    let dark: Colors
    /// Used on the light app theme. Nil when the palette has one look.
    var light: Colors? = nil

    func colors(dark isDark: Bool) -> Colors {
        isDark ? dark : (light ?? dark)
    }

    /// The stored id's palette, built in or imported, or Default when the id is unknown,
    /// as it is after an imported palette is deleted.
    static func named(_ id: String, defaults: UserDefaults = .standard) -> TerminalPalette {
        if let builtIn = all.first(where: { $0.id == id }) { return builtIn }
        guard id.hasPrefix(CustomPalettes.idPrefix) else { return .standard }
        return CustomPalettes(defaults: defaults).palettes.first { $0.id == id } ?? .standard
    }

    static let defaultID = "default"

    /// The look before palettes. Text and background are `Theme.uiTerminalText` and
    /// `Theme.uiBackground` rounded to 8 bits. The ANSI colors are SwiftTerm's own default
    /// (`Color.terminalAppColors`). The cursor is the text color, as SwiftTerm draws it by default.
    static let standard = TerminalPalette(
        id: defaultID, name: "Default",
        dark: Colors(foreground: "#EBEBEB", background: "#0C0C0E", cursor: "#EBEBEB", ansi: terminalApp),
        light: Colors(foreground: "#1A1A1A", background: "#F6F6F6", cursor: "#1A1A1A", ansi: terminalApp))

    private static let terminalApp = [
        "#000000", "#C23621", "#25BC24", "#ADAD27", "#492EE1", "#D338D3", "#33BBC8", "#CBCCCD",
        "#818383", "#FC391F", "#31E722", "#EAEC23", "#5833FF", "#F935F8", "#14F0F0", "#E9EBEB",
    ]

    /// From the Solarized README (altercation/solarized), with its 16-color terminal mapping.
    private static let solarizedANSI = [
        "#073642", "#DC322F", "#859900", "#B58900", "#268BD2", "#D33682", "#2AA198", "#EEE8D5",
        "#002B36", "#CB4B16", "#586E75", "#657B83", "#839496", "#6C71C4", "#93A1A1", "#FDF6E3",
    ]

    static let all: [TerminalPalette] = [
        standard,
        TerminalPalette(
            id: "solarized-dark", name: "Solarized Dark",
            dark: Colors(foreground: "#839496", background: "#002B36", cursor: "#93A1A1", ansi: solarizedANSI)),
        TerminalPalette(
            id: "solarized-light", name: "Solarized Light",
            dark: Colors(foreground: "#657B83", background: "#FDF6E3", cursor: "#586E75", ansi: solarizedANSI)),
        // morhetz/gruvbox, dark mode, medium contrast.
        TerminalPalette(
            id: "gruvbox-dark", name: "Gruvbox Dark",
            dark: Colors(foreground: "#EBDBB2", background: "#282828", cursor: "#EBDBB2", ansi: [
                "#282828", "#CC241D", "#98971A", "#D79921", "#458588", "#B16286", "#689D6A", "#A89984",
                "#928374", "#FB4934", "#B8BB26", "#FABD2F", "#83A598", "#D3869B", "#8EC07C", "#EBDBB2",
            ])),
        // folke/tokyonight.nvim, extras/kitty/tokyonight_night.conf.
        TerminalPalette(
            id: "tokyo-night", name: "Tokyo Night",
            dark: Colors(foreground: "#C0CAF5", background: "#1A1B26", cursor: "#C0CAF5", ansi: [
                "#15161E", "#F7768E", "#9ECE6A", "#E0AF68", "#7AA2F7", "#BB9AF7", "#7DCFFF", "#A9B1D6",
                "#414868", "#FF899D", "#9FE044", "#FABA4A", "#8DB0FF", "#C7A9FF", "#A4DAFF", "#C0CAF5",
            ])),
        // sonph/onehalf, kitty/onehalf-light.conf. It sets no cursor, so the cursor is the text color.
        TerminalPalette(
            id: "one-half-light", name: "One Half Light",
            dark: Colors(foreground: "#383A42", background: "#FAFAFA", cursor: "#383A42", ansi: [
                "#383A42", "#E45649", "#40A14F", "#C18401", "#0184BC", "#A626A4", "#0997B3", "#FAFAFA",
                "#383A42", "#E45649", "#40A14F", "#C18401", "#0184BC", "#A626A4", "#0997B3", "#FAFAFA",
            ])),
    ]
}

/// An 8-bit color parsed from "#RRGGBB" or "RRGGBB".
struct RGB8: Equatable {
    var red: UInt8
    var green: UInt8
    var blue: UInt8

    init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init?(hex: String) {
        let digits = hex.hasPrefix("#") ? hex.dropFirst() : Substring(hex)
        guard digits.count == 6, digits.allSatisfy(\.isHexDigit), let value = UInt32(digits, radix: 16) else {
            return nil
        }
        red = UInt8((value >> 16) & 0xFF)
        green = UInt8((value >> 8) & 0xFF)
        blue = UInt8(value & 0xFF)
    }
}
