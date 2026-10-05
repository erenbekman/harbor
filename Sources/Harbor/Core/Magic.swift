import Foundation

/// "Magic": Claude reads the project and says what it runs.
///
/// Deliberately READ-ONLY and deliberately not writing anything itself — the
/// answer comes back as a proposal the user ticks, because a wrong command that
/// appears in the sidebar on its own is worse than no command at all.
enum Magic {

    struct Suggestion: Identifiable, Decodable {
        var id = UUID()
        var name: String
        var command: String
        var dir: String?
        var health: String?
        var why: String?

        private enum CodingKeys: String, CodingKey { case name, command, dir, health, why }

        var service: Service {
            Service(name: name, command: command, dir: dir ?? "", health: health ?? "")
        }
    }

    struct Answer: Decodable {
        var services: [Suggestion]
        var notes: [String]?
    }

    enum Failure: LocalizedError {
        case missingCLI
        case timedOut
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .missingCLI:
                return "The `claude` command was not found. Install Claude Code, or copy the prompt and run it yourself."
            case .timedOut:
                return "Claude did not answer within five minutes."
            case .failed(let message):
                return message
            }
        }
    }

    static var isAvailable: Bool { Shell.which("claude") != nil }

    static func scan(_ project: Project) throws -> Answer {
        guard Shell.which("claude") != nil else { throw Failure.missingCLI }

        // `--allowedTools` is a permission list, not a tool list: Bash stays on
        // offer, and in print mode a Bash call can never be approved — the CLI
        // then waits for a decision that cannot come, which is a hang, not an
        // error. `--disallowedTools` takes those tools away, so a reach for one
        // comes back as a refusal the model can carry on from. MCP servers are
        // switched off for the same reason, and because four of them starting up
        // is seconds this never needed.
        let command = "cd \(Shell.quoted(project.path)) && claude -p \(Shell.quoted(prompt(for: project))) "
            + "--output-format json "
            + "--allowedTools \(Shell.quoted("Read,Glob,Grep")) "
            + "--disallowedTools \(Shell.quoted("Bash,Write,Edit,MultiEdit,NotebookEdit,WebFetch,WebSearch,Task")) "
            + "--strict-mcp-config --mcp-config \(Shell.quoted("{\"mcpServers\":{}}"))"
        // `-l` but NOT `-i`: the PATH is injected already, and an interactive zsh
        // without a tty writes "can't change option: zle" over the answer.
        let result = Shell.run("/bin/zsh", ["-l", "-c", command], timeout: 300)
        log(command: command, status: result.status, output: result.output)
        if result.status == -2 { throw Failure.timedOut }

        // The CLI reports its own failures inside the envelope — "Not logged in",
        // a refused tool, a rate limit — and that message beats anything this app
        // could say instead.
        if let slice = Self.jsonSlice(result.output),
           let data = slice.data(using: .utf8),
           let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let failed = envelope["is_error"] as? Bool, failed {
            throw Failure.failed((envelope["result"] as? String) ?? "Claude reported an error.")
        }

        // `--output-format json` wraps the answer, and the CLI may print a line of
        // its own before it — so the JSON is cut out rather than assumed to be the
        // whole of stdout. What is inside the envelope's `result` is the model's
        // own answer, which may itself arrive inside a code fence.
        let body = Self.unwrap(Self.jsonSlice(result.output) ?? result.output)

        guard let slice = Self.jsonSlice(body),
              let data = slice.data(using: .utf8),
              let answer = try? JSONDecoder().decode(Answer.self, from: data)
        else {
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure.failed(trimmed.isEmpty ? "Claude answered with nothing." : String(trimmed.prefix(400)))
        }
        return answer
    }

    /// The only place a failure in a GUI-spawned CLI can be read back from.
    private static func log(command: String, status: Int32, output: String) {
        let entry = "--- \(Date()) exit \(status)\n\(command.prefix(400))\n\(output.prefix(4000))\n\n"
        let url = Paths.support.appendingPathComponent("magic.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(entry.utf8))
            try? handle.close()
        } else {
            try? entry.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private static func jsonSlice(_ text: String) -> String? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end
        else { return nil }
        return String(text[start...end])
    }

    private static func unwrap(_ json: String) -> String {
        guard let data = json.data(using: .utf8),
              let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = envelope["result"] as? String
        else { return json }
        return result
    }

    static func prompt(for project: Project) -> String {
        """
        Work out which long-running development processes this project actually has, \
        and answer with JSON only.

        BE QUICK: a handful of targeted Globs and Reads, not an exhaustive walk of the         repository. You are looking at configuration, not at the code.

        HOW TO LOOK:
        - Walk the root AND subdirectories, including monorepo layouts like backend/, \
        frontend/, api/, apps/*, packages/*.
        - Sources: package.json "scripts" (dev/start/watch/serve) with the lockfile deciding \
        npm/pnpm/yarn/bun, composer.json, artisan commands (serve, horizon, queue:work, \
        reverb:start, schedule:work), Makefile targets, docker-compose services, Procfile, \
        the README's setup section, .env.example.
        - A health path only if the project really serves one (/health, /up, /api/health).

        WHAT COUNTS: processes that KEEP RUNNING — dev servers, queue workers, websocket \
        servers, `docker compose up`, watchers. Anything that finishes on its own (build, \
        migrate, test, install) is NOT a service; leave it out.

        ANSWER WITH THIS AND NOTHING ELSE — no prose, no code fences:
        {
          "services": [
            {
              "name": "dev",
              "command": "pnpm dev",
              "dir": "frontend",
              "health": "/health",
              "why": "vite dev server, port from vite.config.ts"
            }
          ],
          "notes": ["redis has to be running for the queue worker"]
        }

        FIELDS:
        - name: short, lowercase, what a sidebar row says. Required.
        - command: run through `zsh -l -i -c` inside tmux, from `dir`. Required.
        - dir: relative to the project root. Omit it for the root itself, and only name a \
        directory you have actually seen.
        - health: optional path or URL.
        - why: one line, naming the file you read it from.
        - notes: anything that has to be running or installed FIRST (a database, redis, \
        `composer install`), one short line each. Omit if there is nothing to say.

        RULES:
        - No port field: Harbor measures the port from the running process.
        - Be lean. A service you cannot point at a file for does not go in. A wrong command \
        is worse than a missing one.
        - These already exist, do not repeat them: \
        \(project.services.map { "\($0.name) — \($0.command)" }.joined(separator: "; ").isEmpty
            ? "none"
            : project.services.map { "\($0.name) — \($0.command)" }.joined(separator: "; "))
        """
    }
}
