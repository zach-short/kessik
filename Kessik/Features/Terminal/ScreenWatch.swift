import Foundation
import Observation
import SwiftTerm

/// What the app reads from the terminal screen once output stops: a Claude Code menu to show as
/// buttons, and whether tmux shows its history after a swipe up.
@MainActor
@Observable
final class ScreenWatch {
    private(set) var menu: ClaudeMenu?
    /// tmux shows old lines (copy mode). Keys go to tmux, not to Claude, until it leaves.
    private(set) var inHistory = false

    @ObservationIgnored weak var terminal: TerminalView?
    @ObservationIgnored private let session: SSHSession
    @ObservationIgnored private var pendingRead: Task<Void, Never>?
    /// Set by a swipe up. Text on the top line that only looks like tmux's position does not count.
    @ObservationIgnored private var swipedUp = false

    init(session: SSHSession) {
        self.session = session
    }

    /// Called for each chunk of output. Reads the screen once, after the chunks stop.
    func screenChanged() {
        pendingRead?.cancel()
        pendingRead = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            self?.read()
        }
    }

    func didSwipeUp() {
        swipedUp = true
    }

    /// Sends "q", which closes tmux copy mode in both its key tables, so the next keys reach
    /// Claude and the newest output comes back.
    func leaveHistory() {
        guard inHistory else { return }
        inHistory = false
        swipedUp = false
        session.send("q")
    }

    func choose(_ option: ClaudeMenu.Option) {
        guard let menu else { return }
        leaveHistory()
        session.send(menu.keys(for: option))
        // Hidden until the next read, so a second tap does not answer the next menu.
        self.menu = nil
    }

    private func read() {
        guard let terminal = terminal?.getTerminal() else { return }
        let lines = (0..<terminal.rows).map { row in
            terminal.getLine(row: row)?.translateToString(trimRight: true) { cell in
                // A cell nothing was written to reads as NUL. tmux crosses blank runs with cursor
                // moves, so the gap in "❯ 1. Red" can be NUL, which the menu pattern would miss.
                let character = terminal.getCharacter(for: cell)
                return character == "\0" ? " " : character
            } ?? ""
        }
        let menu = ClaudeMenu(screen: lines)
        if menu != self.menu { self.menu = menu }

        let history = swipedUp && Self.showsPosition(lines.first ?? "")
        // tmux left on its own: the swipe reached the newest line.
        if inHistory, !history { swipedUp = false }
        if history != inHistory { inHistory = history }
    }

    private static let positionPattern = #/\[\d+\/\d+\](?: \([^)]*\))?$/#

    /// In copy mode tmux puts its place in the history, such as "[12/840]", at the right end of
    /// the top line, with a search count after it while a search is open.
    private static func showsPosition(_ top: String) -> Bool {
        top.firstMatch(of: positionPattern) != nil
    }
}
