import ActivityKit
import Foundation

/// Mirrors the workspace's live agents into a single Live Activity (Lock Screen + Dynamic Island).
/// Updates come from the app's event stream; background updates without the app need APNs push
/// relayed from Hoplite webhooks, which this client can't do on its own.
@MainActor
final class LiveActivityController {
    private var activity: Activity<HopliteActivityAttributes>?
    private var lastState: HopliteActivityAttributes.ContentState?

    init() {
        activity = Activity<HopliteActivityAttributes>.activities.first
    }

    func sync(threads: [AgentThread], approvals: [Approval], projects: [Project], workspace: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let live = threads.filter { thread in
            [.running, .queued, .waiting, .blocked].contains(thread.status) || approvals.contains { $0.threadId == thread.id }
        }
        let ranked = live.sorted { rank($0, approvals) < rank($1, approvals) }
        let agents = ranked.prefix(3).map { thread in
            let approval = approvals.first { $0.threadId == thread.id }
            return HopliteActivityAttributes.Agent(
                id: thread.id,
                title: thread.displayTitle,
                project: projects.first { $0.id == thread.projectId }?.name ?? "",
                status: approval != nil ? ThreadStatus.blocked.rawValue : thread.status.rawValue,
                startedAt: thread.runStartedAt.flatMap(ISO8601.parse) ?? thread.updated,
                approvalId: approval?.id,
                approvalSummary: approval.map { $0.summary ?? $0.toolName.map { "Run `\($0)`" } ?? "Continue the run" }?.replacingOccurrences(of: "`", with: ""),
                detail: thread.isPreparing ? phaseLabel(thread.initializationPhase) : nil
            )
        }
        let state = HopliteActivityAttributes.ContentState(
            agents: Array(agents),
            runningCount: threads.filter { $0.status == .running || $0.status == .queued }.count,
            attentionCount: approvals.count
        )
        guard state != lastState else { return }
        let previous = lastState
        lastState = state

        if state.agents.isEmpty {
            guard let current = activity else { return }
            nonisolated(unsafe) let ending = current
            var final = state
            final.finishedTitle = previous?.agents.first?.title
            self.activity = nil
            Task { await ending.end(.init(state: final, staleDate: nil), dismissalPolicy: .after(.now.addingTimeInterval(15 * 60))) }
            return
        }

        if let current = activity, current.activityState == .active {
            nonisolated(unsafe) let updating = current
            let alert = alert(from: previous, to: state)
            Task { await updating.update(.init(state: state, staleDate: .now.addingTimeInterval(30 * 60)), alertConfiguration: alert) }
        } else {
            activity = try? Activity.request(
                attributes: HopliteActivityAttributes(workspace: workspace),
                content: .init(state: state, staleDate: .now.addingTimeInterval(30 * 60)),
                pushType: nil
            )
        }
    }

    func endAll() {
        lastState = nil
        activity = nil
        Task {
            for activity in Activity<HopliteActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private func rank(_ thread: AgentThread, _ approvals: [Approval]) -> Int {
        if approvals.contains(where: { $0.threadId == thread.id }) { return 0 }
        switch thread.status {
        case .blocked: return 1
        case .running: return 2
        case .waiting: return 3
        default: return 4
        }
    }

    /// Light the Dynamic Island up only when a new approval arrives.
    private func alert(from old: HopliteActivityAttributes.ContentState?, to new: HopliteActivityAttributes.ContentState) -> AlertConfiguration? {
        guard let approval = new.approval, old?.approval?.approvalId != approval.approvalId else { return nil }
        return AlertConfiguration(title: "Approval needed", body: "\(approval.title): \(approval.approvalSummary ?? "")", sound: .default)
    }
}
