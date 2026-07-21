import Foundation
import Testing
@testable import UsageCore

@Suite struct RateLimitTests {
    // Captured from a real /v1/messages response.
    private let headers = [
        "anthropic-ratelimit-unified-status": "allowed",
        "anthropic-ratelimit-unified-5h-status": "allowed",
        "anthropic-ratelimit-unified-5h-reset": "1784191800",
        "anthropic-ratelimit-unified-5h-utilization": "0.27",
        "anthropic-ratelimit-unified-7d-status": "allowed",
        "anthropic-ratelimit-unified-7d-reset": "1784379600",
        "anthropic-ratelimit-unified-7d-utilization": "0.07",
        "anthropic-ratelimit-unified-representative-claim": "five_hour",
    ]

    @Test func parsesRealHeaders() throws {
        let usage = try RateLimitUsage.parseHeaders(headers)
        #expect(usage.windows.count == 2)
        let five = try #require(usage.fiveHour)
        #expect(five.utilization == 27)           // 0.27 → 27%
        #expect(five.label == "5-hour limit")
        #expect(five.resetsAt == Date(timeIntervalSince1970: 1_784_191_800))
        let week = try #require(usage.sevenDay)
        #expect(abs(week.utilization - 7) < 0.0001)   // 0.07 → 7%
        #expect(week.resetsAt == Date(timeIntervalSince1970: 1_784_379_600))
    }

    @Test func headerKeysAreCaseInsensitive() throws {
        let upper = [
            "Anthropic-RateLimit-Unified-5h-Utilization": "0.5",
            "Anthropic-RateLimit-Unified-5h-Reset": "1784191800",
        ]
        let usage = try RateLimitUsage.parseHeaders(upper)
        #expect(usage.fiveHour?.utilization == 50)
    }

    @Test func alreadyPercentScaleNotDoubled() throws {
        // Defensive: if a future payload reports 0–100, don't multiply again.
        let usage = try RateLimitUsage.parseHeaders(["anthropic-ratelimit-unified-5h-utilization": "42"])
        #expect(usage.fiveHour?.utilization == 42)
    }

    @Test func missingHeadersThrow() {
        #expect(throws: RateLimitError.self) {
            try RateLimitUsage.parseHeaders(["content-type": "application/json"])
        }
    }

    // Captured from a real claude-fable-5 /v1/messages response — the Fable
    // weekly window (7d_oi) only appears on calls to the Fable model.
    @Test func parsesFableWeeklyWindow() throws {
        var withFable = headers
        withFable["anthropic-ratelimit-unified-7d_oi-status"] = "allowed_warning"
        withFable["anthropic-ratelimit-unified-7d_oi-reset"] = "1784379600"
        withFable["anthropic-ratelimit-unified-7d_oi-utilization"] = "0.78"
        let usage = try RateLimitUsage.parseHeaders(withFable)
        #expect(usage.windows.count == 3)
        let fable = try #require(usage.fableWeekly)
        #expect(abs(fable.utilization - 78) < 0.0001)
        #expect(fable.label == "Weekly limit (Fable)")
        #expect(fable.resetsAt == Date(timeIntervalSince1970: 1_784_379_600))
    }

    @Test func fableWindowAbsentOnFallbackHeaders() throws {
        // A Haiku fallback probe returns only 5h + 7d — fableWeekly stays nil.
        let usage = try RateLimitUsage.parseHeaders(headers)
        #expect(usage.fableWeekly == nil)
        #expect(usage.windows.count == 2)
    }

    @Test func requestIsMinimalAndAuthorized() throws {
        let req = RateLimitUsage.request(token: "sk-ant-oat01-abc")
        #expect(req.httpMethod == "POST")
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer sk-ant-oat01-abc")
        #expect(req.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
        let body = try #require(req.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["max_tokens"] as? Int == 1)
        // The DEFAULT probe must stay the cheap, widely-compatible Haiku body —
        // guard against a regression to a pricier/less-compatible default.
        #expect(json["model"] as? String == "claude-haiku-4-5-20251001")
        #expect(json["system"] == nil)
    }

    @Test func fallsBackToHaikuOnlyForFableUnavailableFailures() {
        // Fable-specific unavailability (plan without Fable / model gone /
        // Fable-overage rejected / no usage headers) → retry on Haiku.
        #expect(RateLimitUsage.shouldFallBackToHaiku(RateLimitError.httpStatus(403)))
        #expect(RateLimitUsage.shouldFallBackToHaiku(RateLimitError.httpStatus(404)))
        #expect(RateLimitUsage.shouldFallBackToHaiku(RateLimitError.httpStatus(429)))
        #expect(RateLimitUsage.shouldFallBackToHaiku(RateLimitError.noHeaders))
        // Failures that would fail identically on Haiku → propagate, don't
        // double the latency/cost with a doomed second probe.
        #expect(!RateLimitUsage.shouldFallBackToHaiku(RateLimitError.httpStatus(401)))
        #expect(!RateLimitUsage.shouldFallBackToHaiku(RateLimitError.httpStatus(500)))
        #expect(!RateLimitUsage.shouldFallBackToHaiku(URLError(.notConnectedToInternet)))
    }

    @Test func primaryProbeTargetsFableWithClaudeCodeSystemPrompt() throws {
        // The Fable weekly header only comes back on a Fable-model call, and an
        // OAuth inference token gets a headerless 429 on premium models unless
        // the request declares the Claude Code system prompt.
        let req = RateLimitUsage.request(token: "sk-ant-oat01-abc", probe: .fable)
        let body = try #require(req.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["model"] as? String == "claude-fable-5")
        #expect(json["max_tokens"] as? Int == 1)
        #expect((json["system"] as? String)?.hasPrefix("You are Claude Code") == true)
    }

    @Test func fallbackProbeStaysOnHaikuWithoutSystemPrompt() throws {
        let req = RateLimitUsage.request(token: "sk-ant-oat01-abc", probe: .haiku)
        let body = try #require(req.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["model"] as? String == "claude-haiku-4-5-20251001")
        #expect(json["system"] == nil)
    }
}
