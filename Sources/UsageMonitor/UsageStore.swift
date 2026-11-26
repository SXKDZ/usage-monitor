import Foundation
import Observation
import UsageKit
import WidgetKit

@MainActor @Observable
final class UsageStore {
    private(set) var usages: [ProviderUsage]
    private(set) var isLoading = false
    private(set) var updatedAt: Date?

    /// The Used / Left switch; remembered across launches and passed on to the widgets.
    var showsRemaining = UserDefaults.standard.bool(forKey: "showsRemaining") {
        didSet {
            UserDefaults.standard.set(showsRemaining, forKey: "showsRemaining")
            publish()
        }
    }

    init() {
        // Start from the last snapshot so the popover isn't empty while the first fetch runs.
        let last = Snapshot.load()
        usages = last?.usages ?? ProviderUsage.Kind.allCases.map { ProviderUsage(kind: $0) }
        Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(300))
            }
        }
    }

    func refreshIfStale() async {
        if updatedAt.map({ Date().timeIntervalSince($0) > 60 }) ?? true { await refresh() }
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let fresh = await Self.fetchAll()
        // On failure, keep the last good numbers and surface the error alongside them.
        usages = zip(fresh, usages).map { new, old in
            guard new.error != nil, !old.windows.isEmpty else { return new }
            var kept = old
            kept.error = new.error
            return kept
        }
        updatedAt = .now
        publish()
    }

    /// Hands the latest numbers and display setting to the widgets.
    private func publish() {
        let snapshot = Snapshot(usages: usages, updatedAt: updatedAt ?? .now, showsRemaining: showsRemaining)
        if snapshot.save() { WidgetCenter.shared.reloadAllTimelines() }
    }

    nonisolated static func fetchAll() async -> [ProviderUsage] {
        async let claude = run(.claude, ClaudeProvider.load)
        async let codex = run(.codex, CodexProvider.load)
        async let gemini = run(.gemini, GeminiProvider.load)
        return await [claude, codex, gemini]
    }

    private nonisolated static func run(
        _ kind: ProviderUsage.Kind, _ load: () async throws -> ProviderUsage
    ) async -> ProviderUsage {
        do { return try await load() } catch {
            return ProviderUsage(kind: kind, error: error.localizedDescription)
        }
    }
}
