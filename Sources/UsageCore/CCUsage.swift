import Foundation

/// Parsing for `ccusage` JSON output — the zero-config estimate source that
/// reads the session logs Claude Code already writes under `~/.claude`.
public enum CCUsage {
    /// The currently active 5-hour billing block from `ccusage blocks --active --json`.
    public struct ActiveBlock: Sendable {
        public var costUSD: Double
        public var totalTokens: Double
        public var endTime: Date?
        public var tokensPerMinute: Double?
        public var projectedCostUSD: Double?

        public init(
            costUSD: Double,
            totalTokens: Double,
            endTime: Date? = nil,
            tokensPerMinute: Double? = nil,
            projectedCostUSD: Double? = nil
        ) {
            self.costUSD = costUSD
            self.totalTokens = totalTokens
            self.endTime = endTime
            self.tokensPerMinute = tokensPerMinute
            self.projectedCostUSD = projectedCostUSD
        }
    }

    /// Returns nil when there is no active block (idle for 5+ hours).
    public static func parseActiveBlock(_ data: Data) throws -> ActiveBlock? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let blocks = root["blocks"] as? [[String: Any]] else {
            throw CCUsageError.malformedOutput("blocks")
        }
        guard let block = blocks.first(where: { ($0["isActive"] as? Bool) == true }) else {
            return nil
        }
        let cost = (block["costUSD"] as? NSNumber)?.doubleValue ?? 0
        let tokens = (block["totalTokens"] as? NSNumber)?.doubleValue ?? 0
        var endTime: Date?
        if let stamp = block["endTime"] as? String {
            endTime = OfficialAPI.parseISO8601(stamp)
        }
        let burn = block["burnRate"] as? [String: Any]
        let projection = block["projection"] as? [String: Any]
        return ActiveBlock(
            costUSD: cost,
            totalTokens: tokens,
            endTime: endTime,
            tokensPerMinute: (burn?["tokensPerMinute"] as? NSNumber)?.doubleValue,
            projectedCostUSD: (projection?["totalCost"] as? NSNumber)?.doubleValue
        )
    }

    /// Sums `totalCost` across all rows of `ccusage daily --json --since <date>`.
    /// Accepts both `{"daily": [...]}` and a bare top-level array — ccusage
    /// emits `[]` when the requested range contains no data.
    public static func parseDailyTotalCost(_ data: Data) throws -> Double {
        let root = try? JSONSerialization.jsonObject(with: data)
        let daily: [[String: Any]]
        if let dict = root as? [String: Any], let rows = dict["daily"] as? [[String: Any]] {
            daily = rows
        } else if let rows = root as? [[String: Any]] {
            daily = rows
        } else if let empty = root as? [Any], empty.isEmpty {
            daily = []
        } else {
            throw CCUsageError.malformedOutput("daily")
        }
        return daily.reduce(0) { $0 + ((($1["totalCost"]) as? NSNumber)?.doubleValue ?? 0) }
    }
}

public enum CCUsageError: Error, LocalizedError {
    case binaryNotFound
    case malformedOutput(String)
    case processFailed(Int32, String)
    case timedOut

    public var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "ccusage not found — install with `npm i -g ccusage` or set its path in Preferences."
        case .malformedOutput(let key):
            return "Unexpected ccusage output (missing \"\(key)\")."
        case .processFailed(let code, let stderr):
            return "ccusage exited with status \(code): \(stderr.prefix(120))"
        case .timedOut:
            return "ccusage timed out."
        }
    }
}

/// Locates and runs the ccusage binary.
public struct CCUsageRunner: Sendable {
    public var overridePath: String?

    public init(overridePath: String? = nil) {
        self.overridePath = overridePath
    }

    public static func candidatePaths(home: String = NSHomeDirectory()) -> [String] {
        [
            "/opt/homebrew/bin/ccusage",
            "/usr/local/bin/ccusage",
            "\(home)/.bun/bin/ccusage",
            "\(home)/.local/bin/ccusage",
            "\(home)/.npm-global/bin/ccusage",
        ]
    }

    public func resolveBinary() -> String? {
        if let overridePath, !overridePath.isEmpty {
            return FileManager.default.isExecutableFile(atPath: overridePath) ? overridePath : nil
        }
        return Self.candidatePaths().first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public func run(_ arguments: [String], timeout: TimeInterval = 30) async throws -> Data {
        guard let binary = resolveBinary() else { throw CCUsageError.binaryNotFound }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: binary)
                process.arguments = arguments
                var env = ProcessInfo.processInfo.environment
                env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
                process.environment = env
                let stdout = Pipe()
                let stderr = Pipe()
                process.standardOutput = stdout
                process.standardError = stderr

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)

                let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let timedOut = killer.isCancelled == false && process.terminationReason == .uncaughtSignal
                killer.cancel()

                if timedOut {
                    continuation.resume(throwing: CCUsageError.timedOut)
                } else if process.terminationStatus != 0 {
                    let message = String(data: errData, encoding: .utf8) ?? ""
                    continuation.resume(throwing: CCUsageError.processFailed(process.terminationStatus, message))
                } else {
                    continuation.resume(returning: outData)
                }
            }
        }
    }

    /// `--since` date for a trailing window, always Gregorian `yyyyMMdd`.
    /// Explicit calendar + POSIX locale: on devices set to a non-Gregorian
    /// system calendar (e.g. Thai Buddhist, where 2026 renders as 2569),
    /// `Calendar.current`/default formatters produce a date ccusage
    /// interprets as far future and returns nothing for.
    public static func sinceString(daysBack: Int, from now: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let since = calendar.date(byAdding: .day, value: -(daysBack - 1), to: now) ?? now
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: since)
    }

    /// The currently active 5-hour block, or nil when idle.
    public func fetchActiveBlock() async throws -> CCUsage.ActiveBlock? {
        let data = try await run(["blocks", "--active", "--json"])
        return try CCUsage.parseActiveBlock(data)
    }

    /// Total cost over the trailing 7 days.
    public func fetchWeeklyCost(now: Date = Date()) async throws -> Double {
        let since = Self.sinceString(daysBack: 7, from: now)
        let data = try await run(["daily", "--json", "--since", since])
        return try CCUsage.parseDailyTotalCost(data)
    }

    /// Fetches the active block and trailing-7-day total cost in one call.
    public func fetchEstimate(now: Date = Date()) async throws -> (block: CCUsage.ActiveBlock?, weeklyCostUSD: Double) {
        let block = try await fetchActiveBlock()
        let weeklyCost = try await fetchWeeklyCost(now: now)
        return (block, weeklyCost)
    }
}
