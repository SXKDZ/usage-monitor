import SwiftUI
import UsageKit

@main
struct UsageMonitorApp: App {
    @State private var store = UsageStore()

    init() {
        // `UsageMonitor --dump` prints the fetched usage and exits (handy for debugging).
        guard CommandLine.arguments.contains("--dump") else { return }
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            for usage in await UsageStore.fetchAll() {
                print("\(usage.kind.title) [\(usage.plan ?? "-")] \(usage.account ?? "")", usage.error.map { "error: \($0)" } ?? "")
                for w in usage.windows {
                    print("  \(w.label): \(Int((w.used * 100).rounded()))%  resets \(w.resetsAt?.description ?? "-")")
                }
                if !usage.balances.isEmpty { print("  balances:", usage.balances.map(\.text).joined(separator: ", ")) }
            }
            done.signal()
        }
        done.wait()
        exit(0)
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView().environment(store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}
