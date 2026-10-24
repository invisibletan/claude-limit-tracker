import Foundation
import Testing
@testable import UsageCore

@Suite struct CodexRateLimitsTests {
    // Shape of an `account/rateLimits/read` response from codex-cli 0.144.5
    // (app-server protocol v2), one JSON-RPC message per line.
    private let response = """
    {"id":2,"result":{"rateLimits":{"limitId":"codex","limitName":null,\
    "primary":{"usedPercent":12.5,"windowDurationMins":300,"resetsAt":1784191800},\
    "secondary":{"usedPercent":40,"windowDurationMins":10080,"resetsAt":1784379600},\
    "credits":{"hasCredits":false,"unlimited":false,"balance":null},\
    "individualLimit":null,"planType":"plus","rateLimitReachedType":null},\
    "rateLimitsByLimitId":null,"rateLimitResetCredits":null}}
    """

    @Test func parsesRateLimitsResponse() throws {
        let limits = try CodexRateLimits.parse(response: Data(response.utf8))
        let primary = try #require(limits.primary)
        #expect(primary.usedPercent == 12.5)
        #expect(primary.windowMinutes == 300)
        #expect(primary.resetsAt == Date(timeIntervalSince1970: 1_784_191_800))
        let secondary = try #require(limits.secondary)
        #expect(secondary.usedPercent == 40)
        #expect(secondary.windowMinutes == 10080)
        #expect(secondary.resetsAt == Date(timeIntervalSince1970: 1_784_379_600))
        #expect(limits.planType == "plus")
        #expect(limits.limitReached == nil)
    }

    @Test func millisecondResetTimestampsAreNormalized() throws {
        let line = #"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":1,"windowDurationMins":300,"resetsAt":1784191800000}}}}"#
        let limits = try CodexRateLimits.parse(response: Data(line.utf8))
        #expect(limits.primary?.resetsAt == Date(timeIntervalSince1970: 1_784_191_800))
    }

    @Test func absentWindowIsNil() throws {
        let line = #"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":7,"windowDurationMins":300,"resetsAt":null},"secondary":null,"planType":"pro","rateLimitReachedType":"rate_limit_reached"}}}"#
        let limits = try CodexRateLimits.parse(response: Data(line.utf8))
        #expect(limits.primary?.usedPercent == 7)
        #expect(limits.primary?.resetsAt == nil)
        #expect(limits.secondary == nil)
        #expect(limits.limitReached == "rate_limit_reached")
    }

    @Test func fallsBackToTheCodexBucket() throws {
        let line = #"{"id":2,"result":{"rateLimits":{"primary":null,"secondary":null},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":33,"windowDurationMins":300,"resetsAt":1784191800},"secondary":null,"planType":"team"}}}}"#
        let limits = try CodexRateLimits.parse(response: Data(line.utf8))
        #expect(limits.primary?.usedPercent == 33)
        #expect(limits.planType == "team")
    }

    @Test func noWindowsAtAllThrows() {
        let line = #"{"id":2,"result":{"rateLimits":{"primary":null,"secondary":null,"planType":"plus"}}}"#
        #expect(throws: CodexError.noUsageData) { try CodexRateLimits.parse(response: Data(line.utf8)) }
    }

    @Test func garbageThrowsMalformed() {
        #expect(throws: CodexError.malformedResponse) { try CodexRateLimits.parse(response: Data("not json".utf8)) }
        #expect(throws: CodexError.malformedResponse) { try CodexRateLimits.parse(response: Data(#"{"id":2}"#.utf8)) }
    }

    @Test func authErrorMeansNotLoggedIn() {
        // The exact error codex-cli 0.144.5 returns while signed out.
        let line = #"{"error":{"code":-32600,"message":"codex account authentication required to read rate limits"},"id":2}"#
        #expect(throws: CodexError.notLoggedIn) { try CodexRateLimits.parse(response: Data(line.utf8)) }
    }

    @Test func otherRPCErrorsKeepTheirMessage() {
        let line = #"{"error":{"code":-32603,"message":"backend unavailable"},"id":2}"#
        #expect(throws: CodexError.rpc("backend unavailable")) { try CodexRateLimits.parse(response: Data(line.utf8)) }
    }
}

@Suite struct CodexSnapshotTests {
    private let now = Date(timeIntervalSince1970: 1_784_180_000)

    private func window(_ percent: Double, minutes: Int?, resetsIn seconds: TimeInterval?) -> CodexRateLimits.Window {
        .init(usedPercent: percent, windowMinutes: minutes, resetsAt: seconds.map { now.addingTimeInterval($0) })
    }

