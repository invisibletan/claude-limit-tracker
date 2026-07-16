import AppKit
import WebKit
import UsageCore

enum WebUsageResult {
    case windows([WebWindow])
    case needsLogin
    case unavailable(String)
}

/// Reads the exact usage numbers off claude.ai Settings → Usage using a
/// claude.ai session that lives entirely inside this app. The user signs in
/// once in an in-app web view; cookies persist in the app's own data store
/// (never shared with Safari/Chrome, never handled as raw text). Injected
/// JavaScript reads the numbers the same way the page renders them, so no
/// Anthropic API needs to be reverse-engineered.
@MainActor
final class WebUsageReader: NSObject {
    static let shared = WebUsageReader()

    private let usageURL = URL(string: "https://claude.ai/settings/usage")!
    private let loginURL = URL(string: "https://claude.ai/login")!

    // Persistent so the login survives relaunches.
    private let dataStore = WKWebsiteDataStore.default()

    private var reader: WKWebView?
    private var pending: CheckedContinuation<WebUsageResult, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var loginWindow: NSWindow?

    private func makeConfiguration(handlerName: String) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStore
        let controller = WKUserContentController()
        controller.add(self, name: handlerName)
        controller.addUserScript(WKUserScript(
            source: Self.injectedJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        config.userContentController = controller
        return config
    }

    /// Navigate the off-screen reader to the usage page and await the result.
    func fetchOfficial(timeout: TimeInterval = 25) async -> WebUsageResult {
        if pending != nil { return .unavailable("A read is already in progress.") }

        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 1200, height: 900),
            configuration: makeConfiguration(handlerName: "usage")
        )
        webView.navigationDelegate = self
        reader = webView

        return await withCheckedContinuation { continuation in
            pending = continuation
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                self?.finish(.unavailable("Timed out reading the usage page."))
            }
            webView.load(URLRequest(url: usageURL))
        }
    }

    private func finish(_ result: WebUsageResult) {
        timeoutTask?.cancel()
        timeoutTask = nil
        reader?.navigationDelegate = nil
        reader?.configuration.userContentController.removeAllScriptMessageHandlers()
        reader = nil
        if let continuation = pending {
            pending = nil
            continuation.resume(returning: result)
        }
    }

    /// Opens a visible sign-in window on the same data store.
    func showLogin() {
        if let existing = loginWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStore
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 720), configuration: config)
        webView.load(URLRequest(url: loginURL))

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 720),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sign in to Claude"
        window.contentView = webView
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        loginWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Clears the persisted claude.ai cookies (sign out).
    func signOut() async {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await dataStore.dataRecords(ofTypes: types)
        let claude = records.filter { $0.displayName.contains("claude") || $0.displayName.contains("anthropic") }
        await dataStore.removeData(ofTypes: types, for: claude)
    }

    /// Best-effort check for a stored claude.ai session cookie.
    func hasSession() async -> Bool {
        let cookies = await dataStore.httpCookieStore.allCookies()
        return cookies.contains { $0.domain.contains("claude.ai") && $0.name.hasPrefix("sessionKey") }
    }
}

extension WebUsageReader: WKScriptMessageHandler {
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard pending != nil, let body = message.body as? [String: Any] else { return }
        let loggedIn = (body["loggedIn"] as? Bool) ?? true
        let rawWindows = (body["windows"] as? [[String: Any]]) ?? []
        let windows: [WebWindow] = rawWindows.compactMap { entry in
            guard let label = entry["label"] as? String,
                  let percent = (entry["percent"] as? NSNumber)?.doubleValue else { return nil }
            return WebWindow(
                label: label,
                percent: percent,
                resetText: (entry["resetText"] as? String) ?? ""
            )
        }
        if !loggedIn {
            finish(.needsLogin)
        } else if !windows.isEmpty {
            finish(.windows(windows))
        }
        // Logged in but nothing parsed yet — wait for a later message / the timeout.
    }
}

extension WebUsageReader: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor [weak self] in self?.finish(.unavailable(error.localizedDescription)) }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor [weak self] in self?.finish(.unavailable(error.localizedDescription)) }
    }
}

extension WebUsageReader: NSWindowDelegate {
    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor [weak self] in self?.loginWindow = nil }
    }
}

