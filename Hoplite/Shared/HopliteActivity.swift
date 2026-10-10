import ActivityKit
import AppIntents
import Foundation

/// One Live Activity for the whole workspace: what's running and what's waiting on you.
/// Compiled into both the app and the widget extension.
nonisolated struct HopliteActivityAttributes: ActivityAttributes {
    struct Agent: Codable, Hashable, Identifiable {
        var id: String
        var title: String
        var project: String
        /// `ThreadStatus` raw value: running, queued, waiting, blocked, ready, failed.
        var status: String
        var startedAt: Date?
        var approvalId: String?
        var approvalSummary: String?
        var detail: String?

        var needsApproval: Bool { approvalId != nil }
    }

    struct ContentState: Codable, Hashable {
        var agents: [Agent]
        var runningCount: Int
        var attentionCount: Int
        var finishedTitle: String?

        var headline: String {
            if attentionCount > 0 { return attentionCount == 1 ? "1 agent needs you" : "\(attentionCount) agents need you" }
            if runningCount > 0 { return runningCount == 1 ? "1 agent working" : "\(runningCount) agents working" }
            return finishedTitle.map { "Done · \($0)" } ?? "All agents finished"
        }

        var approval: Agent? { agents.first(where: \.needsApproval) }
        var oldestStart: Date? { agents.compactMap(\.startedAt).min() }
    }

    var workspace: String
}

/// Lets the Live Activity's buttons reach the app's live session.
@MainActor
enum ApprovalBridge {
    static var handler: ((_ threadId: String, _ approvalId: String, _ approved: Bool) async -> Void)?
}

/// Approve or deny a gated tool call straight from the Lock Screen or Dynamic Island.
struct ResolveApprovalIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Resolve approval"
    static let description = IntentDescription("Approve or deny a Hoplite agent's pending tool call.")
    static let isDiscoverable = false

    @Parameter(title: "Thread") var threadId: String
    @Parameter(title: "Approval") var approvalId: String
    @Parameter(title: "Approved") var approved: Bool

    init() {}

    init(threadId: String, approvalId: String, approved: Bool) {
        self.threadId = threadId
        self.approvalId = approvalId
        self.approved = approved
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        await ApprovalBridge.handler?(threadId, approvalId, approved)
        return .result()
    }
}
