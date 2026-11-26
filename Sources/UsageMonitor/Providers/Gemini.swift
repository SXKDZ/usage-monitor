import Foundation
import UsageKit

/// Gemini via the Antigravity CLI (`agy`) Google login stored in the "gemini" keychain item.
/// The access token is refreshed in memory only; the keychain is never written.
enum GeminiProvider {
    static func load() async throws -> ProviderUsage {
        let (token, email) = try await GeminiAuth.shared.accessToken()
        async let summary = call("retrieveUserQuotaSummary", body: "{}", token: token)
        // The plan and its AI credit balance; optional, so a failure here doesn't hide the limits.
        async let assist = try? call("loadCodeAssist", body: #"{"metadata":{"ideType":"ANTIGRAVITY"}}"#, token: token)
        let json = try await summary

        // Each model group shares a 5-hour and a weekly bucket.
        var windows: [UsageWindow] = []
        for case let group as JSON in json["groups"] as? [Any] ?? [] {
            let name = (group["displayName"] as? String ?? "Models")
                .replacingOccurrences(of: " models", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: " and ", with: " & ")
            let buckets = (group["buckets"] as? [Any] ?? []).compactMap { $0 as? JSON }
                .sorted { ($0["window"] as? String == "5h" ? 0 : 1) < ($1["window"] as? String == "5h" ? 0 : 1) }
            for b in buckets {
                let period = switch b["window"] as? String {
                case "5h": "5-hour"
                case "weekly": "Weekly"
                default: b["displayName"] as? String ?? "Limit"
                }
                // An omitted remainingFraction means 0 remaining (proto3 default).
                let used = 1 - (num(b["remainingFraction"]) ?? 0)
                windows.append(UsageWindow(label: "\(period) · \(name)", used: used, resetsAt: .iso(b["resetTime"])))
            }
        }
        guard !windows.isEmpty else { throw UsageError("No quota information returned") }

        let tier = await assist?["paidTier"] as? JSON
        // An omitted creditAmount means a zero balance (proto3 default).
        let credits = (tier?["availableCredits"] as? [JSON]).map {
            $0.reduce(0) { $0 + Int(num($1["creditAmount"]) ?? 0) }
        }
        return ProviderUsage(kind: .gemini, plan: tier?["name"] as? String ?? "Antigravity",
                             account: email, windows: windows, credits: credits)
    }

    /// Same host and client identity as `agy`: the server only returns the Gemini group
    /// (with live numbers) to a versioned Antigravity CLI client on the daily host.
    private static func call(_ method: String, body: String, token: String) async throws -> JSON {
        var req = URLRequest(url: URL(string: "https://daily-cloudcode-pa.googleapis.com/v1internal:\(method)")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("antigravity/cli/1.5.17 (aidev_client; os_type=darwin; arch=arm64; auth_method=consumer)",
                     forHTTPHeaderField: "User-Agent")
        req.httpBody = Data(body.utf8)
        return try await HTTP.json(req)
    }
}

actor GeminiAuth {
    static let shared = GeminiAuth()

    // Antigravity's installed-app OAuth client. Its secret ships inside the `agy` binary,
    // so it's read from there at runtime instead of being redistributed with this source.
    private let clientID = "1071006060591-tmhssin2h21lcre235vtolojh4g403ep.apps.googleusercontent.com"
    private var clientSecret: String?

    private var token: String?
    private var email: String?
    private var expiry = Date.distantPast

    func accessToken() async throws -> (token: String, email: String?) {
        if let token, expiry > Date().addingTimeInterval(60) { return (token, email) }

        guard var raw = Keychain.password(service: "gemini")
        else { throw UsageError("Not signed in — run `agy` to log in") }
        if raw.hasPrefix("go-keyring-base64:"),
           let decoded = Data(base64Encoded: String(raw.dropFirst("go-keyring-base64:".count))) {
            raw = String(decoding: decoded, as: UTF8.self)
        }
        let creds = parseJSON(Data(raw.utf8))
        guard let stored = creds?["token"] as? JSON
        else { throw UsageError("Unreadable Antigravity credentials") }
        email = creds?["id_token_email"] as? String

        if let access = stored["access_token"] as? String, let exp = Date.iso(stored["expiry"]),
           exp > Date().addingTimeInterval(60) {
            (token, expiry) = (access, exp)
            return (access, email)
        }
        guard let refresh = stored["refresh_token"] as? String
        else { throw UsageError("Sign-in expired — run `agy` to log in") }

        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-._~"))
        // The binary holds several client secrets; keep the first one that works for this client.
        for secret in clientSecret.map({ [$0] }) ?? Self.agySecrets() {
            req.httpBody = Data([
                "client_id": clientID, "client_secret": secret,
                "refresh_token": refresh, "grant_type": "refresh_token",
            ].map { "\($0)=\($1.addingPercentEncoding(withAllowedCharacters: allowed)!)" }
             .joined(separator: "&").utf8)
            guard let json = try? await HTTP.json(req), let access = json["access_token"] as? String else { continue }
            clientSecret = secret
            (token, expiry) = (access, Date().addingTimeInterval(num(json["expires_in"]) ?? 3_000))
            return (access, email)
        }
        throw UsageError("Couldn't refresh Google sign-in — is the Antigravity CLI (agy) installed?")
    }

    /// Google OAuth client secrets ("GOCSPX-" + 28 chars) found in the installed `agy` binary.
    private static func agySecrets() -> [String] {
        let agy = homeFile(".local/bin/agy").resolvingSymlinksInPath()
        guard let data = try? Data(contentsOf: agy, options: .alwaysMapped) else { return [] }
        let prefix = Data("GOCSPX-".utf8)
        var secrets: [String] = []
        var searchRange = data.startIndex..<data.endIndex
        while let hit = data.range(of: prefix, in: searchRange) {
            let end = data.index(hit.lowerBound, offsetBy: 35, limitedBy: data.endIndex) ?? data.endIndex
            if let s = String(data: data[hit.lowerBound..<end], encoding: .ascii),
               s.range(of: #"^GOCSPX-[A-Za-z0-9_\-]{28}$"#, options: .regularExpression) != nil,
               !secrets.contains(s) {
                secrets.append(s)
            }
            searchRange = hit.upperBound..<data.endIndex
        }
        return secrets
    }
}
