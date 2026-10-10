import SwiftUI

// MARK: Status

extension ThreadStatus {
    var tint: Color {
        switch self {
        case .running: HP.running
        case .queued: HP.ink3
        case .waiting: HP.waiting
        case .blocked: HP.waiting
        case .ready: HP.ready
        case .failed: HP.failed
        case .archived, .unknown: HP.archived
        }
    }

    var label: String {
        switch self {
        case .running: "Running"
        case .queued: "Queued"
        case .waiting: "Waiting"
        case .blocked: "Needs approval"
        case .ready: "Ready"
        case .failed: "Failed"
        case .archived: "Archived"
        case .unknown: "Unknown"
        }
    }
}

/// The status mark used everywhere a thread appears; see `HopliteGlyph`.
struct StatusGlyph: View {
    let status: ThreadStatus
    var size: CGFloat = 18

    var body: some View {
        HopliteGlyph(status: status.rawValue, size: size)
            .accessibilityLabel(status.label)
    }
}

struct StatusPill: View {
    let status: ThreadStatus
    var detail: String?

    var body: some View {
        HStack(spacing: 6) {
            StatusGlyph(status: status, size: 12)
            Text(detail.map { "\(status.label) · \($0)" } ?? status.label)
                .font(.hpCaption)
                .foregroundStyle(status == .queued ? HP.ink2 : status.tint)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(status.tint.opacity(0.12), in: .capsule)
    }
}

// MARK: Brand

struct BrandMark: View {
    var size: CGFloat = 22
    var color: Color = HP.ink

    var body: some View {
        Image("BrandMark")
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }
}

struct AppIconMark: View {
    var size: CGFloat = 36

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(LinearGradient(colors: [HP.actionBright, HP.action, HP.actionDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(BrandMark(size: size * 0.62, color: Color(hex: 0x111111)))
            .frame(width: size, height: size)
            .shadow(color: HP.action.opacity(0.35), radius: size * 0.25, y: size * 0.08)
    }
}

/// The dithered statue art from hoplite.sh, inverted for dark mode and faded into the canvas.
struct HalftoneArt: View {
    var name = "StatueArt"
    var opacity: Double = 0.5
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Image(name)
            .resizable()
            .scaledToFill()
            .colorInvert(scheme == .dark)
            .opacity(opacity)
            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.55), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
            .accessibilityHidden(true)
    }
}

extension View {
    @ViewBuilder func colorInvert(_ enabled: Bool) -> some View {
        if enabled { colorInvert() } else { self }
    }
}

// MARK: Chips

struct MetaChip: View {
    var icon: String?
    var asset: String?
    let text: String
    var tint: Color = HP.ink2

    var body: some View {
        HStack(spacing: 4) {
            if let asset {
                Image(asset).resizable().renderingMode(.template).scaledToFit().frame(width: 11, height: 11)
            } else if let icon {
                Image(systemName: icon).font(.system(size: 10, weight: .semibold))
            }
            Text(text).font(.hpCaption).lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(HP.control.opacity(0.7), in: .capsule)
    }
}

struct PRBadge: View {
    let pr: PullRequest

    private var state: (icon: String, tint: Color, label: String) {
        let state = pr.githubSummary?.state ?? pr.state
        if state == "merged" { return ("arrow.triangle.merge", HP.merged, "Merged") }
        if state == "closed" { return ("xmark.circle", HP.ink3, "Closed") }
        if pr.draft == true || pr.githubSummary?.draft == true { return ("circle.dashed", HP.ink2, "Draft") }
        return ("arrow.triangle.pull", HP.ready, "Open")
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: state.icon).font(.system(size: 10, weight: .bold)).foregroundStyle(state.tint)
            Text("#\(pr.number)").font(.mono(11.5, weight: .medium)).foregroundStyle(HP.ink2)
            if let checks = pr.githubSummary?.checks, checks.total > 0, (pr.githubSummary?.state ?? pr.state) == "open" {
                ChecksRing(checks: checks, size: 11)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(HP.control.opacity(0.7), in: .capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pull request \(pr.number), \(state.label)")
    }
}

/// A tiny segmented ring: green for passing checks, red for failing, blue for running.
struct ChecksRing: View {
    let checks: ChecksSummary
    var size: CGFloat = 12

