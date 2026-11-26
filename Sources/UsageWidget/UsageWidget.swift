import SwiftUI
import UsageKit
import WidgetKit

@main
struct UsageWidgets: WidgetBundle {
    var body: some Widget {
        UsageWidget()
        ClaudeWidget()
        CodexWidget()
        GeminiWidget()
    }
}

struct UsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "UsageWidget", provider: Provider()) { entry in
            UsageWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("AI Usage")
        .description("Claude Code, Codex and Gemini limits and when they reset.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Timeline

struct Entry: TimelineEntry {
    let date: Date
    let snapshot: Snapshot?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: .now, snapshot: .sample) }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: .now, snapshot: Snapshot.load() ?? .sample))
    }

    /// The menu bar app refreshes the data and reloads us; extra entries just keep countdowns current.
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let snapshot = Snapshot.load()
        let entries = (0..<12).map { Entry(date: .now.addingTimeInterval(Double($0) * 300), snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

extension Snapshot {
    static let sample = Snapshot(usages: [
        ProviderUsage(kind: .claude, plan: "Max", windows: [
            UsageWindow(label: "5-hour session", used: 0.2, resetsAt: .now.addingTimeInterval(10_800)),
            UsageWindow(label: "Weekly · all models", used: 0.35, resetsAt: .now.addingTimeInterval(400_000)),
        ]),
        ProviderUsage(kind: .codex, plan: "Plus", windows: [
            UsageWindow(label: "Weekly", used: 0.18, resetsAt: .now.addingTimeInterval(500_000)),
        ]),
        ProviderUsage(kind: .gemini, plan: "Antigravity", windows: [
            UsageWindow(label: "5-hour · Claude & GPT", used: 0.1, resetsAt: .now.addingTimeInterval(9_000)),
            UsageWindow(label: "Weekly · Claude & GPT", used: 0.55, resetsAt: .now.addingTimeInterval(300_000)),
        ]),
    ], updatedAt: .now)
}

// MARK: - Views

struct UsageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Entry

    var body: some View {
        if let snapshot = entry.snapshot {
            switch family {
            case .systemSmall: SmallView(usages: snapshot.usages)
            case .systemMedium: MediumView(usages: snapshot.usages, now: entry.date)
            default: LargeView(snapshot: snapshot, now: entry.date)
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "gauge.with.dots.needle.33percent").font(.title2)
                Text("Open Usage Monitor to start").font(.caption).multilineTextAlignment(.center)
            }
            .foregroundStyle(.secondary)
        }
    }
}

/// Small: each tool's most-used limit.
private struct SmallView: View {
    let usages: [ProviderUsage]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(usages) { usage in
                let top = usage.windows.max { $0.used < $1.used }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        ProviderMark(kind: usage.kind, size: 16)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(usage.kind.title).font(.caption.weight(.semibold))
                            Text(top?.shortLabel ?? usage.error ?? "—")
                                .font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                        .lineLimit(1)
                        Spacer(minLength: 2)
                        if let top {
                            Text(top.used, format: .percent.precision(.fractionLength(0)))
                                .font(.system(.callout, design: .rounded).weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(warningColor(top.used) ?? .primary)
                        }
                    }
                    let warning = top.flatMap { warningColor($0.used) }
                    UsageBar(value: top?.used ?? 0, colors: warning.map { [$0.opacity(0.8), $0] } ?? usage.kind.colors)
                        .frame(height: 4)
                }
                .frame(maxHeight: .infinity)
            }
            Text("% of limit used").font(.system(size: 9)).foregroundStyle(.tertiary)
        }
    }
}

/// Medium: one column per tool with its first two limits.
private struct MediumView: View {
    let usages: [ProviderUsage]
    let now: Date

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(usages) { usage in
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 6) {
                        ProviderMark(kind: usage.kind, size: 18)
                        Text(usage.kind.title).font(.caption.weight(.semibold)).lineLimit(1)
                    }
                    ForEach(usage.activeWindows.prefix(2)) {
                        LimitRow(window: $0, kind: usage.kind, now: now, density: .mini)
                    }
                    if usage.windows.isEmpty, let error = usage.error {
                        Text(error).font(.caption2).foregroundStyle(.secondary).lineLimit(3)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .overlay(alignment: .bottomLeading) {
            Text("% of limit used").font(.system(size: 9)).foregroundStyle(.tertiary)
        }
    }
}

/// Large: every limit, grouped by tool.
private struct LargeView: View {
    let snapshot: Snapshot
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("AI Usage").font(.system(.headline, design: .rounded))
                Spacer()
                Text("Updated \(snapshot.updatedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            ForEach(snapshot.usages) { usage in
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        ProviderMark(kind: usage.kind, size: 18)
                        Text(usage.kind.title).font(.caption.weight(.semibold))
                        if let account = usage.account {
                            Text(account).font(.caption2).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        Spacer(minLength: 4)
                        usage.chips
                    }
                    ForEach(usage.activeWindows.prefix(3)) {
                        LimitRow(window: $0, kind: usage.kind, now: now, density: .compact)
                    }
                    if usage.windows.isEmpty, let error = usage.error {
                        Text(error).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}
