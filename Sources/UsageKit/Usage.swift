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
    public var resetCards: Int?
    public var error: String?

    public init(kind: Kind, plan: String? = nil, account: String? = nil, windows: [UsageWindow] = [],
                resetCards: Int? = nil, error: String? = nil) {
        self.kind = kind
        self.plan = plan
        self.account = account
        self.windows = windows
        self.resetCards = resetCards
        self.error = error
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

    public init(usages: [ProviderUsage], updatedAt: Date) {
        self.usages = usages
        self.updatedAt = updatedAt
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

    /// Returns true when the usage numbers changed (so the widget needs a reload).
    @discardableResult
    public func save() -> Bool {
        guard let url = Self.url, let data = try? JSONEncoder().encode(self) else { return false }
        let changed = Self.load()?.usages != usages
        try? data.write(to: url, options: .atomic)
        return changed
    }
}
