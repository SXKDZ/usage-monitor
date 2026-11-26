import Foundation

public struct UsageWindow: Identifiable, Codable, Hashable, Sendable {
    public var id: String { label }
    public let label: String
    public let used: Double // fraction used, 0...1
    public let resetsAt: Date?

    public init(label: String, used: Double, resetsAt: Date?) {
        self.label = label
        self.used = used
        self.resetsAt = resetsAt
    }

    /// "Weekly · all models" → "Weekly"
    public var shortLabel: String {
        label.components(separatedBy: " · ")[0].replacingOccurrences(of: " session", with: "")
    }
}

public struct ProviderUsage: Identifiable, Codable, Hashable, Sendable {
    public enum Kind: String, CaseIterable, Codable, Sendable { case claude, codex, gemini }

    public let kind: Kind
    public var id: Kind { kind }
    public var plan: String?
    public var account: String?
    public var windows: [UsageWindow]
    public var balances: [Balance] // resets, credits, extra usage: shown as pills
    public var error: String?

    public init(kind: Kind, plan: String? = nil, account: String? = nil, windows: [UsageWindow] = [],
                balances: [Balance] = [], error: String? = nil) {
        self.kind = kind
        self.plan = plan
        self.account = account
        self.windows = windows
        self.balances = balances
        self.error = error
    }
}

/// Something a tool lets you spend beyond its limits, shown as a pill: "4 resets", "0 AI credits".
public struct Balance: Codable, Hashable, Sendable {
    public let symbol: String  // SF Symbol
    public let text: String
    public let available: Bool // something to use (or switched on): drawn in orange
    public let help: String

    public init(symbol: String, text: String, available: Bool, help: String) {
        self.symbol = symbol
        self.text = text
        self.available = available
        self.help = help
    }

    public static func resets(_ count: Int) -> Balance {
        Balance(symbol: "ticket.fill", text: "\(count) \(count == 1 ? "reset" : "resets")",
                available: count > 0, help: "Limit resets you can redeem")
    }

    public static func credits(_ amount: Double, unit: String, help: String) -> Balance {
        Balance(symbol: "creditcard.fill", text: "\(amount.formatted(.number.precision(.fractionLength(0...2)))) \(unit)",
                available: amount > 0, help: help)
    }
}

public extension ProviderUsage {
    /// Limits that have started (something used or a reset scheduled) — for space-constrained views.
    var activeWindows: [UsageWindow] {
        let active = windows.filter { $0.used > 0 || $0.resetsAt != nil }
        return active.isEmpty ? windows : active
    }
}

/// The app writes the latest usage here; the sandboxed widget reads it (shared app-group container).
public struct Snapshot: Codable, Sendable {
    public var usages: [ProviderUsage]
    public var updatedAt: Date
    public var showsRemaining: Bool? // the app's Used / Left switch, so widgets match it

    public init(usages: [ProviderUsage], updatedAt: Date, showsRemaining: Bool? = nil) {
        self.usages = usages
        self.updatedAt = updatedAt
        self.showsRemaining = showsRemaining
    }

    private static var url: URL? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "UsageAppGroup") as? String,
              let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
        else { return nil }
        return dir.appendingPathComponent("snapshot.json")
    }

    public static func load() -> Snapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    /// Returns true when what the widgets show changed (so they need a reload).
    @discardableResult
    public func save() -> Bool {
        guard let url = Self.url, let data = try? JSONEncoder().encode(self) else { return false }
        let old = Self.load()
        let changed = old?.usages != usages || old?.showsRemaining != showsRemaining
        try? data.write(to: url, options: .atomic)
        return changed
    }
}
