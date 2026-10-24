import Foundation

/// Codex (OpenAI) plan limits — the same windows `codex /status` shows, as
/// returned by the Codex CLI app-server's `account/rateLimits/read`.
public struct CodexRateLimits: Sendable, Equatable {
    public struct Window: Sendable, Equatable {
        /// 0–100 as reported (not clamped).
        public var usedPercent: Double
        public var windowMinutes: Int?
        public var resetsAt: Date?

        public init(usedPercent: Double, windowMinutes: Int?, resetsAt: Date?) {
            self.usedPercent = usedPercent
            self.windowMinutes = windowMinutes
            self.resetsAt = resetsAt
        }
    }

    public var primary: Window?
    public var secondary: Window?
    /// Raw plan id, e.g. "plus", "pro".
    public var planType: String?
    /// Raw `rateLimitReachedType`, e.g. "rate_limit_reached"; nil while under the limit.
    public var limitReached: String?

    public init(primary: Window?, secondary: Window?, planType: String?, limitReached: String?) {
        self.primary = primary
        self.secondary = secondary
        self.planType = planType
        self.limitReached = limitReached
    }

    /// Parses one JSON-RPC message line answering `account/rateLimits/read`.
    public static func parse(response line: Data) throws -> CodexRateLimits {
        guard let message = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else {
            throw CodexError.malformedResponse
        }
        if let error = message["error"] as? [String: Any] {
            throw CodexError.fromRPC(message: error["message"] as? String ?? "")
        }
        guard let result = message["result"] as? [String: Any] else { throw CodexError.malformedResponse }

        // `rateLimits` is the single-bucket view `/status` uses; fall back to the
        // `codex` bucket of the multi-bucket view if it's empty.
        var snapshot = result["rateLimits"] as? [String: Any]
        if window(snapshot?["primary"]) == nil, window(snapshot?["secondary"]) == nil,
           let codex = (result["rateLimitsByLimitId"] as? [String: Any])?["codex"] as? [String: Any] {
            snapshot = codex
        }
        guard let snapshot else { throw CodexError.malformedResponse }

        let limits = CodexRateLimits(
            primary: window(snapshot["primary"]),
            secondary: window(snapshot["secondary"]),
            planType: snapshot["planType"] as? String,
            limitReached: snapshot["rateLimitReachedType"] as? String
        )
        guard limits.primary != nil || limits.secondary != nil else { throw CodexError.noUsageData }
        return limits
    }

    private static func window(_ raw: Any?) -> Window? {
        guard let dict = raw as? [String: Any],
              let used = (dict["usedPercent"] as? NSNumber)?.doubleValue else { return nil }
        var resetsAt: Date?
        if let epoch = (dict["resetsAt"] as? NSNumber)?.doubleValue {
            // Unix seconds per the protocol; tolerate milliseconds.
            resetsAt = Date(timeIntervalSince1970: epoch > 1e12 ? epoch / 1000 : epoch)
        }
        return Window(usedPercent: used, windowMinutes: (dict["windowDurationMins"] as? NSNumber)?.intValue, resetsAt: resetsAt)
    }
}

public enum CodexError: Error, Equatable, LocalizedError {
    case notInstalled
    case notLoggedIn
    case rpc(String)
    case timeout
    case exited(status: Int32, detail: String)
    case malformedResponse
    case noUsageData

    static func fromRPC(message: String) -> CodexError {
        // codex-cli 0.144: "codex account authentication required to read rate limits".
        if message.localizedCaseInsensitiveContains("authentication required")
            || message.localizedCaseInsensitiveContains("not logged in") {
            return .notLoggedIn
        }
        return .rpc(message)
    }

    public var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "Codex CLI not found — install it (`brew install codex` or `npm i -g @openai/codex`)."
        case .notLoggedIn:
            return "Not signed in to Codex — run `codex login` in a terminal."
        case .rpc(let message):
            return "Codex: \(message)"
        case .timeout:
            return "Codex didn't answer in time."
        case .exited(let status, let detail):
            return detail.isEmpty ? "Codex exited (\(status))." : "Codex exited (\(status)): \(detail)"
        case .malformedResponse:
            return "Unexpected reply from Codex."
        case .noUsageData:
            return "Codex reported no usage limits for this sign-in (API-key sign-ins have none)."
        }
    }
}

/// What the panel and menu bar show for Codex: its windows mapped onto the
/// session (shorter) and weekly (longer) meter slots, titled by real length.
public struct CodexSnapshot: Sendable {
    /// `fiveHour` holds the shorter window (or the only one), `weekly` the
    /// longer one; `fableWeekly` is always nil.
    public var usage: UsageSnapshot
    public var sessionTitle: String
    /// nil when Codex reports a single window (the weekly meter is then empty).
    public var weeklyTitle: String?
    public var planName: String?
    public var limitReachedText: String?

