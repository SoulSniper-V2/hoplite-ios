import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct HopliteWidgets: WidgetBundle {
    var body: some Widget {
        HopliteLiveActivity()
    }
}

struct HopliteLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HopliteActivityAttributes.self) { context in
            LockScreenView(state: context.state, workspace: context.attributes.workspace)
                .activityBackgroundTint(Color(hex: 0x0F0F0F).opacity(0.92))
                .activitySystemActionForegroundColor(HP.action)
                .widgetURL(deepLink(context.state))
                .environment(\.colorScheme, .dark)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        MarkTile(size: 26)
                        Text("Hoplite").font(.display(16, weight: .medium)).foregroundStyle(.white)
                    }
                    .padding(.leading, 4)
                    .padding(.top, 2)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Group {
                        if state.attentionCount > 0 {
                            Label("\(state.attentionCount) need you", systemImage: "hand.raised.fill")
                                .foregroundStyle(HP.waiting)
                        } else if let start = state.oldestStart, state.runningCount > 0 {
                            Text(start, style: .timer)
                                .monospacedDigit()
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(HP.running)
                        } else {
                            Label("Done", systemImage: "checkmark").foregroundStyle(HP.ready)
                        }
                    }
                    .font(.ui(13, weight: .semibold))
                    .lineLimit(1)
                    .frame(maxWidth: 110, alignment: .trailing)
                    .padding(.trailing, 4)
                    .padding(.top, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        if let approval = state.approval {
                            ApprovalBlock(agent: approval)
                        } else {
                            ForEach(state.agents.prefix(2)) { AgentRow(agent: $0, compact: true) }
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
                }
            } compactLeading: {
                BrandMark(size: 17, color: HP.action).padding(.leading, 2)
            } compactTrailing: {
                if state.attentionCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "hand.raised.fill").font(.system(size: 11, weight: .bold))
                        Text("\(state.attentionCount)").font(.mono(13, weight: .semibold))
                    }
                    .foregroundStyle(HP.waiting)
                } else if let start = state.oldestStart {
                    Text(start, style: .timer)
                        .font(.mono(13, weight: .medium))
                        .foregroundStyle(HP.running)
                        .monospacedDigit()
                        .frame(maxWidth: 46)
                } else {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(HP.ready)
                }
            } minimal: {
                if state.attentionCount > 0 {
                    Image(systemName: "hand.raised.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(HP.waiting)
                } else {
                    BrandMark(size: 15, color: HP.action)
                }
            }
            .widgetURL(deepLink(state))
            .keylineTint(HP.action)
        }
    }

    private func deepLink(_ state: HopliteActivityAttributes.ContentState) -> URL? {
        (state.approval ?? state.agents.first).flatMap { URL(string: "hoplite-ios://thread/\($0.id)") }
    }
}

private struct LockScreenView: View {
    let state: HopliteActivityAttributes.ContentState
    let workspace: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                MarkTile(size: 24)
                Text("Hoplite").font(.display(16, weight: .medium)).foregroundStyle(.white)
                Text(workspace).font(.ui(13)).foregroundStyle(.white.opacity(0.45))
                Spacer(minLength: 6)
                Text(state.headline)
                    .font(.ui(12.5, weight: .semibold))
                    .foregroundStyle(state.attentionCount > 0 ? HP.waiting : .white.opacity(0.6))
            }
            if state.agents.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(HP.ready)
                    Text(state.finishedTitle ?? "Every run has finished").font(.ui(14.5, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                }
            } else if let approval = state.approval {
                ApprovalBlock(agent: approval)
                ForEach(state.agents.filter { $0.id != approval.id }.prefix(1)) { AgentRow(agent: $0, compact: true) }
            } else {
                ForEach(state.agents) { AgentRow(agent: $0, compact: false) }
            }
        }
        .padding(16)
    }
}

private struct AgentRow: View {
    let agent: HopliteActivityAttributes.Agent
    let compact: Bool

    var body: some View {
        HStack(spacing: 10) {
            HopliteGlyph(status: agent.status, size: 16, animated: false)
            VStack(alignment: .leading, spacing: 1) {
                Text(agent.title).font(.ui(compact ? 14 : 14.5, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                if !compact || agent.detail != nil {
                    Text(agent.detail ?? agent.project).font(.ui(11.5)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            trailing
        }
    }

    @ViewBuilder private var trailing: some View {
        switch agent.status {
        case "running":
            if let start = agent.startedAt {
                Text(start, style: .timer).font(.mono(12.5, weight: .medium)).foregroundStyle(HP.running).monospacedDigit().multilineTextAlignment(.trailing).frame(maxWidth: 64, alignment: .trailing)
            }
        case "blocked": Text("Needs input").font(.ui(12, weight: .semibold)).foregroundStyle(HP.waiting)
        case "waiting": Text("CI running").font(.ui(12, weight: .semibold)).foregroundStyle(HP.waiting)
        case "queued": Text("Starting").font(.ui(12, weight: .semibold)).foregroundStyle(HP.running)
        case "failed": Text("Failed").font(.ui(12, weight: .semibold)).foregroundStyle(HP.failed)
        default: Text("Done").font(.ui(12, weight: .semibold)).foregroundStyle(HP.ready)
        }
    }
}

private struct ApprovalBlock: View {
    let agent: HopliteActivityAttributes.Agent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                HopliteGlyph(status: "blocked", size: 22, animated: false)
                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.approvalSummary ?? "Continue the run").font(.ui(14, weight: .medium)).foregroundStyle(.white).lineLimit(2)
                    Text(agent.title).font(.ui(11.5)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                }
            }
            if let approvalId = agent.approvalId {
                HStack(spacing: 8) {
                    Button(intent: ResolveApprovalIntent(threadId: agent.id, approvalId: approvalId, approved: false)) {
                        Text("Deny").font(.ui(14, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 9)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(.white.opacity(0.14), in: .capsule)
                    Button(intent: ResolveApprovalIntent(threadId: agent.id, approvalId: approvalId, approved: true)) {
                        Text("Approve").font(.ui(14, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 9)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(HP.action, in: .capsule)
                }
            }
        }
    }
}

private struct MarkTile: View {
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(LinearGradient(colors: [HP.actionBright, HP.action, HP.actionDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(BrandMark(size: size * 0.62, color: Color(hex: 0x111111)))
            .frame(width: size, height: size)
    }
}

struct BrandMark: View {
    var size: CGFloat
    var color: Color

    var body: some View {
        Image("BrandMark").resizable().renderingMode(.template).scaledToFit().frame(width: size, height: size).foregroundStyle(color)
    }
}
