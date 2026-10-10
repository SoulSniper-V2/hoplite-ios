import Foundation

/// Workspace administration: projects, environment, MCP servers, webhooks, service accounts,
/// automation management and capabilities. `LiveService` talks to api.hoplite.sh; `DemoService`
/// keeps the same data in memory.
protocol WorkspaceAdmin: AnyObject, Sendable {
    // Projects
    func workspaceProjects() async throws -> [WorkspaceProject]
    func createProject(_ project: NewProject) async throws -> WorkspaceProject
    func updateProject(id: String, draft: ProjectDraft) async throws -> WorkspaceProject
    func deleteProject(id: String) async throws
    func projectRepositories(projectId: String) async throws -> [ProjectRepo]
    func assignRepositories(projectId: String, repositories: [RepoAssignment]) async throws -> WorkspaceProject

    // GitHub
    func githubInstallations() async throws -> [GitHubInstallation]
    func githubRepositories() async throws -> [GitHubRepository]
    func githubBranches(repositoryId: String) async throws -> [String]
    func inspectRepository(repositoryId: String) async throws -> RepoInspection

    // Environment variables (values are write-only)
    func envVars(projectId: String) async throws -> [EnvVar]
    func setEnvVar(projectId: String, key: String, value: String) async throws -> EnvVar
    func deleteEnvVar(projectId: String, key: String) async throws

    // MCP servers
    func mcpServers() async throws -> [McpServer]
    func createMcpServer(_ draft: McpServerDraft) async throws -> McpServer
    func updateMcpServer(id: String, draft: McpServerDraft) async throws -> McpServer
    func deleteMcpServer(id: String) async throws

    // Webhooks
    func webhooks() async throws -> [Webhook]
    func createWebhook(url: String, projectId: String?, types: [String]) async throws -> WebhookSecret
    func updateWebhook(id: String, url: String?, types: [String]?, disabled: Bool?) async throws -> Webhook
    func deleteWebhook(id: String) async throws
    func webhookDeliveries(id: String, cursor: String?) async throws -> WebhookDeliveryPage
    func redeliver(webhookId: String, deliveryId: String) async throws
    func rotateWebhookSecret(id: String) async throws -> WebhookSecret

    // Service accounts
    func serviceAccounts() async throws -> [ServiceAccount]
    func ownServiceAccount() async throws -> ServiceAccount
    func createServiceAccount(_ draft: ServiceAccountDraft) async throws -> ServiceAccountSecret
    func updateServiceAccount(id: String, draft: ServiceAccountDraft) async throws -> ServiceAccount
    func setServiceAccountDisabled(id: String, disabled: Bool) async throws -> ServiceAccount
    func serviceCredentials(accountId: String) async throws -> [ServiceCredential]
    func revokeCredential(accountId: String, credentialId: String) async throws
    func rotateServiceAccount(id: String) async throws -> ServiceAccountSecret
    func rotateOwnCredential() async throws -> ServiceAccountSecret

    // Automations
    func projectAutomations(projectId: String) async throws -> [Automation]
    func createAutomation(projectId: String, draft: AutomationDraft) async throws -> AutomationCreateResult
    func updateAutomation(projectId: String, id: String, draft: AutomationDraft) async throws -> Automation
    func deleteAutomation(projectId: String, id: String) async throws
    func automationStatus(projectId: String) async throws -> AutomationStatusReport

    // About
    func capabilities() async throws -> FactoryCapabilities
    func health() async throws -> ServiceHealth
}

// MARK: Live

extension LiveService: WorkspaceAdmin {
    private struct Ack: Decodable {}

    private static func nullable(_ text: String) -> Any {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? NSNull() : trimmed
    }

    // MARK: Projects

    func workspaceProjects() async throws -> [WorkspaceProject] {
        struct R: Decodable { var projects: [WorkspaceProject]; var nextCursor: String? }
        var all: [WorkspaceProject] = []
        var cursor: String?
        repeat {
            let page: R = try await client.get("/api/projects", query: ["limit": "100", "pagination": "cursor", "cursor": cursor])
            all += page.projects
            cursor = page.nextCursor
        } while cursor != nil && all.count < 500
        return all
    }

    func createProject(_ project: NewProject) async throws -> WorkspaceProject {
        struct R: Decodable { var project: WorkspaceProject }
        var body: [String: Any] = ["name": project.name, "repositoryId": project.repositoryId]
        if let id = project.sourceControlConnectionId { body["sourceControlConnectionId"] = id }
        if let branch = project.baseBranch { body["baseBranch"] = branch }
        if let port = project.previewPort { body["previewPort"] = port }
        if let script = project.setupScript { body["setupScript"] = script }
        if let script = project.runScript { body["runScript"] = script }
        if let script = project.archiveScript { body["archiveScript"] = script }
        return try await client.send("POST", "/api/projects", body: body, as: R.self).project
    }

