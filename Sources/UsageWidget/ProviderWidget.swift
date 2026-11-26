import SwiftUI
import UsageKit
import WidgetKit

// One widget per tool, so each can be placed as its own block on the desktop.

struct ClaudeWidget: Widget {
    var body: some WidgetConfiguration { providerConfiguration(.claude) }
}

struct CodexWidget: Widget {
    var body: some WidgetConfiguration { providerConfiguration(.codex) }
}

struct GeminiWidget: Widget {
    var body: some WidgetConfiguration { providerConfiguration(.gemini) }
}

private func providerConfiguration(_ kind: ProviderUsage.Kind) -> some WidgetConfiguration {
    StaticConfiguration(kind: "\(kind.rawValue)-usage", provider: Provider()) { entry in
        ProviderWidgetView(kind: kind, entry: entry)
            .containerBackground(.background, for: .widget)
    }
    // Plain Strings: interpolated literals become LocalizedStringKeys with arguments,
    // which WidgetKit can't archive (it asserts and the whole extension disappears from the gallery).
    .configurationDisplayName(kind.title + " Usage")
    .description(kind.title + " limits and when they reset.")
    .supportedFamilies([.systemSmall, .systemMedium])
}

struct ProviderWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let kind: ProviderUsage.Kind
    let entry: Entry

    private var usage: ProviderUsage? { entry.snapshot?.usages.first { $0.kind == kind } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let usage, !usage.windows.isEmpty {
                if family == .systemSmall {
                    ForEach(smallWindows(usage)) {
                        LimitRow(window: $0, kind: kind, now: entry.date, density: .mini)
                    }
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 18, alignment: .top), count: 2),
                              alignment: .leading, spacing: 10) {
                        ForEach(usage.windows.prefix(usage.resetCards == nil ? 4 : 3)) {
                            LimitRow(window: $0, kind: kind, now: entry.date, density: .tile)
                        }
                        if let cards = usage.resetCards { ResetCardsTile(count: cards) }
                    }
                }
            } else {
                Text(usage?.error ?? "Open Usage Monitor to start")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(3)
            }
            Spacer(minLength: 0)
        }
    }

    /// Small has room for two rows. Gemini gets one per model group ("Gemini", "Claude & GPT"),
    /// each showing whichever of its limits is closest to running out.
    private func smallWindows(_ usage: ProviderUsage) -> [UsageWindow] {
        guard kind == .gemini else { return Array(usage.windows.prefix(2)) }
        var groups: [String: UsageWindow] = [:]
        var order: [String] = []
        for w in usage.windows {
            let group = w.label.components(separatedBy: " · ").last ?? w.label
            if groups[group] == nil { order.append(group) }
            if w.used >= groups[group]?.used ?? -1 { groups[group] = UsageWindow(label: group, used: w.used, resetsAt: w.resetsAt) }
        }
        return order.prefix(2).compactMap { groups[$0] }
    }

    private var header: some View {
        HStack(spacing: 6) {
            ProviderMark(kind: kind, size: 18)
            Text(family == .systemSmall && kind == .claude ? "Claude" : kind.title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            if family != .systemSmall, let account = usage?.account {
                Text(account)
                    .font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 4)
            Text("% used").font(.system(size: 9)).foregroundStyle(.tertiary).fixedSize()
        }
    }
}

/// Reset cards as their own grid tile, laid out like a LimitRow so it can't be misread as a percentage.
private struct ResetCardsTile: View {
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("Reset cards").font(.caption.weight(.medium)).lineLimit(1)
                Spacer(minLength: 4)
                Text("\(count)")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(count > 0 ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary))
            }
            Color.clear.frame(height: 4)
            Label(count == 0 ? "None available" : "\(count) available", systemImage: "ticket.fill")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}
