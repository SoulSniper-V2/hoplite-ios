import Foundation

// MARK: JSON

/// A loosely typed JSON value, used for MCP server configuration whose shape varies by transport.
nonisolated enum JSONValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else { self = .null }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var string: String? { if case .string(let value) = self { value } else { nil } }
    var bool: Bool? { if case .bool(let value) = self { value } else { nil } }
    var object: [String: JSONValue]? { if case .object(let value) = self { value } else { nil } }

    subscript(key: String) -> JSONValue? { object?[key] }
}

// MARK: Projects

nonisolated struct ProjectRepo: Codable, Hashable, Sendable, Identifiable {
    var repoFullName: String
    var repositoryId: String?
    var branch: String?

    var id: String { repoFullName }
}

nonisolated struct SandboxSpec: Codable, Hashable, Sendable {
    var defaultCpu: Int?
    var defaultMemoryGiB: Int?
    var maxCpu: Int?
    var maxDiskGiB: Int?
    var maxMemoryGiB: Int?
    var runtimeProfile: String?
}

nonisolated struct WorkspaceProject: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var description: String?
    var taskCode: String?
    var repos: [ProjectRepo]?
    var githubInstallationId: String?
    var defaultBranch: String?
    var previewPort: Int?
    var setupScript: String?
    var runScript: String?
    var archiveScript: String?
    var instructions: String?
    var defaultModel: String?
    var reasoningEffort: String?
    var agentSpeed: String?
    var prReviewAutofixDefault: Bool?
    var sandboxSpec: SandboxSpec?
    var framework: String?
    var createdAt: String?
    var updatedAt: String?
}

/// The editable fields of a project, as sent by `PATCH /api/projects/{id}`.
nonisolated struct ProjectDraft: Hashable, Sendable {
    var name: String
    var description: String
    var defaultBranch: String
    var previewPort: String
    var setupScript: String
    var runScript: String
    var archiveScript: String
    var instructions: String
    var defaultModel: String?
    var reasoningEffort: String?
    var agentSpeed: String?

    init(_ project: WorkspaceProject) {
        name = project.name
        description = project.description ?? ""
        defaultBranch = project.defaultBranch ?? ""
        previewPort = project.previewPort.map(String.init) ?? ""
        setupScript = project.setupScript ?? ""
        runScript = project.runScript ?? ""
        archiveScript = project.archiveScript ?? ""
        instructions = project.instructions ?? ""
        defaultModel = project.defaultModel
        reasoningEffort = project.reasoningEffort
        agentSpeed = project.agentSpeed
    }

    var isValid: Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard !previewPort.isEmpty else { return true }
        return Int(previewPort).map { (3000...9999).contains($0) } ?? false
    }
}

nonisolated struct NewProject: Hashable, Sendable {
    var name: String
    var repositoryId: String
    var repositoryFullName: String
    var sourceControlConnectionId: String?
    var baseBranch: String?
    var previewPort: Int?
    var setupScript: String?
    var runScript: String?
    var archiveScript: String?
    var framework: String?
}

nonisolated struct RepoAssignment: Hashable, Sendable, Identifiable {
    var repositoryId: String
    var repoFullName: String
    var baseBranch: String?
    var sourceControlConnectionId: String?

    var id: String { repositoryId }
}

// MARK: GitHub

nonisolated struct GitHubRepository: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var installationId: String?
    var repositoryId: Int?
    var fullName: String
    var cloneUrl: String?
    var language: String?
    var framework: String?
    var defaultBranch: String?
    var `private`: Bool?

    var name: String { fullName.split(separator: "/").last.map(String.init) ?? fullName }
}

nonisolated struct GitHubInstallation: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var installationId: Int?
    var accountLogin: String
    var accountType: String?
    var managementUrl: String?
    var repositories: [GitHubRepository]?
}

nonisolated struct RepoScript: Codable, Hashable, Sendable {
    var enabled: Bool?
    var command: String?
}

nonisolated struct RepoInspection: Codable, Hashable, Sendable {
    struct Scripts: Codable, Hashable, Sendable {
        var setup: RepoScript?
        var run: RepoScript?
        var archive: RepoScript?
    }
    struct Settings: Codable, Hashable, Sendable {
        var path: String?
        var previewPort: Int?
        var invalid: Bool?
        var scripts: Scripts?
    }
    var framework: String?
    var settings: Settings?
}

// MARK: Environment

nonisolated struct EnvVar: Codable, Identifiable, Hashable, Sendable {
    var key: String
    var updatedAt: String?

    var id: String { key }
}

// MARK: MCP

nonisolated struct McpServer: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var projectId: String?
    var name: String
    var config: [String: JSONValue]?
    var enabled: Bool?
    var createdAt: String?
    var updatedAt: String?

    var isEnabled: Bool { enabled ?? true }
    var transport: String { config?["transport"]?.string ?? "http" }
    var url: String? { config?["url"]?.string }
    var headerNames: [String] { config?["headers"]?.object?.keys.sorted() ?? [] }
    var usesOAuth: Bool { config?["auth"]?["kind"]?.string == "oauth2" }
    var needsSignIn: Bool { config?["needsAuth"]?.bool == true || config?["auth"]?["status"]?.string == "needs_reauth" }
}

