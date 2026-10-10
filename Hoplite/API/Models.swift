import Foundation

nonisolated enum ThreadStatus: String, Codable, Sendable, CaseIterable {
    case queued, running, waiting, blocked, ready, failed, archived, unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ThreadStatus(rawValue: raw) ?? .unknown
    }

    var isActive: Bool { self == .running || self == .queued || self == .waiting }
    var needsAttention: Bool { self == .blocked || self == .failed }
}

nonisolated enum RunStatus: String, Codable, Sendable {
    case queued, running, waiting, completed, failed, cancelled, unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = RunStatus(rawValue: raw) ?? .unknown
    }

    var isLive: Bool { self == .queued || self == .running || self == .waiting }
}

nonisolated struct RepoRef: Codable, Hashable, Sendable {
    var fullName: String?
    var name: String?
    var owner: String?
    var defaultBranch: String?

    var display: String { fullName ?? [owner, name].compactMap(\.self).joined(separator: "/") }
}

nonisolated struct Project: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var description: String?
    var taskCode: String?
    var repos: [RepoRef]?
    var defaultBranch: String?
    var defaultModel: String?
    var reasoningEffort: String?
    var framework: String?
    var updatedAt: String?
}

nonisolated struct UserSummary: Codable, Hashable, Sendable {
    var id: String
    var name: String
    var image: String?
}

nonisolated struct ChecksSummary: Codable, Hashable, Sendable {
    var total: Int
    var succeeded: Int
    var failing: Int
    var running: Int
}

nonisolated struct GitHubSummary: Codable, Hashable, Sendable {
    var state: String?
    var draft: Bool?
    var mergeable: String?
    var mergeQueued: Bool?
    var checks: ChecksSummary?
    var unresolvedCount: Int?
}

nonisolated struct PullRequest: Codable, Hashable, Sendable, Identifiable {
    var id: String?
    var number: Int
    var url: String
    var repoFullName: String
    var state: String
    var headRef: String?
    var headSha: String?
    var baseRef: String?
    var draft: Bool?
    var githubSummary: GitHubSummary?

    var stableID: String { id ?? "\(repoFullName)#\(number)" }

    var isReadyToMerge: Bool {
        guard (githubSummary?.state ?? state) == "open", draft != true, let checks = githubSummary?.checks else { return false }
        return checks.total > 0 && checks.succeeded == checks.total && githubSummary?.mergeable != "conflicting"
    }
}

nonisolated struct ThreadTask: Codable, Hashable, Sendable {
    var id: String
    var identifier: String?
    var title: String?
    var status: String?
}

nonisolated struct AgentThread: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var projectId: String
    var modelId: String?
    var title: String?
    var status: ThreadStatus
    var archivedAt: String?
    var initializationState: String?
    var initializationPhase: String?
    var initializationErrorMessage: String?
    var waitingOn: [String]?
    var blockedOn: [String]?
    var tasks: [ThreadTask]?
    var pullRequests: [PullRequest]?
    var primaryPullRequest: PullRequest?
    var createdAt: String?
    var updatedAt: String?
    var spendLimitMicros: Int?
    var version: Int?
    var archiveVersion: Int?
    var titleVersion: Int?
    var latestUserMessageAt: String?
    var workspaceStatus: String?
    var latestRunId: String?
    var runStartedAt: String?
    var runStatus: RunStatus?
    var runSteerable: Bool?
    var stopRequestedAt: String?
    var runActiveDurationMs: Int?
    var createdByAutomation: Bool?
    var participantUserIds: [String]?

    var displayTitle: String {
        guard let title, !title.trimmingCharacters(in: .whitespaces).isEmpty else { return "Untitled thread" }
        return title
    }

    var pullRequest: PullRequest? { primaryPullRequest ?? pullRequests?.first }
    var updated: Date? { (updatedAt ?? createdAt).flatMap(ISO8601.parse) }
    var isPreparing: Bool { initializationState == "accepted" || initializationState == "preparing" }
    var hasLiveRun: Bool { runStatus?.isLive == true || status == .running || status == .queued }
}