    func updateProject(id: String, draft: ProjectDraft) async throws -> WorkspaceProject {
        struct R: Decodable { var project: WorkspaceProject }
        var body: [String: Any] = [
            "name": draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            "description": Self.nullable(draft.description),
            "defaultBranch": Self.nullable(draft.defaultBranch),
            "setupScript": Self.nullable(draft.setupScript),
            "runScript": Self.nullable(draft.runScript),
            "archiveScript": Self.nullable(draft.archiveScript),
            "instructions": Self.nullable(draft.instructions),
            "defaultModel": draft.defaultModel ?? NSNull(),
            "reasoningEffort": draft.reasoningEffort ?? NSNull(),
            "agentSpeed": draft.agentSpeed ?? NSNull(),
        ]
        if let port = Int(draft.previewPort) { body["previewPort"] = port }
        return try await client.send("PATCH", "/api/projects/\(id)", body: body, as: R.self).project
    }

    func deleteProject(id: String) async throws {
        let _: Ack = try await client.send("DELETE", "/api/projects/\(id)")
    }

    func projectRepositories(projectId: String) async throws -> [ProjectRepo] {
        struct R: Decodable { var repositories: [ProjectRepo]? }
        return try await client.get("/api/projects/\(projectId)/repositories", as: R.self).repositories ?? []
    }

    func assignRepositories(projectId: String, repositories: [RepoAssignment]) async throws -> WorkspaceProject {
        struct R: Decodable { var project: WorkspaceProject }
        let items: [[String: Any]] = repositories.map { repo in
            var item: [String: Any] = ["repositoryId": repo.repositoryId]
            if let branch = repo.baseBranch { item["baseBranch"] = branch }
            if let connection = repo.sourceControlConnectionId { item["sourceControlConnectionId"] = connection }
            return item
        }
        return try await client.send("PUT", "/api/projects/\(projectId)/repositories", body: ["repositories": items], as: R.self).project
    }

    // MARK: GitHub

    func githubInstallations() async throws -> [GitHubInstallation] {
        struct R: Decodable { var installations: [GitHubInstallation] }
        return try await client.get("/api/source-control/github/installations", as: R.self).installations
    }

    func githubRepositories() async throws -> [GitHubRepository] {
        struct R: Decodable { var repositories: [GitHubRepository] }
        return try await client.get("/api/source-control/github/repositories", as: R.self).repositories
    }

    func githubBranches(repositoryId: String) async throws -> [String] {
        struct R: Decodable { var branches: [String] }
        return try await client.get("/api/source-control/github/repositories/\(repositoryId)/branches", as: R.self).branches
    }

    func inspectRepository(repositoryId: String) async throws -> RepoInspection {
        struct R: Decodable { var inspection: RepoInspection }
        return try await client.get("/api/source-control/github/repositories/\(repositoryId)/inspect", as: R.self).inspection
    }

    // MARK: Environment

    func envVars(projectId: String) async throws -> [EnvVar] {
        struct R: Decodable { var envVars: [EnvVar] }
        return try await client.get("/api/projects/\(projectId)/env-vars", as: R.self).envVars
    }

    func setEnvVar(projectId: String, key: String, value: String) async throws -> EnvVar {
        struct R: Decodable { var envVar: EnvVar }
        return try await client.send("PUT", "/api/projects/\(projectId)/env-vars/\(key)", body: ["value": value], as: R.self).envVar
    }

    func deleteEnvVar(projectId: String, key: String) async throws {
        let _: Ack = try await client.send("DELETE", "/api/projects/\(projectId)/env-vars/\(key)")
    }

    // MARK: MCP

    func mcpServers() async throws -> [McpServer] {
        struct R: Decodable { var servers: [McpServer] }
        return try await client.get("/api/mcp/servers", as: R.self).servers
    }

    func createMcpServer(_ draft: McpServerDraft) async throws -> McpServer {
        struct R: Decodable { var server: McpServer }
        var body: [String: Any] = ["name": draft.name, "config": mcpConfig(draft), "enabled": draft.enabled]
        if let projectId = draft.projectId { body["projectId"] = projectId }
        return try await client.send("POST", "/api/mcp/servers", body: body, as: R.self).server
    }

