import Foundation
import UsageKit

/// Codex: ChatGPT token from ~/.codex/auth.json, usage from the endpoint Codex's `/status` uses.
enum CodexProvider {
    static func load() async throws -> ProviderUsage {
        guard let data = try? Data(contentsOf: homeFile(".codex/auth.json")),
              let tokens = parseJSON(data)?["tokens"] as? JSON,
              let token = tokens["access_token"] as? String
        else { throw UsageError("Not signed in — run `codex login`") }
        if let exp = num(jwtPayload(token)?["exp"]), Date(timeIntervalSince1970: exp) < Date() {
            throw UsageError("Sign-in expired — open Codex once to refresh it")
        }

        var req = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("codex-cli", forHTTPHeaderField: "User-Agent")
        if let account = tokens["account_id"] as? String {
            req.setValue(account, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        let json = try await HTTP.json(req)

        let email = (tokens["id_token"] as? String).flatMap(jwtPayload)?["email"] as? String
        var usage = ProviderUsage(kind: .codex, plan: plan(json["plan_type"] as? String), account: email)
        var windows: [(seconds: Double, window: UsageWindow)] = []
        func collect(_ limit: Any?, prefix: String? = nil) {
            for key in ["primary_window", "secondary_window"] {
                guard let w = (limit as? JSON)?[key] as? JSON, let pct = num(w["used_percent"]) else { continue }
                let seconds = num(w["limit_window_seconds"]) ?? 0
                let reset = num(w["reset_at"]).map { Date(timeIntervalSince1970: $0) }
                    ?? num(w["reset_after_seconds"]).map { Date().addingTimeInterval($0) }
                let label = [prefix, windowName(seconds)].compactMap { $0 }.joined(separator: " · ")
                windows.append((seconds, UsageWindow(label: label, used: pct / 100, resetsAt: reset)))
            }
        }
        collect(json["rate_limit"])
        collect(json["code_review_rate_limit"], prefix: "Code review")
        usage.windows = windows.sorted { $0.seconds < $1.seconds }.map(\.window)
        if let resets = num((json["rate_limit_reset_credits"] as? JSON)?["available_count"]) {
            usage.balances.append(.resets(Int(resets)))
        }
        if let credits = json["credits"] as? JSON {
            let help = "Codex credits, used once your plan's limits run out"
            usage.balances.append(credits["unlimited"] as? Bool == true
                ? Balance(symbol: "creditcard.fill", text: "Unlimited credits", available: true, help: help)
                : .credits(num(credits["balance"]) ?? 0, unit: "credits", help: help))
        }
        return usage
    }

    private static func windowName(_ seconds: Double) -> String {
        switch seconds {
        case 18_000: "5-hour session"
        case 518_400.0...: "Weekly"
        case 86_400.0...: "\(Int(seconds / 86_400))-day"
        case 1.0...: "\(Int(seconds / 3_600))-hour"
        default: "Limit"
        }
    }

    /// "self_serve_business_prolite" → "Business Prolite"
    private static func plan(_ raw: String?) -> String? {
        raw?.replacingOccurrences(of: "self_serve_", with: "")
            .split(separator: "_").map(\.capitalized).joined(separator: " ")
    }

    private static func jwtPayload(_ jwt: String) -> JSON? {
        let parts = jwt.split(separator: ".")
        guard parts.count > 1 else { return nil }
        var b64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        b64 += String(repeating: "=", count: (4 - b64.count % 4) % 4)
        return Data(base64Encoded: b64).flatMap(parseJSON)
    }
}