nonisolated struct McpServerDraft: Hashable, Sendable {
    enum Auth: Hashable, Sendable {
        case keep
        case none
        case bearer(token: String)
        case header(name: String, value: String)
    }

    var name: String
    var projectId: String?
    var transport: String
    var url: String
    var auth: Auth
    var enabled: Bool
}

// MARK: Webhooks

nonisolated struct Webhook: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var orgId: String?
    var projectId: String?
    var url: String
    var types: [String]?
    var disabled: Bool
    var createdAt: String?
    var updatedAt: String?

    var host: String { URL(string: url)?.host() ?? url }
    var path: String {
        guard let url = URL(string: url) else { return "" }
        let path = url.path()
        return path == "/" ? "" : path
    }
}

/// A subscription together with its signing secret, which the API returns only once.
nonisolated struct WebhookSecret: Hashable, Sendable {
    var webhook: Webhook
    var secret: String?
}

nonisolated struct WebhookDelivery: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var eventId: String
    var state: String
    var attempts: Int?
    var lastStatus: Int?
    var lastError: String?
    var createdAt: String?
    var finishedAt: String?
}

nonisolated struct WebhookDeliveryPage: Sendable {
    var deliveries: [WebhookDelivery]
    var nextCursor: String?
}

// MARK: Service accounts

nonisolated struct ServiceAccount: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var orgId: String?
    var name: String
    var permissions: [String: [String]]
    var projectIds: [String]?
    var disabled: Bool
    var createdAt: String?
    var updatedAt: String?

    var grantCount: Int { permissions.values.reduce(0) { $0 + $1.count } }
}

nonisolated struct ServiceCredential: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var accountId: String
    var expiresAt: String?
    var revoked: Bool
    var createdAt: String?

    var isExpired: Bool { expiresAt.flatMap(ISO8601.parse).map { $0 < .now } ?? false }
}

/// An account plus a freshly issued key, which the API returns only once.
nonisolated struct ServiceAccountSecret: Hashable, Sendable {
    var account: ServiceAccount
    var credential: ServiceCredential?
    var key: String?
}

nonisolated struct ServiceAccountDraft: Hashable, Sendable {
    var name: String
    var permissions: [String: Set<String>]
    var projectIds: [String]?
}

// MARK: Capabilities

nonisolated struct FactoryOperation: Codable, Identifiable, Hashable, Sendable {
    var operationId: String
    var method: String
    var path: String
    var permission: String?
    var permissions: [String]?

    var id: String { operationId }
}

nonisolated struct FactoryLimits: Codable, Hashable, Sendable {
    var eventRetentionDays: Int?
    var idempotencyRetentionDays: Int?
    var credentialLifetimeDays: Int?
    var credentialOverlapHours: Int?
    var attachmentMaxBytes: Int?
}

nonisolated struct FactoryCapabilities: Codable, Hashable, Sendable {
    var principalId: String
    var orgId: String
    var projectIds: [String]?
    var permissions: [String: [String]]?
    var operations: [FactoryOperation]?
    var availability: [String: Bool]?
    var limits: FactoryLimits?
}

nonisolated struct ServiceHealth: Codable, Hashable, Sendable {
    var ok: Bool
    var service: String?
    var version: String?
}

// MARK: Automations

nonisolated struct AutomationDraft: Hashable, Sendable {
    enum Trigger: Hashable, Sendable {
        case schedule(AutomationSchedule)
        case event(String?)
    }

    var name: String
    var prompt: String
    var enabled: Bool
    var trigger: Trigger
    var repoFullName: String?
    var modelId: String?
}

/// A created automation. Webhook automations carry their trigger credential only on this response.
nonisolated struct AutomationCreateResult: Hashable, Sendable {
    var automation: Automation
    var webhookToken: String?
    var webhookUrl: String?
}

nonisolated struct AutomationRecentExecution: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var status: String
    var runStatus: String?
    var createdAt: String?
}

nonisolated struct AutomationStatus: Codable, Identifiable, Hashable, Sendable {
    var automationId: String
    var recentExecutions: [AutomationRecentExecution]?
    var lastStatus: String?
    var lastRunStatus: String?
    var lastError: String?
    var lastExecutionAt: String?
    var runs30d: Int?
    var succeeded30d: Int?
    var failed30d: Int?

    var id: String { automationId }
}

nonisolated struct AutomationStatusTotals: Codable, Hashable, Sendable {
    var runs30d: Int?
    var succeeded30d: Int?
}

nonisolated struct AutomationStatusReport: Codable, Hashable, Sendable {
    var statuses: [AutomationStatus]
    var totals: AutomationStatusTotals?

    func status(for automationId: String) -> AutomationStatus? { statuses.first { $0.automationId == automationId } }
}
