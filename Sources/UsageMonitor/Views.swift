import ServiceManagement
import SwiftUI
import UsageKit

// MARK: - Popover

struct ContentView: View {
    @Environment(UsageStore.self) private var store

    var body: some View {
        VStack(spacing: 10) {
            header
            ForEach(store.usages) { ProviderCard(usage: $0) }
        }
        .environment(\.showsRemaining, store.showsRemaining)
        .padding(14)
        .frame(width: 340)
        .task { await store.refreshIfStale() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Usage")
                .font(.system(.title3, design: .rounded).weight(.semibold))
            @Bindable var store = store
            Picker("Show", selection: $store.showsRemaining) {
                Text("Used").tag(false)
                Text("Left").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            .help("Show how much of each limit is used, or how much is left")
            Spacer()
            if let updated = store.updatedAt {
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    Text(updated, format: .relative(presentation: .named))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .symbolEffect(.rotate, isActive: store.isLoading)
            }
            .buttonStyle(.borderless)
            .disabled(store.isLoading)
            .help("Refresh")
            SettingsMenu()
        }
        .padding(.horizontal, 2)
    }
}

private struct SettingsMenu: View {
    @Environment(UsageStore.self) private var store
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        @Bindable var store = store
        Menu {
            Picker("Menu Bar Shows", selection: $store.menuBarTool) {
                ForEach(ProviderUsage.Kind.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                Divider()
                Text("Closest to a Limit").tag(ProviderUsage.Kind?.none)
            }
            Toggle("Launch at Login", isOn: $launchAtLogin)
            Divider()
            Button("Quit Usage Monitor") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onChange(of: launchAtLogin) { _, enabled in
            do {
                if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }
}

// MARK: - Card

struct ProviderCard: View {
    let usage: ProviderUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProviderHeader(usage: usage)

            if usage.windows.isEmpty && usage.error == nil {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity)
            }
            TimelineView(.periodic(from: .now, by: 30)) { context in
                VStack(spacing: 12) {
                    ForEach(usage.windows) { LimitRow(window: $0, kind: usage.kind, now: context.date) }
                }
            }
            .animation(.smooth, value: usage.windows)

            if let error = usage.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.multicolor)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.045), in: .rect(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07))
        )
    }
}

// MARK: - Menu bar label

struct MenuBarLabel: View {
    let store: UsageStore

    var body: some View {
        // The chosen tool's tightest limit (or the tightest across all tools), with that tool's symbol.
        let candidates = store.usages.filter { store.menuBarTool == nil || $0.kind == store.menuBarTool }
        let tightest = candidates
            .compactMap { usage in usage.windows.map(\.used).max().map { (usage.kind, $0) } }
            .max { $0.1 < $1.1 }
        let items: [(symbol: String, text: String)] = if let (kind, used) = tightest {
            [(kind.symbol, (store.showsRemaining ? 1 - used : used).formatted(.percent.precision(.fractionLength(0))))]
        } else if let kind = store.menuBarTool {
            [(kind.symbol, "–")]
        } else {
            [("gauge.with.dots.needle.33percent", "")]
        }
        Image(nsImage: Self.image(items))
            .help(summary)
    }

    /// Every tool's tightest limit, for the tooltip.
    private var summary: String {
        store.usages.map { usage in
            let value = usage.windows.map(\.used).max().map { store.showsRemaining ? 1 - $0 : $0 }
            let text = value?.formatted(.percent.precision(.fractionLength(0))) ?? "–"
            return "\(usage.kind.title): \(text) \(metricName(remaining: store.showsRemaining))"
        }
        .joined(separator: "\n")
    }

    /// The status bar draws an Image and a Text side by side without aligning them (and drops
    /// symbols embedded in Text), so render everything into one template image, centered together.
    @MainActor static func image(_ items: [(symbol: String, text: String)]) -> NSImage {
        let content = HStack(spacing: 9) {
            ForEach(items.indices, id: \.self) { i in
                HStack(spacing: 3) {
                    Image(systemName: items[i].symbol)
                        .font(.system(size: items[i].symbol.hasPrefix("chevron") ? 8.5 : 11, weight: .bold))
                    if !items[i].text.isEmpty { Text(items[i].text).monospacedDigit() }
                }
            }
        }
        .font(.system(size: 12.5, weight: .medium))
        .foregroundStyle(.black)
        .padding(.vertical, 1)

        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage(systemSymbolName: "gauge.with.dots.needle.33percent",
                                                accessibilityDescription: "Usage")!
        image.isTemplate = true // tinted by the menu bar for light and dark appearances
        return image
    }
}