extension WebUsageReader {
    /// Runs on claude.ai/settings/usage. Reports login state and the usage
    /// windows, preferring the page's own network JSON and falling back to the
    /// rendered DOM. Polls briefly because the SPA fills in asynchronously.
    static let injectedJS = #"""
    (function () {
      if (window.__usageReaderInstalled) return;
      window.__usageReaderInstalled = true;

      var networkWindows = [];

      function normalizeUtil(v) {
        if (typeof v !== 'number' || isNaN(v)) return null;
        return v <= 1 ? v * 100 : v;
      }

      // Collect windows from any JSON body carrying a numeric "utilization".
      function scanJSON(obj) {
        try {
          for (var key in obj) {
            var val = obj[key];
            if (val && typeof val === 'object') {
              if (typeof val.utilization === 'number') {
                var pct = normalizeUtil(val.utilization);
                if (pct !== null) {
                  networkWindows.push({
                    label: prettyKey(key),
                    percent: pct,
                    resetText: val.resets_at ? ('Resets ' + val.resets_at) : ''
                  });
                }
              }
              scanJSON(val);
            }
          }
        } catch (e) {}
      }

      function prettyKey(k) {
        if (k === 'five_hour') return 'Current session';
        if (k === 'seven_day') return 'All models';
        return k.replace(/_/g, ' ').replace(/\b\w/g, function (c) { return c.toUpperCase(); });
      }

      // Hook fetch.
      var origFetch = window.fetch;
      if (origFetch) {
        window.fetch = function () {
          return origFetch.apply(this, arguments).then(function (resp) {
            try {
              var ct = resp.headers.get('content-type') || '';
              if (ct.indexOf('json') !== -1) {
                resp.clone().json().then(scanJSON).catch(function () {});
              }
            } catch (e) {}
            return resp;
          });
        };
      }
      // Hook XHR.
      var origOpen = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function () {
        this.addEventListener('load', function () {
          try {
            var ct = this.getResponseHeader('content-type') || '';
            if (ct.indexOf('json') !== -1) scanJSON(JSON.parse(this.responseText));
          } catch (e) {}
        });
        return origOpen.apply(this, arguments);
      };

      function scrapeDOM() {
        var out = [];
        var text = document.body ? document.body.innerText : '';
        // Find "<label> ... <n>% used" rows, keeping nearby "Resets ..." text.
        var lines = text.split('\n').map(function (l) { return l.trim(); }).filter(Boolean);
        var labels = ['Current session', 'All models'];
        // Also treat standalone model names before a "% used" as labels.
        for (var i = 0; i < lines.length; i++) {
          var m = lines[i].match(/(\d+)%\s*used/i);
          if (!m) continue;
          var pct = parseInt(m[1], 10);
          // Search backwards for the nearest label-ish line.
          var label = '';
          for (var j = i; j >= 0 && j > i - 4; j--) {
            var cand = lines[j].replace(/\d+%\s*used/i, '').trim();
            if (cand && !/^resets/i.test(cand)) { label = cand; break; }
          }
          // Search forward for a Resets line.
          var reset = '';
          for (var k = i; k < lines.length && k < i + 4; k++) {
            if (/resets/i.test(lines[k])) { reset = lines[k]; break; }
          }
          if (label) out.push({ label: label, percent: pct, resetText: reset });
        }
        return out;
      }

      function isLoggedIn() {
        if (/\/login/.test(location.pathname)) return false;
        var t = document.body ? document.body.innerText : '';
        if (/log in|sign in to continue/i.test(t) && !/usage/i.test(t)) return false;
        return true;
      }

      function report(force) {
        var loggedIn = isLoggedIn();
        var windows = networkWindows.length ? dedupe(networkWindows) : scrapeDOM();
        if (!loggedIn) {
          post({ loggedIn: false, windows: [] });
          return true;
        }
        if (windows.length || force) {
          post({ loggedIn: true, windows: windows });
          return windows.length > 0;
        }
        return false;
      }

      function dedupe(arr) {
        var seen = {}, out = [];
        arr.forEach(function (w) {
          if (!seen[w.label]) { seen[w.label] = 1; out.push(w); }
        });
        return out;
      }

      function post(payload) {
        try { window.webkit.messageHandlers.usage.postMessage(payload); } catch (e) {}
      }

      // Poll for up to ~20s; the SPA renders usage asynchronously.
      var tries = 0;
      var timer = setInterval(function () {
        tries++;
        var done = report(tries >= 40);
        if (done || tries >= 40) clearInterval(timer);
      }, 500);
    })();
    """#
}
