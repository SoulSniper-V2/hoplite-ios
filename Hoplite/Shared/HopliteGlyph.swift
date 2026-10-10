import SwiftUI

/// Hoplite's thread status glyphs, matching the web app's thread-row set: a sunburst spinner
/// for running, an amber half-disc for needs input, a green check, a red cross and a purple
/// branch for merged. Shared by the app and the Live Activity.
struct HopliteGlyph: View {
    /// A `ThreadStatus` raw value, or "merged".
    let status: String
    var size: CGFloat = 18
    var animated = true

    private var tint: Color {
        switch status {
        case "running", "queued": HP.running
        case "blocked", "waiting": HP.waiting
        case "ready": HP.ready
        case "failed": HP.failed
        case "merged": HP.merged
        default: HP.archived
        }
    }

    var body: some View {
        ZStack {
            Circle().fill(tint.opacity(status == "archived" ? 0.08 : 0.16))
            switch status {
            case "running":
                Sunburst(color: tint, animated: animated).padding(size * 0.2)
            case "queued":
                Circle().strokeBorder(tint.opacity(0.9), style: StrokeStyle(lineWidth: size * 0.09, dash: [size * 0.13, size * 0.11])).padding(size * 0.14)
            case "waiting":
                Circle().strokeBorder(tint, style: StrokeStyle(lineWidth: size * 0.09, dash: [size * 0.13, size * 0.11])).padding(size * 0.14)
            case "blocked":
                Circle().strokeBorder(tint, lineWidth: size * 0.09).padding(size * 0.2)
                HalfDisc().fill(tint).padding(size * 0.2)
            case "ready":
                Circle().strokeBorder(tint, lineWidth: size * 0.08).padding(size * 0.14)
                Image(systemName: "checkmark").font(.system(size: size * 0.38, weight: .bold)).foregroundStyle(tint)
            case "failed":
                Circle().strokeBorder(tint, lineWidth: size * 0.08).padding(size * 0.14)
                Image(systemName: "xmark").font(.system(size: size * 0.34, weight: .bold)).foregroundStyle(tint)
            case "merged":
                Image(systemName: "arrow.triangle.merge").font(.system(size: size * 0.46, weight: .semibold)).foregroundStyle(tint)
            default:
                Circle().strokeBorder(tint, lineWidth: size * 0.08).padding(size * 0.18)
            }
        }
        .frame(width: size, height: size)
    }
}

private nonisolated struct HalfDisc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: rect.width / 2, startAngle: .degrees(90), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        return path
    }
}

private struct Sunburst: View {
    let color: Color
    let animated: Bool
    @State private var angle = 0.0

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outer = min(size.width, size.height) / 2
            for index in 0..<8 {
                let theta = Double(index) / 8 * 2 * .pi
                let start = CGPoint(x: center.x + cos(theta) * outer * 0.42, y: center.y + sin(theta) * outer * 0.42)
                let end = CGPoint(x: center.x + cos(theta) * outer, y: center.y + sin(theta) * outer)
                var line = Path()
                line.move(to: start)
                line.addLine(to: end)
                context.stroke(line, with: .color(color.opacity(0.35 + 0.65 * Double(index) / 7)), style: StrokeStyle(lineWidth: max(1.2, outer * 0.24), lineCap: .round))
            }
        }
        .rotationEffect(.degrees(angle))
        .onAppear {
            guard animated else { return }
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { angle = 360 }
        }
    }
}
