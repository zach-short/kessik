import Foundation

/// A numbered choice menu that Claude Code shows at the bottom of the screen, such as a permission
/// prompt or a question with options, read from the screen text:
///
///     ❯ 1. Yes
///       2. Yes, and always allow access to …
///       3. No
///
///     Esc to cancel · Tab to amend
///
/// Only numbered menus count. The digit picks that option at once, wherever the `❯` is. A menu
/// without numbers, such as the folder trust prompt, needs arrow keys, and a label that wraps
/// onto two lines would look like two options there.
struct ClaudeMenu: Equatable {
    struct Option: Identifiable, Equatable {
        let number: Int
        let label: String
        var id: Int { number }
    }

    let options: [Option]
    /// The number the `❯` is on.
    let cursor: Int

    /// Keys that choose `option`. Claude Code takes the digits 1 to 9; past 9 the arrow keys move
    /// to it and Return chooses it.
    func keys(for option: Option) -> [UInt8] {
        if option.number <= 9 {
            return Array(String(option.number).utf8)
        }
        let delta = option.number - cursor
        let arrow: [UInt8] = delta < 0 ? [0x1b, 0x5b, 0x41] : [0x1b, 0x5b, 0x42]
        return Array([[UInt8]](repeating: arrow, count: abs(delta)).joined()) + [0x0d]
    }
}

extension ClaudeMenu {
    /// Every menu in Claude Code 2.1 ends with a hint such as "Enter to select · ↑/↓ to navigate ·
    /// Esc to cancel". The input box also starts with `❯`, so a typed numbered list would look like
    /// a menu without this check. "esc to interrupt" while Claude works is lower case.
    private static let hints = ["Esc to", "Enter to"]
    /// Options sit at most this many lines apart: a wrapped label, a description or a rule.
    private static let maxGap = 4

    /// Finds the menu that waits for an answer in the visible rows, top to bottom. While a menu is
    /// open Claude Code hides the input box, so the menu's `❯` is the last one on the screen.
    init?(screen: [String]) {
        guard let row = screen.lastIndex(where: { Self.unboxed($0).first == "❯" }),
              let marked = Self.option(in: screen[row]), marked.marked,
              screen[(row + 1)...].contains(where: { line in Self.hints.contains { line.contains($0) } })
        else { return nil }

        var options = [Option(number: marked.number, label: marked.label)]
        // Up to option 1.
        var gap = 0
        var index = row - 1
        while let first = options.first, first.number > 1, index >= 0, gap <= Self.maxGap {
            if let found = Self.option(in: screen[index]) {
                guard found.number == first.number - 1 else { return nil }
                options.insert(Option(number: found.number, label: found.label), at: 0)
                gap = 0
            } else {
                gap += 1
            }
            index -= 1
        }
        guard options.first?.number == 1 else { return nil }
        // Down to the hint line.
        gap = 0
        index = row + 1
        while let last = options.last, index < screen.count, gap <= Self.maxGap,
              !Self.hints.contains(where: { screen[index].contains($0) }) {
            if let found = Self.option(in: screen[index]) {
                guard found.number == last.number + 1 else { break }
                options.append(Option(number: found.number, label: found.label))
                gap = 0
            } else {
                gap += 1
            }
            index += 1
        }
        guard options.count >= 2 else { return nil }
        self.options = options
        self.cursor = marked.number
    }

    private static let optionPattern = #/^\s*(?<marker>❯\s*)?(?<number>\d{1,2})\.\s+(?<label>\S.*?)\s*$/#

    /// "❯ 1. Yes" or "  2. No".
    private static func option(in line: String) -> (marked: Bool, number: Int, label: String)? {
        guard let match = unboxed(line).wholeMatch(of: optionPattern), let number = Int(match.number) else { return nil }
        return (match.marker != nil, number, String(match.label))
    }

    /// Old Claude Code versions drew the menu in a box, so the `│` edges and spaces go first.
    private static func unboxed(_ line: String) -> String {
        line.trimmingCharacters(in: CharacterSet(charactersIn: "│ "))
    }
}