nonisolated enum MessageRole: String, Codable, Sendable {
    case user, assistant, system, tool, unknown
    init(from decoder: Decoder) throws {
        self = MessageRole(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }
}

nonisolated enum MessageKind: String, Codable, Sendable {
    case chat, thinking, tool, status, unknown
    init(from decoder: Decoder) throws {
        self = MessageKind(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }
}

nonisolated struct Message: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var threadId: String
    var runId: String?
    var authorUserId: String?
    var author: UserSummary?
    var role: MessageRole
    var kind: MessageKind?
    var content: String
    var createdAt: String
    var toolCallId: String?
    var toolName: String?
    var checkpointId: String?
    var metadata: MessageMetadata?

    var created: Date? { ISO8601.parse(createdAt) }
    var attachments: [MessageAttachment] { metadata?.attachments ?? [] }
    var resolvedKind: MessageKind {
        if let kind, kind != .unknown { return kind }
        return role == .tool ? .tool : .chat
    }
}

nonisolated struct RunSummary: Codable, Hashable, Sendable {
    var id: String
    var status: String?
}

nonisolated struct Run: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var threadId: String
    var status: RunStatus
    var createdAt: String
    var startedAt: String?
    var finishedAt: String?
}

nonisolated struct ActivityItem: Codable, Identifiable, Hashable, Sendable {
    var kind: String
    var id: String
    var threadId: String
    var runId: String?
    var toolCallId: String?
    var toolName: String?
    var status: String
    var createdAt: String
    var completedAt: String?
    var description: String?
    var inputPreview: String?
    var outputPreview: String?
    var errorPreview: String?

    var isRunning: Bool { status == "running" || status == "pending" || status == "started" }
    var isFailed: Bool { status == "failed" || status == "error" || errorPreview != nil }
}

nonisolated struct Approval: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var threadId: String
    var runId: String?
    var toolName: String?
    var toolCallId: String?
    var requestEventId: String?
    var actionable: Bool
    var createdAt: String
    /// Not part of the public payload; demo mode fills it to describe the gated action.
    var summary: String?
}

nonisolated struct DiffFile: Codable, Identifiable, Hashable, Sendable {
    var path: String
    var previousPath: String?
    var state: String?
    var additions: Int?
    var deletions: Int?
    var patch: String?
    var truncated: Bool?
    var truncatedReason: String?

    var id: String { path }
    var fileName: String { (path as NSString).lastPathComponent }
    var directory: String {
        let dir = (path as NSString).deletingLastPathComponent
        return dir.isEmpty ? "" : dir + "/"
    }
}

nonisolated struct DiffStats: Codable, Hashable, Sendable {
    var files: Int
    var additions: Int
    var deletions: Int
}

nonisolated enum DiffMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case uncommitted, base, pr
    var id: String { rawValue }
    var label: String {
        switch self {
        case .uncommitted: "Working"
        case .base: "Branch"
        case .pr: "PR"
        }
    }
}

nonisolated struct ThreadDiff: Codable, Hashable, Sendable {
    var threadId: String
    var mode: DiffMode
    var files: [DiffFile]
    var stats: DiffStats?
    var effectiveMode: DiffMode?
    var isFallback: Bool?
    var unavailableReason: String?

    var totals: DiffStats {
        stats ?? DiffStats(
            files: files.count,
            additions: files.reduce(0) { $0 + ($1.additions ?? 0) },
            deletions: files.reduce(0) { $0 + ($1.deletions ?? 0) }
        )
    }
}

nonisolated struct PRCheck: Codable, Hashable, Sendable, Identifiable {
    var name: String
    var status: String
    var conclusion: String?
    var startedAt: String?
    var completedAt: String?
    var url: String?
    var id: String { name + (startedAt ?? "") }
}

nonisolated struct PullRequestStatus: Codable, Hashable, Sendable {
    var number: Int
    var url: String
    var repoFullName: String
    var title: String?
    var body: String?
    var state: String
    var draft: Bool?
    var mergeable: String?
    var mergeQueued: Bool?
    var checks: [PRCheck]?
    var additions: Int?
    var deletions: Int?
    var changedFiles: Int?
    var aheadBy: Int?
    var behindBy: Int?
    var baseRef: String?
    var headRef: String?
    var headSha: String?
    var allowedMergeMethods: [String]?
}

