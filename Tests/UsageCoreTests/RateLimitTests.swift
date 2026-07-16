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

    @Test func requestIsMinimalAndAuthorized() throws {
        let req = RateLimitUsage.request(token: "sk-ant-oat01-abc")
        #expect(req.httpMethod == "POST")
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer sk-ant-oat01-abc")
        #expect(req.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
        let body = try #require(req.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["max_tokens"] as? Int == 1)
    }
}
