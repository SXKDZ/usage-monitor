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
        .padding(14)
        .frame(width: 340)
        .task { await store.refreshIfStale() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Usage")
                .font(.system(.title3, design: .rounded).weight(.semibold))
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
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Menu {
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
            HStack(spacing: 9) {
                ProviderMark(kind: usage.kind, size: usage.account == nil ? 22 : 30)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(usage.kind.title)
                            .font(.system(.headline, design: .rounded))
                        if let plan = usage.plan {
                            Text(plan)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .foregroundStyle(usage.kind.tint)
                                .background(usage.kind.tint.opacity(0.14), in: Capsule())
                                .lineLimit(1)
                        }
                    }
                    HStack {
                        if let account = usage.account {
                            Text(account)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 4)
                        if let cards = usage.resetCards { ResetCardsChip(count: cards) }
                    }
                }
            }

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
        HStack(spacing: 4) {
            Image(systemName: "gauge.with.dots.needle.33percent")
            if let peak = store.peak {
                Text(peak, format: .percent.precision(.fractionLength(0)))
            }
        }
        .help("Highest limit usage across all tools")
    }
}