nonisolated struct MergeResult: Codable, Hashable, Sendable {
    var merged: Bool
    var queued: Bool?
    var sha: String?
    var message: String?
}

nonisolated struct ModelInfo: Codable, Identifiable, Hashable, Sendable {
    struct Capabilities: Codable, Hashable, Sendable {
        var contextWindowTokens: Int?
        var reasoningLevels: [String]?
        var supportsFast: Bool?
        var supportsImages: Bool?
    }
    var id: String
    var name: String
    var provider: String
    var requiredPlan: String?
    var contextVariantOf: String?
    var capabilities: Capabilities?
}

nonisolated struct ModelCatalog: Codable, Hashable, Sendable {
    struct RunConfig: Codable, Hashable, Sendable {
        var defaultModelId: String
        var defaultReasoning: String?
        var reasoningOptions: [String]?
    }
    var models: [ModelInfo]
    var runConfig: RunConfig?

    func model(_ id: String?) -> ModelInfo? { models.first { $0.id == id } }
    var primaryModels: [ModelInfo] { models.filter { $0.contextVariantOf == nil } }
}

nonisolated struct ThreadUsage: Codable, Hashable, Sendable {
    var totalCostMicros: Double?
    var spendLimitMicros: Int?
    var llmCostMicros: Double?
    var vmCostMicros: Double?
    var runCount: Double?
    var inputTokens: Double?
    var outputTokens: Double?
    var latestContextTokens: Double?
    var topModel: String?
    var runtimeMs: Double?
    var usesByok: Bool?
}

nonisolated struct BillingSummary: Codable, Hashable, Sendable {
    var grantedCredits: Double?
    var remainingCredits: Double?
    var usedCredits: Double?
    var heldCredits: Double?
    var available: Bool?
    var nextResetAt: String?
    var includedCredits: Double?
    var remainingIncludedCredits: Double?
    var prepaidCredits: Double?
}

nonisolated struct BillingPlan: Codable, Hashable, Sendable {
    var plan: String
    var billingInterval: String?
    var sandboxIdleMinutes: Int?
    var seatCount: Int?
}

nonisolated struct OrganizationUsage: Codable, Hashable, Sendable {
    var orgId: String
    var totalCostMicros: Double?
    var inputTokens: Double?
    var outputTokens: Double?
    var events: Double?
}

nonisolated struct AutomationSchedule: Codable, Hashable, Sendable {
    var mode: String
    var expression: String?
    var timezone: String?
    var intervalMs: Double?
}

nonisolated struct Automation: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var projectId: String
    var name: String
    var enabled: Bool
    var triggerKind: String
    var eventKind: String?
    var schedule: AutomationSchedule?
    var prompt: String
    var title: String?
    var repoFullName: String?
    var modelId: String?
    var nextRunAt: String?
    var lastRunAt: String?
    var isDraft: Bool?
}

nonisolated struct AutomationExecution: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var automationId: String
    var projectId: String
    var triggerKind: String
    var status: String
    var threadId: String?
    var threadTitle: String?
    var error: String?
    var createdAt: String
    var runStatus: String?
    var runDurationMs: Int?
}

nonisolated struct Checkpoint: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var threadId: String
    var runId: String?
    var label: String?
    var gitCommitSha: String?
    var createdAt: String
}

nonisolated struct PreviewGateway: Codable, Hashable, Sendable {
    var header: String
    var token: String
    var expiresAt: String
}

nonisolated struct Preview: Codable, Hashable, Sendable {
    var status: String
    var name: String?
    var port: Int?
    var reason: String?
    var url: String?
    var gateway: PreviewGateway?
}

nonisolated struct RunFailure: Codable, Hashable, Sendable {
    var code: String
    var message: String
}

nonisolated struct UploadedAttachment: Hashable, Sendable {
    var artifactId: String
    var contentType: String
    var name: String
}

nonisolated struct ThreadPage: Sendable {
    var threads: [AgentThread]
    var nextCursor: String?
    var statusCounts: [String: Int]
    var totalCount: Int
}

nonisolated struct PublicEvent: Codable, Hashable, Sendable {
    struct Payload: Codable, Hashable, Sendable {
        var id: String?
        var status: String?
        var role: String?
    }
    var id: String
    var type: String
    var projectId: String?
    var threadId: String?
    var runId: String?
    var data: Payload?
    var occurredAt: String?
    var cursor: String?
}

