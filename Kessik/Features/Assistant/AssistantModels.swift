import Foundation

/// Values the home assistant on the Mac returns. Field names arrive in snake_case and decode with
/// `.convertFromSnakeCase`. The assistant keeps the only copy; the app holds them while a screen is open.
enum Assistant {
    struct Conversation: Decodable, Identifiable, Hashable {
        var id: Int
        var title: String
        var updatedAt: String
        var last: String?
    }

    struct Message: Decodable, Identifiable, Equatable {
        var id: Int
        var role: String
        var text: String
        var cardId: Int?
        var createdAt: String
        var card: Card?

        var isUser: Bool { role == "user" }
    }

    struct Turn: Decodable, Equatable {
        var id: Int
        var convId: Int
        var status: String
        var error: String?

        var isRunning: Bool { status == "queued" || status == "running" }
    }

    /// A coding task the assistant proposes for Claude. Nothing starts until Approve.
    struct Card: Decodable, Identifiable, Equatable {
        var id: Int
        var repo: String
        var path: String
        var tier: String
        var task: String
        var warnings: [String]
        var status: String
        var lastEvent: String?
    }

    /// What Approve returns: the fields the app needs to start the job in tmux.
    struct JobSpec: Decodable, Equatable {
        var id: Int
        var session: String
        var repo: String
        var path: String
        var tier: String
        var model: String
        var task: String
    }

    struct Job: Decodable, Identifiable, Equatable {
        var id: Int
        var session: String
        var repo: String
        var path: String
        var tier: String
        var model: String
        var task: String
        var status: String
        var lastEvent: String?
        var updatedAt: String
    }

    struct Fact: Decodable, Identifiable, Equatable {
        var id: Int
        var text: String
        var topic: String
        var source: String
        var updatedAt: String
    }

    struct Draft: Decodable, Identifiable, Equatable {
        struct Review: Decodable, Equatable {
            var verdict: String
            var classOk: Int?
            var note: String
        }

        var id: Int
        var kind: String
        var createdAt: String
        var account: String?
        var subject: String
        var sender: String
        var classification: String?
        var reason: String
        var urgent: Bool
        var body: String
        var event: [String: String]?
        var review: Review?

        var isEvent: Bool { kind == "propose_event" }
    }

    struct Health: Decodable, Equatable {
        struct LastRun: Decodable, Equatable {
            var id: Int
            var finishedAt: String?
            var drafts: Int?
            var errors: Int?
            var skipped: [String]?
        }

        var primaryModel: Bool
        var routerModel: Bool
        var load: [Double]
        var diskFreeGb: Int
        var loopMode: String
        var uptimeHours: Double?
        var lastRun: LastRun?
        var jobsRunning: Int
    }

    /// The tiers, in the order the edit sheet lists them, with the model each one runs.
    static let tiers: [(name: String, model: String, note: String)] = [
        ("Light", "haiku", "The task names the change and the place"),
        ("Mechanical", "sonnet", "A clear change across several files"),
        ("Default", "opus", "Find a cause or choose a design"),
        ("Deep", "fable", "A mistake would pass every test"),
    ]

    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    /// Server time stamps are ISO 8601 with an offset, such as `2026-11-07T10:49:46-05:00`.
    static func date(_ text: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: text)
    }

    static func shortTime(_ text: String) -> String {
        guard let date = date(text) else { return "" }
        if Calendar.current.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

/// The request line the forced command on the Mac reads: `<verb> [<number> ...] [<payload>]`, with the
/// payload as base64url JSON, so nothing in it can reach a shell. Plain values, so it tests without the app.
enum AssistantRequest {
    struct BadArgument: LocalizedError {
        var errorDescription: String? { "The app built a bad request." }
    }

    static let verbs: Set<String> = [
        "ping", "convs", "conv", "send", "turn", "delete-conv", "facts", "fact-add", "fact-edit", "fact-del",
        "repos-set", "card", "card-approve", "card-reject", "card-started", "jobs", "drafts", "draft-mark",
        "health", "digest",
    ]

    static func line(_ verb: String, _ numbers: [Int] = [], payload: [String: Any]? = nil) throws -> String {
        guard verbs.contains(verb), numbers.allSatisfy({ $0 >= 0 }) else { throw BadArgument() }
        var parts = [verb] + numbers.map(String.init)
        if let payload {
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            parts.append(base64url(data))
        }
        return parts.joined(separator: " ")
    }

    static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
