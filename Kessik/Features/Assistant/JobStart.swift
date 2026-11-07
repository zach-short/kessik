import Foundation

/// Starting an approved assistant job, over the admin login. The assistant only sends plain fields;
/// this file checks each one and builds the command itself, so the assistant's user can never make
/// the admin login run a command of its choosing.
enum JobStart {
    struct Rejected: LocalizedError {
        var reason: String
        var errorDescription: String? { "The job was not started: \(reason)." }
    }

    static let models: Set<String> = ["haiku", "sonnet", "opus", "fable"]
    /// The hook every job runs. scripts/16-assistant.sh installs it; it writes an event file with no content.
    static let hook = "/Users/Shared/home-agent/bin/job-event"

    /// The arguments after `claude --remote-control <session>`: model, hooks, then the task as the first prompt.
    /// `--` ends the options, so the task can never be read as a flag such as a second `--settings`.
    static func claudeArguments(for job: Assistant.JobSpec, home: String) throws -> [String] {
        try check(job, home: home)
        return ["--model", job.model, "--settings", try settings(jobID: job.id), "--", job.task]
    }

    /// A first prompt that starts with `-` could be read as a flag, `/` runs a slash command and `!` runs
    /// bash. The assistant refuses these too; this is the check on the side that runs the command.
    static func startsUnsafe(_ task: String) -> Bool {
        guard let first = task.trimmingCharacters(in: .whitespacesAndNewlines).first else { return true }
        return first == "-" || first == "/" || first == "!"
    }

    static func check(_ job: Assistant.JobSpec, home: String) throws {
        guard job.session == "job-\(job.id)" else { throw Rejected(reason: "the session name is not job-\(job.id)") }
        guard models.contains(job.model) else { throw Rejected(reason: "unknown model \(job.model)") }
        let path = (job.path as NSString).standardizingPath
        guard !home.isEmpty, path == job.path, path.hasPrefix(home + "/"), !path.contains("/.") else {
            throw Rejected(reason: "the folder is not inside your home folder")
        }
        guard !job.task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, job.task.count <= 4000 else {
            throw Rejected(reason: "the task is empty or too long")
        }
        guard !startsUnsafe(job.task) else { throw Rejected(reason: "the task starts with -, / or !") }
    }

    /// Claude Code settings for one job: four hooks that report its state to the assistant.
    static func settings(jobID: Int) throws -> String {
        func group(_ kind: String, matcher: String? = nil) -> [[String: Any]] {
            var entry: [String: Any] = ["hooks": [["type": "command", "command": "\(hook) \(jobID) \(kind)"]]]
            if let matcher { entry["matcher"] = matcher }
            return [entry]
        }
        let hooks: [String: Any] = [
            "UserPromptSubmit": group("working"),
            "Stop": group("stop"),
            "Notification": group("needs", matcher: "permission_prompt"),
            "SessionEnd": group("end"),
        ]
        let data = try JSONSerialization.data(withJSONObject: ["hooks": hooks], options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    /// The git repos the assistant may hand work to: folders in ~/Developer/<org>/ and ~/Projects that hold `.git`.
    /// First line is $HOME.
    static let reposCommand = #"echo "$HOME"; for d in "$HOME"/Developer/*/*/.git "$HOME"/Projects/*/.git; do [ -e "$d" ] && echo "${d%/.git}"; done; true"#

    static func parseRepos(_ output: String) -> (home: String, repos: [[String: String]])? {
        var lines = output.split(separator: "\n").map(String.init)
        guard !lines.isEmpty else { return nil }
        let home = lines.removeFirst()
        var seen = Set<String>()
        let repos = lines.compactMap { path -> [String: String]? in
            let name = (path as NSString).lastPathComponent
            guard path.hasPrefix(home + "/"), name.range(of: #"^[\w.-]+$"#, options: .regularExpression) != nil,
                  seen.insert(name.lowercased()).inserted else { return nil }
            return ["name": name, "path": path]
        }
        return (home, repos)
    }
}
