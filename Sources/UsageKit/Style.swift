import SwiftUI

public extension ProviderUsage.Kind {
    var title: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .gemini: "Gemini"
        }
    }

    var symbol: String {
        switch self {
        case .claude: "asterisk"
        case .codex: "chevron.left.forwardslash.chevron.right"
        case .gemini: "sparkle"
        }
    }

    var colors: [Color] {
        switch self {
        case .claude: [Color(red: 0.91, green: 0.55, blue: 0.40), Color(red: 0.80, green: 0.40, blue: 0.27)]
        case .codex: [Color(red: 0.20, green: 0.75, blue: 0.60), Color(red: 0.05, green: 0.55, blue: 0.47)]
        case .gemini: [Color(red: 0.30, green: 0.55, blue: 0.98), Color(red: 0.62, green: 0.45, blue: 0.85)]
        }
    }

    var tint: Color { colors[1] }
}

/// Orange from 75 % used, red from 90 % used.
public func warningColor(_ used: Double) -> Color? {
    used >= 0.9 ? .red : used >= 0.75 ? .orange : nil
}

public struct ProviderMark: View {
    let kind: ProviderUsage.Kind
    var size: CGFloat = 22

    public init(kind: ProviderUsage.Kind, size: CGFloat = 22) {
        self.kind = kind
        self.size = size
    }

    public var body: some View {
        Image(systemName: kind.symbol)
            .font(.system(size: size * (kind == .codex ? 0.36 : 0.5), weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: kind.colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                in: .rect(cornerRadius: size * 0.27, style: .continuous)
            )
    }
}

/// One limit: name, "NN% used", a bar filled by the used share, and when it resets.
public struct LimitRow: View {
    /// regular: popover · compact: smaller type, countdown inline ·
    /// tile: full label, bare percent · mini: short label, bare percent
    public enum Density { case regular, compact, tile, mini }

    let window: UsageWindow
    let kind: ProviderUsage.Kind
    let now: Date
    var density: Density

    public init(window: UsageWindow, kind: ProviderUsage.Kind, now: Date, density: Density = .regular) {
        self.window = window
        self.kind = kind
        self.now = now
        self.density = density
    }

    private var compact: Bool { density != .regular }

    public var body: some View {
        let warning = warningColor(window.used)
        VStack(alignment: .leading, spacing: compact ? 3 : 5) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(density == .mini ? window.shortLabel : window.label)
                    .font(compact ? .caption.weight(.medium) : .subheadline.weight(.medium))
                    .lineLimit(1)
                // compact (large widget) keeps the countdown on this line so every limit fits without scrolling
                if density == .compact, let reset = window.resetsAt { resetLabel(reset).padding(.leading, 4) }
                Spacer(minLength: 4)
                let percent = Text(window.used, format: .percent.precision(.fractionLength(0)))
                    .fontWeight(.semibold)
                    .foregroundStyle(warning ?? .primary)
                Text(density == .mini || density == .tile
                     ? "\(percent)" : "\(percent) \(Text("used").foregroundStyle(.secondary))")
                    .font(.system(compact ? .caption : .subheadline, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            UsageBar(value: window.used, colors: warning.map { [$0.opacity(0.8), $0] } ?? kind.colors)
                .frame(height: compact ? 4 : 6)
            if density != .compact {
                if let reset = window.resetsAt {
                    resetLabel(reset)
                } else {
                    Text("Not started").font(compact ? .caption2 : .caption).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func resetLabel(_ date: Date) -> some View {
        Label {
            Text(resetText(date))
        } icon: {
            Image(systemName: "arrow.counterclockwise")
        }
        .labelStyle(ResetLabelStyle())
        .font(compact ? .caption2 : .caption)
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .lineLimit(1)
        .help("Time until this limit resets")
    }

    private func resetText(_ date: Date) -> String {
        let remaining = date.timeIntervalSince(now)
        guard remaining > 0 else { return "Reset" }
        if compact { return Self.countdown(remaining) }
        let countdown = "Resets in \(Self.countdown(remaining))"
        let time = Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        return "\(countdown) · \(time)"
    }

    static func countdown(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        let (d, h, m) = (minutes / 1440, minutes % 1440 / 60, minutes % 60)
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(max(m, 1))m"
    }
}

private struct ResetLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) { configuration.icon; configuration.title }
    }
}

public struct UsageBar: View {
    let value: Double
    let colors: [Color]

    public init(value: Double, colors: [Color]) {
        self.value = value
        self.colors = colors
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    .frame(width: value > 0 ? max(geo.size.height, geo.size.width * min(value, 1)) : 0)
            }
        }
    }
}

/// A labeled count in a pill, e.g. "4 resets" or "0 AI credits".
public struct CountChip: View {
    let count: Int
    let unit: (one: String, many: String)
    let symbol: String
    let help: String

    public static func resets(_ count: Int) -> CountChip {
        CountChip(count: count, unit: ("reset", "resets"), symbol: "ticket.fill",
                  help: "Limit resets you can redeem")
    }

    public static func credits(_ count: Int) -> CountChip {
        CountChip(count: count, unit: ("AI credit", "AI credits"), symbol: "sparkles",
                  help: "Google One AI credits, used once your plan's quota runs out")
    }

    public var body: some View {
        Label("\(count.formatted()) \(count == 1 ? unit.one : unit.many)", systemImage: symbol)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(count > 0 ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
            .background(Color.primary.opacity(0.06), in: Capsule())
            .fixedSize()
            .help(help)
    }
}

public extension ProviderUsage {
    /// Pills for whatever extras this tool reports.
    @ViewBuilder var chips: some View {
        if let resets { CountChip.resets(resets) }
        if let credits { CountChip.credits(credits) }
    }
}