    func updateMcpServer(id: String, draft: McpServerDraft) async throws -> McpServer {
        struct R: Decodable { var server: McpServer }
        let body: [String: Any] = ["name": draft.name, "config": mcpConfig(draft), "enabled": draft.enabled]
        return try await client.send("PATCH", "/api/mcp/servers/\(id)", body: body, as: R.self).server
    }

    func deleteMcpServer(id: String) async throws {
        let _: Ack = try await client.send("DELETE", "/api/mcp/servers/\(id)")
    }

    private func mcpConfig(_ draft: McpServerDraft) -> [String: Any] {
        var config: [String: Any] = ["transport": draft.transport, "url": draft.url]
        switch draft.auth {
        case .keep, .none: break
        case .bearer(let token): config["headers"] = ["Authorization": "Bearer \(token)"]
        case .header(let name, let value): config["headers"] = [name: value]
        }
        return config
    }

    /// The workspace accepted this credential elsewhere, so a 401 here means the key lacks this
    /// operation's permission (personal keys can't manage webhooks or service accounts).
    private func scoped<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let error as APIError where error.status == 401 {
            throw APIError(status: 403, code: "insufficient_permissions", requestId: error.requestId)
        }
    }

    // MARK: Webhooks

    func webhooks() async throws -> [Webhook] {
        struct R: Decodable { var subscriptions: [Webhook]; var nextCursor: String? }
        var all: [Webhook] = []
        var cursor: String?
        repeat {
            let page: R = try await scoped { try await client.get("/api/webhooks", query: ["cursor": cursor]) }
            all += page.subscriptions
            cursor = page.nextCursor
        } while cursor != nil && all.count < 500
        return all
    }

    func createWebhook(url: String, projectId: String?, types: [String]) async throws -> WebhookSecret {
        struct R: Decodable { var subscription: Webhook; var secret: String? }
        var body: [String: Any] = ["url": url]
        if let projectId { body["projectId"] = projectId }
        if !types.isEmpty { body["types"] = types }
        let r: R = try await client.send("POST", "/api/webhooks", body: body)
        return WebhookSecret(webhook: r.subscription, secret: r.secret)
    }

    func updateWebhook(id: String, url: String?, types: [String]?, disabled: Bool?) async throws -> Webhook {
        struct R: Decodable { var subscription: Webhook }
        var body: [String: Any] = [:]
        if let url { body["url"] = url }
        if let types { body["types"] = types }
        if let disabled { body["disabled"] = disabled }
        return try await client.send("PATCH", "/api/webhooks/\(id)", body: body, as: R.self).subscription
    }

    func deleteWebhook(id: String) async throws {
        let _: Ack = try await client.send("DELETE", "/api/webhooks/\(id)")
    }

    func webhookDeliveries(id: String, cursor: String?) async throws -> WebhookDeliveryPage {
        struct R: Decodable { var deliveries: [WebhookDelivery]; var nextCursor: String? }
        let r: R = try await client.get("/api/webhooks/\(id)/deliveries", query: ["cursor": cursor])
        return WebhookDeliveryPage(deliveries: r.deliveries, nextCursor: r.nextCursor)
    }

    func redeliver(webhookId: String, deliveryId: String) async throws {
        let _: Ack = try await client.send("POST", "/api/webhooks/\(webhookId)/deliveries/\(deliveryId)/redeliver")
    }

    func rotateWebhookSecret(id: String) async throws -> WebhookSecret {
        struct R: Decodable { var subscription: Webhook; var secret: String? }
        let r: R = try await client.send("POST", "/api/webhooks/\(id)/rotate-secret")
        return WebhookSecret(webhook: r.subscription, secret: r.secret)
    }

    // MARK: Service accounts

    func serviceAccounts() async throws -> [ServiceAccount] {
        struct R: Decodable { var accounts: [ServiceAccount]; var nextCursor: String? }
        var all: [ServiceAccount] = []
        var cursor: String?
        repeat {
            let page: R = try await scoped { try await client.get("/api/service-accounts", query: ["cursor": cursor]) }
            all += page.accounts
            cursor = page.nextCursor
        } while cursor != nil && all.count < 500
        return all
    }

    func ownServiceAccount() async throws -> ServiceAccount {
        struct R: Decodable { var account: ServiceAccount }
        return try await client.get("/api/service-accounts/self", as: R.self).account
    }

    func createServiceAccount(_ draft: ServiceAccountDraft) async throws -> ServiceAccountSecret {
        struct R: Decodable { var account: ServiceAccount; var credential: ServiceCredential?; var key: String? }
        var body = accountBody(draft)
        if draft.projectIds == nil { body.removeValue(forKey: "projectIds") }
        let r: R = try await client.send("POST", "/api/service-accounts", body: body)
        return ServiceAccountSecret(account: r.account, credential: r.credential, key: r.key)
    }

    func updateServiceAccount(id: String, draft: ServiceAccountDraft) async throws -> ServiceAccount {
        struct R: Decodable { var account: ServiceAccount }
        return try await client.send("PATCH", "/api/service-accounts/\(id)", body: accountBody(draft), as: R.self).account
    }

    func setServiceAccountDisabled(id: String, disabled: Bool) async throws -> ServiceAccount {
        struct R: Decodable { var account: ServiceAccount }
        return try await client.send("PATCH", "/api/service-accounts/\(id)", body: ["disabled": disabled], as: R.self).account
    }

    func serviceCredentials(accountId: String) async throws -> [ServiceCredential] {
        struct R: Decodable { var credentials: [ServiceCredential] }
        return try await client.get("/api/service-accounts/\(accountId)/credentials", as: R.self).credentials
    }

    func revokeCredential(accountId: String, credentialId: String) async throws {
        let _: Ack = try await client.send("DELETE", "/api/service-accounts/\(accountId)/credentials/\(credentialId)")
    }

    func rotateServiceAccount(id: String) async throws -> ServiceAccountSecret {
        try await rotate("/api/service-accounts/\(id)/rotate")
    }

    func rotateOwnCredential() async throws -> ServiceAccountSecret {
        try await rotate("/api/service-accounts/self/rotate")
    }

    private func rotate(_ path: String) async throws -> ServiceAccountSecret {
        struct R: Decodable { var account: ServiceAccount; var credential: ServiceCredential?; var key: String? }
        let r: R = try await client.send("POST", path)
        return ServiceAccountSecret(account: r.account, credential: r.credential, key: r.key)
    }

    private func accountBody(_ draft: ServiceAccountDraft) -> [String: Any] {
        let permissions = draft.permissions.filter { !$0.value.isEmpty }.mapValues { $0.sorted() }
        return [
            "name": draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            "permissions": permissions,
            "projectIds": draft.projectIds ?? NSNull(),
        ]
    }

    // MARK: Automations

    func projectAutomations(projectId: String) async throws -> [Automation] {
        try await automations(projectId: projectId)
    }

    func createAutomation(projectId: String, draft: AutomationDraft) async throws -> AutomationCreateResult {
        struct R: Decodable { var automation: Automation; var webhookToken: String?; var webhookUrl: String? }
        let r: R = try await client.send("POST", "/api/projects/\(projectId)/automations", body: automationBody(draft, creating: true))
        return AutomationCreateResult(automation: r.automation, webhookToken: r.webhookToken, webhookUrl: r.webhookUrl)
    }

    func updateAutomation(projectId: String, id: String, draft: AutomationDraft) async throws -> Automation {
        struct R: Decodable { var automation: Automation }
        return try await client.send("PATCH", "/api/projects/\(projectId)/automations/\(id)", body: automationBody(draft, creating: false), as: R.self).automation
    }

    func deleteAutomation(projectId: String, id: String) async throws {
        let _: Ack = try await client.send("DELETE", "/api/projects/\(projectId)/automations/\(id)")
    }

    func automationStatus(projectId: String) async throws -> AutomationStatusReport {
        try await client.get("/api/projects/\(projectId)/automations/status")
    }

    private func automationBody(_ draft: AutomationDraft, creating: Bool) -> [String: Any] {
        var body: [String: Any] = [
            "name": draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            "prompt": draft.prompt,
            "enabled": draft.enabled,
            "repoFullName": draft.repoFullName ?? NSNull(),
            "modelId": draft.modelId ?? NSNull(),
        ]
        switch draft.trigger {
        case .schedule(let schedule):
            if creating { body["triggerKind"] = "schedule" }
            if schedule.mode == "interval" {
                body["schedule"] = ["mode": "interval", "intervalMs": schedule.intervalMs ?? 3_600_000]
            } else {
                body["schedule"] = ["mode": "cron", "expression": schedule.expression ?? "0 9 * * *", "timezone": schedule.timezone ?? TimeZone.current.identifier]
            }
        case .event(let kind):
            if creating { body["triggerKind"] = "webhook" }
            body["eventKind"] = kind ?? NSNull()
        }
        return body
    }

    // MARK: About

    func capabilities() async throws -> FactoryCapabilities {
        try await client.get("/api/capabilities")
    }

    func health() async throws -> ServiceHealth {
        try await client.get("/health")
    }
}