nonisolated struct DraftFrame: Hashable, Sendable {
    var messageId: String
    var revision: Int
    var content: String
    var kind: MessageKind
}

nonisolated enum StreamFrame: Sendable {
    case event(PublicEvent)
    case draft(DraftFrame)
    case draftRemoved(messageId: String)
    case heartbeat
}

nonisolated enum ISO8601 {
    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let plain = ISO8601DateFormatter()

    static func parse(_ string: String) -> Date? {
        fractional.date(from: string) ?? plain.date(from: string)
    }

    static func string(_ date: Date) -> String { fractional.string(from: date) }
}

nonisolated struct ReviewComment: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var authorLogin: String?
    var authorAvatarUrl: String?
    var body: String
    var createdAt: String?
    var path: String?
    var line: Int?
    var url: String?
    var isOutdated: Bool?
}

nonisolated struct ReviewThread: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var path: String?
    var line: Int?
    var isResolved: Bool
    var isOutdated: Bool
    var comments: [ReviewComment]
}

nonisolated struct PullRequestComments: Codable, Hashable, Sendable {
    var number: Int
    var repoFullName: String
    var commentsAvailable: Bool?
    var unresolvedCount: Int
    var comments: [ReviewComment]?
    var reviewThreads: [ReviewThread]?
}

nonisolated struct ReviewLoop: Codable, Hashable, Sendable {
    var id: String
    var pullRequestId: String
    var enabled: Bool
    var autoMerge: Bool?
    var status: String
    var passCount: Int
    var blockedReason: String?
    var lastErrorMessage: String?
    var lastObservedAt: String?

    var statusLabel: String {
        switch status {
        case "observing": "Watching for review feedback"
        case "waiting_checks": "Waiting for checks"
        case "fixing": "Fixing review feedback"
        case "finalizing": "Finalizing"
        case "ready": "Ready"
        case "blocked": blockedReason ?? "Blocked"
        case "error": lastErrorMessage ?? "Error"
        default: "Off"
        }
    }
}

nonisolated struct WorkspaceRecovery: Codable, Hashable, Sendable {
    var bricked: Bool
    var canReset: Bool
    var canRestoreSnapshot: Bool
    var snapshotSupersededAt: String?
}

nonisolated struct MessageAttachment: Codable, Hashable, Sendable {
    var artifactId: String
    var contentType: String?
    var name: String?

    private enum CodingKeys: String, CodingKey { case artifactId, id, contentType, name }

    init(artifactId: String, contentType: String?, name: String?) {
        self.artifactId = artifactId
        self.contentType = contentType
        self.name = name
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = try c.decodeIfPresent(String.self, forKey: .artifactId) ?? c.decodeIfPresent(String.self, forKey: .id) else {
            throw DecodingError.keyNotFound(CodingKeys.artifactId, .init(codingPath: c.codingPath, debugDescription: "artifactId"))
        }
        artifactId = id
        contentType = try c.decodeIfPresent(String.self, forKey: .contentType)
        name = try c.decodeIfPresent(String.self, forKey: .name)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(artifactId, forKey: .artifactId)
        try c.encodeIfPresent(contentType, forKey: .contentType)
        try c.encodeIfPresent(name, forKey: .name)
    }
}

nonisolated struct MessageMetadata: Codable, Hashable, Sendable {
    var attachments: [MessageAttachment]?
    var model: String?

    init(attachments: [MessageAttachment]? = nil, model: String? = nil) {
        self.attachments = attachments
        self.model = model
    }

    private enum CodingKeys: String, CodingKey { case attachments, model }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        attachments = (try? c.decodeIfPresent([MessageAttachment].self, forKey: .attachments)) ?? nil
        model = try? c.decodeIfPresent(String.self, forKey: .model)
    }
}

nonisolated struct ThreadOptions: Hashable, Sendable {
    var operationId = UUID().uuidString
    var attachmentTickets: [String] = []
    var reasoning: String?
    var fast = false
    var autoMerge: Bool?
    var spendLimitMicros: Int?
}