    public static func build(from limits: CodexRateLimits, now: Date = Date()) -> CodexSnapshot {
        // Shorter window first; unknown lengths keep primary-before-secondary.
        let ordered = [limits.primary, limits.secondary].compactMap { $0 }.enumerated()
            .sorted { a, b in
                let la = a.element.windowMinutes ?? .max, lb = b.element.windowMinutes ?? .max
                return la != lb ? la < lb : a.offset < b.offset
            }
            .map(\.element)
        let session = ordered.first
        let weekly = ordered.count > 1 ? ordered[1] : nil

        func meter(_ window: CodexRateLimits.Window?) -> Meter {
            guard let window else { return Meter(percent: nil, resetText: "") }
            var pace: Pace?
            if let resetsAt = window.resetsAt, let minutes = window.windowMinutes {
                pace = Pace.compute(percent: window.usedPercent, resetsAt: resetsAt, windowSeconds: Double(minutes) * 60, now: now)
            }
            return Meter(percent: min(100, max(0, window.usedPercent)), resetText: Format.reset(window.resetsAt, now: now), pace: pace)
        }

        return CodexSnapshot(
            usage: UsageSnapshot(
                fiveHour: meter(session),
                weekly: meter(weekly),
                activityLevel: min(1, max(0, (session?.usedPercent ?? 0) / 100)),
                updatedAt: now
            ),
            sessionTitle: windowTitle(minutes: session?.windowMinutes),
            weeklyTitle: weekly.map { windowTitle(minutes: $0.windowMinutes) },
            planName: planName(limits.planType),
            limitReachedText: limitReachedText(limits.limitReached)
        )
    }

    /// "5-hour limit", "Weekly limit", "2-day limit", … from a window length.
    public static func windowTitle(minutes: Int?) -> String {
        guard let minutes, minutes > 0 else { return "Usage limit" }
        switch minutes {
        case 10080: return "Weekly limit"
        case 1440: return "Daily limit"
        default:
            if minutes % 1440 == 0 { return "\(minutes / 1440)-day limit" }
            if minutes % 60 == 0 { return "\(minutes / 60)-hour limit" }
            return "\(minutes)-minute limit"
        }
    }