    var body: some View {
        let total = max(Double(checks.total), 1)
        let ok = Double(checks.succeeded) / total
        let bad = Double(checks.failing) / total
        let run = Double(checks.running) / total
        ZStack {
            Circle().stroke(HP.ink3.opacity(0.3), lineWidth: 2)
            Circle().trim(from: 0, to: ok).stroke(HP.ready, lineWidth: 2)
            Circle().trim(from: ok, to: ok + bad).stroke(HP.failed, lineWidth: 2)
            Circle().trim(from: ok + bad, to: ok + bad + run).stroke(HP.waiting, lineWidth: 2)
        }
        .rotationEffect(.degrees(-90))
        .frame(width: size, height: size)
    }
}

struct Avatar: View {
    let name: String
    var size: CGFloat = 22

    private var tint: Color {
        let palette: [Color] = [Color(hex: 0xF59E0B), Color(hex: 0x3B82F6), Color(hex: 0xA855F7), Color(hex: 0x10B981), Color(hex: 0xEC4899), Color(hex: 0x06B6D4)]
        return palette[abs(name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }) % palette.count]
    }

    var body: some View {
        Circle()
            .fill(tint.gradient)
            .overlay(Text(name.split(separator: " ").compactMap(\.first).prefix(2).map(String.init).joined()).font(.system(size: size * 0.4, weight: .bold)).foregroundStyle(.white))
            .frame(width: size, height: size)
            .accessibilityLabel(name)
    }
}

// MARK: Motion

/// A moving highlight across text while the agent works, the same cue Claude and Cursor use
/// for "thinking", tinted in Hoplite's neutral inks.
struct Shimmer: ViewModifier {
    var active = true
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                if active {
                    GeometryReader { proxy in
                        LinearGradient(colors: [.clear, .white.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: proxy.size.width * 0.5)
                            .offset(x: phase * proxy.size.width * 1.5)
                            .blendMode(.plusLighter)
                    }
                    .mask(content)
                    .allowsHitTesting(false)
                }
            }
            .onAppear {
                guard active else { return }
                withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}

extension View {
    func shimmer(_ active: Bool = true) -> some View { modifier(Shimmer(active: active)) }
}

// MARK: Formatting

enum Format {
    static func relative(_ date: Date?) -> String {
        guard let date else { return "" }
        let seconds = Date().timeIntervalSince(date)
        if seconds < 45 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h" }
        if seconds < 86_400 * 7 { return "\(Int(seconds / 86_400))d" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    static func until(_ date: Date) -> String {
        let seconds = date.timeIntervalSinceNow
        if seconds <= 60 { return "soon" }
        if seconds < 3600 { return "in \(Int(seconds / 60))m" }
        if seconds < 86_400 { return "in \(Int(seconds / 3600))h" }
        return "in \(Int(seconds / 86_400))d"
    }

    static func duration(ms: Double) -> String {
        let seconds = Int(ms / 1000)
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m \(seconds % 60)s" }
        return "\(seconds / 3600)h \((seconds % 3600) / 60)m"
    }

    static func elapsed(since date: Date?) -> String {
        guard let date else { return "" }
        return duration(ms: Date().timeIntervalSince(date) * 1000)
    }

    static func dollars(micros: Double?) -> String {
        guard let micros else { return "$0.00" }
        return (micros / 1_000_000).formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }

    static func tokens(_ value: Double?) -> String {
        guard let value else { return "0" }
        return value.formatted(.number.notation(.compactName).precision(.significantDigits(1...3)))
    }
}

// MARK: Empty / error states

struct EmptyState: View {
    let icon: String
    let title: String
    var message: String?
    var action: (label: String, run: () -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(HP.ink3)
                .frame(width: 64, height: 64)
                .background(HP.control.opacity(0.6), in: .circle)
            VStack(spacing: 6) {
                Text(title).font(.display(21, weight: .medium)).foregroundStyle(HP.ink)
                if let message {
                    Text(message).font(.hpSubhead).foregroundStyle(HP.ink2).multilineTextAlignment(.center)
                }
            }
            if let action {
                Button(action.label, action: action.run)
                    .buttonStyle(.glass)
                    .font(.ui(15, weight: .medium))
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: 300)
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
    }
}

struct ErrorBanner: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(HP.waiting)
            Text(message).font(.hpFootnote).foregroundStyle(HP.ink).frame(maxWidth: .infinity, alignment: .leading)
            if let retry {
                Button("Retry", action: retry).font(.ui(13, weight: .semibold)).buttonStyle(.glass)
            }
        }
        .padding(12)
        .glassEffect(.regular.tint(HP.waiting.opacity(0.12)), in: .rect(cornerRadius: 18))
    }
}
