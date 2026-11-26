import Foundation
import UsageKit

/// Claude Code: OAuth token from the "Claude Code-credentials" keychain item
/// (or ~/.claude/.credentials.json), usage from the same endpoint `/usage` uses.
enum ClaudeProvider {
    static func load() async throws -> ProviderUsage {
        let raw = Keychain.password(service: "Claude Code-credentials")
            ?? (try? String(contentsOf: homeFile(".claude/.credentials.json"), encoding: .utf8))
        guard let raw, let creds = parseJSON(Data(raw.utf8))?["claudeAiOauth"] as? JSON,
              let token = creds["accessToken"] as? String
        else { throw UsageError("Not signed in — run `claude` to log in") }

        let profile = (try? Data(contentsOf: homeFile(".claude.json"))).flatMap(parseJSON)?["oauthAccount"] as? JSON
        var usage = ProviderUsage(kind: .claude, plan: plan(creds), account: profile?["emailAddress"] as? String)
        if let exp = num(creds["expiresAt"]), exp / 1000 < Date().timeIntervalSince1970 {
            throw UsageError("Sign-in expired — open Claude Code once to refresh it")
        }

        // `cedar_ember=1` adds limit-reset grants ("reset cards"); they're only reported to Claude Code itself.
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage?cedar_ember=1&skip_spend=1")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("claude-cli/2.1.332 (external, cli)", forHTTPHeaderField: "User-Agent")
        req.setValue("cli", forHTTPHeaderField: "x-app")
        let json = try await HTTP.json(req)
        if let ember = json["cedar_ember"] as? JSON, ember["eligible"] as? Bool != false {
            usage.resetCards = (ember["grants"] as? [JSON] ?? []).reduce(0) { $0 + Int(num($1["resets_left"]) ?? 0) }
        }

        func window(_ label: String, _ w: JSON?, _ key: String = "utilization") -> UsageWindow? {
            guard let w, let pct = num(w[key]) else { return nil }
            return UsageWindow(label: label, used: pct / 100, resetsAt: .iso(w["resets_at"]))
        }

        var windows = [
            window("5-hour session", json["five_hour"] as? JSON),
            window("Weekly · all models", json["seven_day"] as? JSON),
        ]
        if let limits = json["limits"] as? [JSON] {
            for l in limits where l["kind"] as? String == "weekly_scoped" {
                let model = ((l["scope"] as? JSON)?["model"] as? JSON)?["display_name"] as? String
                windows.append(window("Weekly · \(model ?? "scoped")", l, "percent"))
            }
        } else {
            windows.append(window("Weekly · Opus", json["seven_day_opus"] as? JSON))
            windows.append(window("Weekly · Sonnet", json["seven_day_sonnet"] as? JSON))
        }
        usage.windows = windows.compactMap { $0 }
        return usage
    }

    /// "max" + "default_claude_max_5x" → "Max 5×"
    private static func plan(_ creds: JSON) -> String? {
        guard let sub = (creds["subscriptionType"] as? String)?.capitalized else { return nil }
        let tier = creds["rateLimitTier"] as? String ?? ""
        guard let r = tier.range(of: #"\d+x$"#, options: .regularExpression) else { return sub }
        return "\(sub) \(tier[r].dropLast())×"
    }
}
