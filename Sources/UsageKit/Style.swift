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

// MARK: - Used / left

private struct ShowsRemainingKey: EnvironmentKey { static let defaultValue = false }

public extension EnvironmentValues {
    /// Show what's left of each limit instead of what's used.
    var showsRemaining: Bool {
        get { self[ShowsRemainingKey.self] }
        set { self[ShowsRemainingKey.self] = newValue }
    }
}

public extension UsageWindow {
    /// The fraction to display: what's used, or what's left.
    func shown(remaining: Bool) -> Double { remaining ? max(0, 1 - used) : used }
}

/// "used" or "left", for labels like "72% used".
public func metricName(remaining: Bool) -> String { remaining ? "left" : "used" }

/// Orange from 75 % used, red from 90 % used (whichever way the percentage is shown).
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

    @Environment(\.showsRemaining) private var remaining

    private var compact: Bool { density != .regular }

    public var body: some View {
        let warning = warningColor(window.used)
        VStack(alignment: .leading, spacing: compact ? 3 : 5) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(density == .mini ? window.shortLabel : window.label)
                    .font(compact ? .caption.weight(.medium) : .subheadline.weight(.medium))
                    .lineLimit(1)
                    // Sized first, so it keeps its natural width whenever it fits.
                    .layoutPriority(1)
                // compact (large widget) keeps the countdown on this line so every limit fits without scrolling
                if density == .compact, let reset = window.resetsAt { resetLabel(reset).padding(.leading, 4) }
                Spacer(minLength: 4)
                let percent = Text(window.shown(remaining: remaining), format: .percent.precision(.fractionLength(0)))
                    .fontWeight(.semibold)
                    .foregroundStyle(warning ?? .primary)
                Text(density == .mini || density == .tile
                     ? "\(percent)" : "\(percent) \(Text(metricName(remaining: remaining)).foregroundStyle(.secondary))")
                    .font(.system(compact ? .caption : .subheadline, design: .rounded))
                    .monospacedDigit()
                    .fixedSize()
            }
            UsageBar(value: window.shown(remaining: remaining), colors: warning.map { [$0.opacity(0.8), $0] } ?? kind.colors)
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

/// A balance as a pill, orange when there's something to use.
public struct BalanceChip: View {
    let balance: Balance
    var compact = false

    public init(_ balance: Balance, compact: Bool = false) {
        self.balance = balance
        self.compact = compact
    }

    public var body: some View {
        Label(balance.text, systemImage: balance.symbol)
            .labelStyle(ChipLabelStyle())
            .font(compact ? .system(size: 9.5, weight: .semibold) : .caption2.weight(.semibold))
            .padding(.horizontal, compact ? 5 : 7)
            .padding(.vertical, compact ? 2 : 3)
            .foregroundStyle(balance.available ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
            .background(Color.primary.opacity(0.06), in: Capsule())
            .fixedSize()
            .help(balance.help)
    }
}

private struct ChipLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) { configuration.icon; configuration.title }
    }
}

/// Tool name and plan, then the signed-in account with its balances. Shared by the popover and widgets.
public struct ProviderHeader: View {
    let usage: ProviderUsage
    var compact = false

    public init(usage: ProviderUsage, compact: Bool = false) {
        self.usage = usage
        self.compact = compact
    }

    public var body: some View {
        HStack(spacing: compact ? 7 : 9) {
            ProviderMark(kind: usage.kind, size: compact ? 26 : 30)
            VStack(alignment: .leading, spacing: compact ? 1 : 2) {
                HStack(spacing: 6) {
                    Text(usage.kind.title)
                        .font(compact ? .caption.weight(.semibold) : .system(.headline, design: .rounded))
                        .lineLimit(1)
                    if let plan = usage.plan { PlanBadge(plan: plan, kind: usage.kind, compact: compact) }
                }
                HStack(spacing: 4) {
                    if let account = usage.account {
                        Text(account)
                            .font(compact ? .caption2 : .caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 4)
                    ForEach(usage.balances, id: \.self) { BalanceChip($0, compact: compact) }
                }
            }
        }
    }
}

/// The subscription plan ("Max 5×") in the tool's color.
public struct PlanBadge: View {
    let plan: String
    let kind: ProviderUsage.Kind
    var compact = false

    public init(plan: String, kind: ProviderUsage.Kind, compact: Bool = false) {
        self.plan = plan
        self.kind = kind
        self.compact = compact
    }

    public var body: some View {
        Text(plan)
            .font(compact ? .system(size: 9.5, weight: .semibold) : .caption2.weight(.semibold))
            .padding(.horizontal, compact ? 5 : 6)
            .padding(.vertical, compact ? 1 : 2)
            .foregroundStyle(kind.tint)
            .background(kind.tint.opacity(0.14), in: Capsule())
            .lineLimit(1)
            .fixedSize()
    }
}