    public static func planName(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty, raw != "unknown" else { return nil }
        let known = ["plus": "Plus", "pro": "Pro", "prolite": "Pro Lite", "team": "Team", "free": "Free",
                     "go": "Go", "edu": "Edu", "business": "Business", "enterprise": "Enterprise"]
        if let name = known[raw] { return name }
        return raw.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    public static func limitReachedText(_ raw: String?) -> String? {
        guard let raw else { return nil }
        if raw == "rate_limit_reached" { return "Usage limit reached" }
        if raw.hasSuffix("credits_depleted") { return "Workspace credits depleted" }
        if raw.hasSuffix("usage_limit_reached") { return "Workspace usage limit reached" }
        let words = raw.replacingOccurrences(of: "_", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}

/// Reads Codex limits from the locally installed Codex CLI by running
/// `codex app-server` (line-delimited JSON-RPC over stdio). Codex owns sign-in
/// and token refresh, so the tracker never touches OpenAI credentials.
public enum CodexAppServer {
    /// Finds and asks the installed `codex`.
    public static func fetchRateLimits(timeout: TimeInterval = 20) async throws -> CodexRateLimits {
        guard let executable = locate() else { throw CodexError.notInstalled }
        return try await readRateLimits(executable: executable, timeout: timeout)
    }

    /// The `codex` binary: PATH first, then the usual install spots — launchd
    /// gives GUI apps only /usr/bin:/bin:/usr/sbin:/sbin.
    public static func locate(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: String = NSHomeDirectory(),
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
        listDirectory: (String) -> [String] = { (try? FileManager.default.contentsOfDirectory(atPath: $0)) ?? [] }
    ) -> URL? {
        var dirs = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        dirs += ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "\(home)/.npm-global/bin",
                 "\(home)/.bun/bin", "\(home)/.volta/bin", "\(home)/.cargo/bin"]
        let nvm = "\(home)/.nvm/versions/node"
        dirs += listDirectory(nvm)
            .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            .map { "\(nvm)/\($0)/bin" }
        for dir in dirs where !dir.isEmpty {
            let path = (dir as NSString).appendingPathComponent("codex")
            if isExecutable(path) { return URL(fileURLWithPath: path) }
        }
        return nil
    }

    /// The child's environment, with a PATH that can run the npm/Homebrew
    /// `#!/usr/bin/env node` launcher: the binary's own directory first (nvm
    /// and volta keep node beside it), then Homebrew, then the inherited PATH.
    public static func childEnvironment(executable: URL, base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var env = base
        var dirs = [executable.deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin"]
        dirs += (base["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin").split(separator: ":").map(String.init)
        var seen = Set<String>()
        env["PATH"] = dirs.filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: ":")
        return env
    }

    /// Runs `<executable> app-server`, sends `initialize` + `account/rateLimits/read`
    /// and parses the reply. Blocking work stays on a GCD thread, off the
    /// Swift concurrency pool.
    public static func readRateLimits(executable: URL, timeout: TimeInterval = 20) async throws -> CodexRateLimits {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(with: Result { try runSession(executable: executable, timeout: timeout) })
            }
        }
    }

    private static func runSession(executable: URL, timeout: TimeInterval) throws -> CodexRateLimits {
        let process = Process()
        process.executableURL = executable
        process.arguments = ["app-server"]
        process.environment = childEnvironment(executable: executable)
        let input = Pipe(), output = Pipe(), errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        // A server that dies before reading stdin must not SIGPIPE the whole app.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)

        let session = Session()
        // At EOF a handler keeps firing with empty data until removed.
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                session.finish(.eof)
            } else {
                session.receive(data)
            }
        }
        errors.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                session.stderrClosed()
            } else {
                session.receiveStderr(data)
            }
        }
        defer {
            output.fileHandleForReading.readabilityHandler = nil
            errors.fileHandleForReading.readabilityHandler = nil
        }
        do {
            try process.run()
        } catch {
            throw CodexError.exited(status: -1, detail: error.localizedDescription)
        }
        defer { stop(process, input: input) }

        let requests: [[String: Any]] = [
            ["id": 1, "method": "initialize", "params": [
                "clientInfo": ["name": "claude-usage-tracker", "title": "Claude Usage Tracker", "version": "1"],
                "capabilities": NSNull(),
            ]],
            ["method": "initialized"],
            ["id": 2, "method": "account/rateLimits/read"],
        ]
        for request in requests {
            guard var line = try? JSONSerialization.data(withJSONObject: request, options: .withoutEscapingSlashes) else { continue }
            line.append(0x0A)
            // A dead server surfaces as EOF on stdout below.
            do { try input.fileHandleForWriting.write(contentsOf: line) } catch { break }
        }

        switch session.wait(timeout: timeout) {
        case .response(let line):
            return try CodexRateLimits.parse(response: line)
        case .timedOut:
            throw CodexError.timeout
        case .eof:
            let status = waitForExit(process, within: 2)
            session.waitForStderr(within: 1)
            throw CodexError.exited(status: status ?? -1, detail: session.stderrText)
        }
    }

    /// Closing stdin makes app-server exit by itself; terminate it if it lingers.
    private static func stop(_ process: Process, input: Pipe) {
        try? input.fileHandleForWriting.close()
        if waitForExit(process, within: 1) == nil { process.terminate() }
    }

    private static func waitForExit(_ process: Process, within seconds: TimeInterval) -> Int32? {
        let deadline = Date().addingTimeInterval(seconds)
        while process.isRunning, Date() < deadline { usleep(20_000) }
        return process.isRunning ? nil : process.terminationStatus
    }

    /// Collects stdout lines until the answer arrives; thread-safe because the
    /// pipes' readability handlers run on their own queues.
    private final class Session: @unchecked Sendable {
        enum Outcome { case response(Data), eof, timedOut }

        private let lock = NSLock()
        private let done = DispatchSemaphore(value: 0)
        private let stderrDone = DispatchSemaphore(value: 0)
        private var outcome: Outcome?
        private var buffer = Data()
        private var stderr = Data()
        private var stderrEnded = false

        func receive(_ data: Data) {
            lock.lock(); defer { lock.unlock() }
            guard outcome == nil else { return }
            buffer.append(data)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[buffer.startIndex..<newline])
                buffer.removeSubrange(buffer.startIndex...newline)
                if Self.isAnswer(line) { finishLocked(.response(line)); return }
            }
        }

        /// The reply to request 2, or any error reply (a failed `initialize`
        /// ends the session too). Server notifications and requests carry `method`.
        private static func isAnswer(_ line: Data) -> Bool {
            guard let message = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                  message["method"] == nil else { return false }
            return message["error"] != nil || (message["id"] as? Int) == 2
        }

        func finish(_ result: Outcome) {
            lock.lock(); defer { lock.unlock() }
            finishLocked(result)
        }

        private func finishLocked(_ result: Outcome) {
            guard outcome == nil else { return }
            outcome = result
            done.signal()
        }

        func wait(timeout: TimeInterval) -> Outcome {
            if done.wait(timeout: .now() + timeout) == .timedOut { finish(.timedOut) }
            lock.lock(); defer { lock.unlock() }
            return outcome ?? .timedOut
        }

        func receiveStderr(_ data: Data) {
            lock.lock(); defer { lock.unlock() }
            if stderr.count < 16_384 { stderr.append(data) }
        }

        func stderrClosed() {
            lock.lock(); defer { lock.unlock() }
            guard !stderrEnded else { return }
            stderrEnded = true
            stderrDone.signal()
        }

        func waitForStderr(within seconds: TimeInterval) {
            _ = stderrDone.wait(timeout: .now() + seconds)
        }

        /// The last few lines of stderr, enough to say why the server died.
        var stderrText: String {
            lock.lock(); defer { lock.unlock() }
            let text = String(decoding: stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.split(separator: "\n").suffix(3).joined(separator: " · ")
        }
    }
}