    @Test func standardWindowsMapToSessionAndWeekly() {
        let limits = CodexRateLimits(
            primary: window(30, minutes: 300, resetsIn: 2.5 * 3600),
            secondary: window(10, minutes: 10080, resetsIn: 3 * 86400),
            planType: "pro", limitReached: nil)
        let snap = CodexSnapshot.build(from: limits, now: now)
        #expect(snap.sessionTitle == "5-hour limit")
        #expect(snap.weeklyTitle == "Weekly limit")
        #expect(snap.usage.fiveHour.percent == 30)
        #expect(snap.usage.weekly.percent == 10)
        #expect(snap.usage.fableWeekly == nil)
        #expect(snap.usage.updatedAt == now)
        // Half of the 5-hour window elapsed with 30% used → ratio 0.6 → slow.
        #expect(snap.usage.fiveHour.pace?.state == .slow)
        #expect(snap.usage.fiveHour.resetText == "resets in 2h 30m")
        #expect(snap.planName == "Pro")
        #expect(snap.limitReachedText == nil)
    }

    @Test func windowsAreOrderedByLengthNotPosition() {
        let limits = CodexRateLimits(
            primary: window(10, minutes: 10080, resetsIn: 86400),
            secondary: window(60, minutes: 300, resetsIn: 3600),
            planType: nil, limitReached: nil)
        let snap = CodexSnapshot.build(from: limits, now: now)
        #expect(snap.sessionTitle == "5-hour limit")
        #expect(snap.usage.fiveHour.percent == 60)
        #expect(snap.weeklyTitle == "Weekly limit")
        #expect(snap.usage.weekly.percent == 10)
    }

    @Test func aLoneWindowTakesTheSessionSlot() {
        let limits = CodexRateLimits(primary: window(40, minutes: 10080, resetsIn: 86400), secondary: nil,
                                     planType: "free", limitReached: nil)
        let snap = CodexSnapshot.build(from: limits, now: now)
        #expect(snap.sessionTitle == "Weekly limit")
        #expect(snap.usage.fiveHour.percent == 40)
        #expect(snap.weeklyTitle == nil)
        #expect(snap.usage.weekly.percent == nil)
    }

    @Test func paceUsesTheWindowsRealLength() {
        // A 1-day window, 12h in, 50% used → exactly even. Assuming 5 hours would
        // put the window start in the future and lose the pace entirely.
        let limits = CodexRateLimits(primary: window(50, minutes: 1440, resetsIn: 12 * 3600), secondary: nil,
                                     planType: nil, limitReached: nil)
        let snap = CodexSnapshot.build(from: limits, now: now)
        #expect(snap.usage.fiveHour.pace?.state == .steady)
    }

    @Test func percentIsClampedForDisplay() {
        let limits = CodexRateLimits(primary: window(130, minutes: 300, resetsIn: 600),
                                     secondary: window(-5, minutes: 10080, resetsIn: 86400),
                                     planType: nil, limitReached: "rate_limit_reached")
        let snap = CodexSnapshot.build(from: limits, now: now)
        #expect(snap.usage.fiveHour.percent == 100)
        #expect(snap.usage.weekly.percent == 0)
        #expect(snap.limitReachedText == "Usage limit reached")
    }

    @Test func windowTitles() {
        #expect(CodexSnapshot.windowTitle(minutes: 300) == "5-hour limit")
        #expect(CodexSnapshot.windowTitle(minutes: 10080) == "Weekly limit")
        #expect(CodexSnapshot.windowTitle(minutes: 1440) == "Daily limit")
        #expect(CodexSnapshot.windowTitle(minutes: 2880) == "2-day limit")
        #expect(CodexSnapshot.windowTitle(minutes: 120) == "2-hour limit")
        #expect(CodexSnapshot.windowTitle(minutes: 90) == "90-minute limit")
        #expect(CodexSnapshot.windowTitle(minutes: nil) == "Usage limit")
    }

    @Test func planNames() {
        #expect(CodexSnapshot.planName("plus") == "Plus")
        #expect(CodexSnapshot.planName("prolite") == "Pro Lite")
        #expect(CodexSnapshot.planName("some_new_plan") == "Some New Plan")
        #expect(CodexSnapshot.planName("unknown") == nil)
        #expect(CodexSnapshot.planName(nil) == nil)
    }

    @Test func limitReachedTexts() {
        #expect(CodexSnapshot.limitReachedText("workspace_member_credits_depleted") == "Workspace credits depleted")
        #expect(CodexSnapshot.limitReachedText("workspace_owner_usage_limit_reached") == "Workspace usage limit reached")
        #expect(CodexSnapshot.limitReachedText(nil) == nil)
    }

    @Test func windowSecondsPaceMatchesTheFixedFiveHourWindow() {
        let resets = now.addingTimeInterval(3600)
        #expect(Pace.compute(percent: 50, resetsAt: resets, windowSeconds: 5 * 3600, now: now)
                == Pace.compute(percent: 50, resetsAt: resets, window: .fiveHour, now: now))
    }

    @Test func menuBarEntryCarriesTheTag() {
        let entry = MenuBarEntry(name: nil, snapshot: nil, tag: "CX")
        #expect(entry.tag == "CX")
        #expect(entry.showsWeekly)
        #expect(MenuBarEntry(name: nil, snapshot: nil).tag == nil)
    }
}

@Suite struct CodexLocateTests {
    private let home = "/Users/x"

    @Test func usesPATHFirst() {
        let found = CodexAppServer.locate(environment: ["PATH": "/a:/b"], home: home,
                                          isExecutable: { $0 == "/b/codex" || $0 == "/opt/homebrew/bin/codex" })
        #expect(found?.path == "/b/codex")
    }

    @Test func fallsBackToHomebrewUnderLaunchdsPATH() {
        let found = CodexAppServer.locate(environment: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"], home: home,
                                          isExecutable: { $0 == "/opt/homebrew/bin/codex" })
        #expect(found?.path == "/opt/homebrew/bin/codex")
    }

    @Test func findsUserLevelInstalls() {
        let found = CodexAppServer.locate(environment: [:], home: home,
                                          isExecutable: { $0 == "/Users/x/.local/bin/codex" })
        #expect(found?.path == "/Users/x/.local/bin/codex")
    }

    @Test func findsTheNewestNvmNode() {
        let found = CodexAppServer.locate(
            environment: [:], home: home,
            isExecutable: { $0.hasPrefix("/Users/x/.nvm/versions/node/") },
            listDirectory: { $0 == "/Users/x/.nvm/versions/node" ? ["v18.20.4", "v22.11.0", "v9.0.0"] : [] })
        #expect(found?.path == "/Users/x/.nvm/versions/node/v22.11.0/bin/codex")
    }

    @Test func nilWhenNotInstalled() {
        #expect(CodexAppServer.locate(environment: ["PATH": "/usr/bin"], home: home, isExecutable: { _ in false }) == nil)
    }

    @Test func childPATHCanFindNode() {
        // Homebrew/npm `codex` is `#!/usr/bin/env node`; under launchd's PATH
        // that dies with "env: node: No such file or directory".
        let env = CodexAppServer.childEnvironment(
            executable: URL(fileURLWithPath: "/Users/x/.nvm/versions/node/v22.11.0/bin/codex"),
            base: ["PATH": "/usr/bin:/bin", "HOME": "/Users/x"])
        let dirs = (env["PATH"] ?? "").split(separator: ":").map(String.init)
        #expect(dirs.first == "/Users/x/.nvm/versions/node/v22.11.0/bin")
        #expect(dirs.contains("/opt/homebrew/bin"))
        #expect(dirs.contains("/usr/bin"))
        #expect(Set(dirs).count == dirs.count)
        #expect(env["HOME"] == "/Users/x")
    }
}

@Suite struct CodexAppServerTests {
    /// A stand-in `codex` executable: a bash script speaking the app-server's
    /// line-delimited JSON-RPC on stdin/stdout.
    private func fakeCodex(_ body: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fake-codex-\(UUID().uuidString)")
        try ("#!/bin/bash\n" + body + "\n").write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private func responder(rateLimitsReply: String) -> String {
        """
        [ "$1" = "app-server" ] || { echo "unexpected args: $*" >&2; exit 2; }
        while IFS= read -r line; do
          case "$line" in
            *'"initialize"'*) echo '{"id":1,"result":{"userAgent":"fake"}}' ;;
            *'account/rateLimits/read'*)
              echo '{"method":"remoteControl/status/changed","params":{"status":"disabled"}}'
              echo '\(rateLimitsReply)' ;;
          esac
        done
        """
    }

    @Test func readsRateLimitsOverStdio() async throws {
        let exe = try fakeCodex(responder(rateLimitsReply:
            #"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":12,"windowDurationMins":300,"resetsAt":1784191800},"secondary":null,"planType":"plus"}}}"#))
        defer { try? FileManager.default.removeItem(at: exe) }
        let limits = try await CodexAppServer.readRateLimits(executable: exe, timeout: 10)
        #expect(limits.primary?.usedPercent == 12)
        #expect(limits.planType == "plus")
    }

    @Test func signedOutServerMeansNotLoggedIn() async throws {
        let exe = try fakeCodex(responder(rateLimitsReply:
            #"{"error":{"code":-32600,"message":"codex account authentication required to read rate limits"},"id":2}"#))
        defer { try? FileManager.default.removeItem(at: exe) }
        await #expect(throws: CodexError.notLoggedIn) {
            try await CodexAppServer.readRateLimits(executable: exe, timeout: 10)
        }
    }

    @Test func silentServerTimesOutPromptly() async throws {
        let exe = try fakeCodex("exec sleep 30")
        defer { try? FileManager.default.removeItem(at: exe) }
        let start = Date()
        await #expect(throws: CodexError.timeout) {
            try await CodexAppServer.readRateLimits(executable: exe, timeout: 0.5)
        }
        #expect(Date().timeIntervalSince(start) < 5)
    }

    @Test func crashReportsExitStatusAndStderr() async throws {
        let exe = try fakeCodex(#"echo "env: node: No such file or directory" >&2; exit 127"#)
        defer { try? FileManager.default.removeItem(at: exe) }
        await #expect(throws: CodexError.exited(status: 127, detail: "env: node: No such file or directory")) {
            try await CodexAppServer.readRateLimits(executable: exe, timeout: 10)
        }
    }
}
