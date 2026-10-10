import Foundation
import ObjectiveC

/// Mutable state behind the demo workspace's admin screens, attached to the `DemoService`
/// instance it belongs to so that leaving the demo discards it.
@MainActor
final class DemoWorkspaceState {
    var projects: [WorkspaceProject] = DemoWorkspaceData.projects
    var envVars: [String: [EnvVar]] = DemoWorkspaceData.envVars
    var mcpServers: [McpServer] = DemoWorkspaceData.mcpServers
    var webhooks: [Webhook] = DemoWorkspaceData.webhooks
    var deliveries: [String: [WebhookDelivery]] = DemoWorkspaceData.deliveries
    var accounts: [ServiceAccount] = DemoWorkspaceData.accounts
    var credentials: [String: [ServiceCredential]] = DemoWorkspaceData.credentials
}

nonisolated(unsafe) private var workspaceStateKey: UInt8 = 0

extension DemoService: WorkspaceAdmin {
    private var workspace: DemoWorkspaceState {
        if let state = objc_getAssociatedObject(self, &workspaceStateKey) as? DemoWorkspaceState { return state }
        let state = DemoWorkspaceState()
        objc_setAssociatedObject(self, &workspaceStateKey, state, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return state
    }

    private func pause() async { try? await Task.sleep(for: .milliseconds(140)) }

    private static func now(_ offset: TimeInterval = 0) -> String { ISO8601.string(.now.addingTimeInterval(offset)) }

    private func notFound() -> APIError { APIError(status: 404, code: "not_found") }

    // MARK: Projects

    func workspaceProjects() async throws -> [WorkspaceProject] {
        await pause()
        return workspace.projects
    }

    func createProject(_ project: NewProject) async throws -> WorkspaceProject {
        await pause()
        let code = String(project.name.filter(\.isLetter).prefix(3)).uppercased()
        let created = WorkspaceProject(
            id: "prj_\(UUID().uuidString.prefix(8).lowercased())", name: project.name, taskCode: code,
            repos: [ProjectRepo(repoFullName: project.repositoryFullName, repositoryId: project.repositoryId, branch: project.baseBranch)],
            githubInstallationId: project.sourceControlConnectionId, defaultBranch: project.baseBranch, previewPort: project.previewPort ?? 3000,
            setupScript: project.setupScript, runScript: project.runScript, archiveScript: project.archiveScript,
            reasoningEffort: "medium", agentSpeed: "standard", framework: project.framework, createdAt: Self.now(), updatedAt: Self.now()
        )
        workspace.projects.insert(created, at: 0)
        projectsStore.append(Project(id: created.id, name: created.name, taskCode: created.taskCode, repos: [RepoRef(fullName: project.repositoryFullName, defaultBranch: project.baseBranch)], defaultBranch: project.baseBranch, framework: project.framework))
        return created
    }

    func updateProject(id: String, draft: ProjectDraft) async throws -> WorkspaceProject {
        await pause()
        guard let index = workspace.projects.firstIndex(where: { $0.id == id }) else { throw notFound() }
        func text(_ value: String) -> String? {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        var project = workspace.projects[index]
        project.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        project.description = text(draft.description)
        project.defaultBranch = text(draft.defaultBranch)
        project.previewPort = Int(draft.previewPort) ?? project.previewPort
        project.setupScript = text(draft.setupScript)
        project.runScript = text(draft.runScript)
        project.archiveScript = text(draft.archiveScript)
        project.instructions = text(draft.instructions)
        project.defaultModel = draft.defaultModel
        project.reasoningEffort = draft.reasoningEffort
        project.agentSpeed = draft.agentSpeed
        project.updatedAt = Self.now()
        workspace.projects[index] = project
        if let i = projectsStore.firstIndex(where: { $0.id == id }) {
            projectsStore[i].name = project.name
            projectsStore[i].description = project.description
            projectsStore[i].defaultBranch = project.defaultBranch
            projectsStore[i].defaultModel = project.defaultModel
            projectsStore[i].reasoningEffort = project.reasoningEffort
        }
        return project
    }

    func deleteProject(id: String) async throws {
        await pause()
        workspace.projects.removeAll { $0.id == id }
        workspace.envVars[id] = nil
        projectsStore.removeAll { $0.id == id }
    }

    func projectRepositories(projectId: String) async throws -> [ProjectRepo] {
        await pause()
        guard let project = workspace.projects.first(where: { $0.id == projectId }) else { throw notFound() }
        return project.repos ?? []
    }

    func assignRepositories(projectId: String, repositories: [RepoAssignment]) async throws -> WorkspaceProject {
        await pause()
        guard let index = workspace.projects.firstIndex(where: { $0.id == projectId }) else { throw notFound() }
        workspace.projects[index].repos = repositories.map { ProjectRepo(repoFullName: $0.repoFullName, repositoryId: $0.repositoryId, branch: $0.baseBranch) }
        workspace.projects[index].updatedAt = Self.now()
        return workspace.projects[index]
    }

    // MARK: GitHub

    func githubInstallations() async throws -> [GitHubInstallation] {
        await pause()
        return DemoWorkspaceData.installations
    }

    func githubRepositories() async throws -> [GitHubRepository] {
        await pause()
        return DemoWorkspaceData.installations.flatMap { $0.repositories ?? [] }
    }

    func githubBranches(repositoryId: String) async throws -> [String] {
        await pause()
        let base = DemoWorkspaceData.installations.flatMap { $0.repositories ?? [] }.first { $0.id == repositoryId }?.defaultBranch ?? "main"
        return [base, "develop", "release/2026.10", "hoplite/ratelimit"]
    }

    func inspectRepository(repositoryId: String) async throws -> RepoInspection {
        await pause()
        let repo = DemoWorkspaceData.installations.flatMap { $0.repositories ?? [] }.first { $0.id == repositoryId }
        let go = repo?.language == "Go"
        if repo?.language == "Swift" || repo?.language == "HCL" || repo?.language == "Shell" {
            return RepoInspection(framework: nil, settings: .init(path: nil, previewPort: nil, invalid: false, scripts: nil))
        }
        return RepoInspection(framework: repo?.framework, settings: .init(
            path: ".hoplite/settings.json", previewPort: go ? 8080 : 3000, invalid: false,
            scripts: .init(
                setup: RepoScript(enabled: true, command: go ? "go mod download" : "pnpm install --frozen-lockfile"),
                run: RepoScript(enabled: true, command: go ? "go run ./cmd/server" : "pnpm dev"),
                archive: RepoScript(enabled: false, command: nil)
            )
        ))
    }

    // MARK: Environment

    func envVars(projectId: String) async throws -> [EnvVar] {
        await pause()
        return workspace.envVars[projectId] ?? []
    }

    func setEnvVar(projectId: String, key: String, value: String) async throws -> EnvVar {
        await pause()
        let variable = EnvVar(key: key, updatedAt: Self.now())
        var items = workspace.envVars[projectId] ?? []
        if let index = items.firstIndex(where: { $0.key == key }) { items[index] = variable } else { items.append(variable) }
        workspace.envVars[projectId] = items.sorted { $0.key < $1.key }
        return variable
    }

    func deleteEnvVar(projectId: String, key: String) async throws {
        await pause()
        workspace.envVars[projectId]?.removeAll { $0.key == key }
    }

    // MARK: MCP

    func mcpServers() async throws -> [McpServer] {
        await pause()
        return workspace.mcpServers
    }

    private func mcpServer(id: String, draft: McpServerDraft, existing: McpServer?) -> McpServer {
        var config = existing?.config ?? [:]
        config["transport"] = .string(draft.transport)
        config["url"] = .string(draft.url)
        switch draft.auth {
        case .keep, .none: break
        case .bearer: config["headers"] = .object(["Authorization": .string("••••••••")])
        case .header(let name, _): config["headers"] = .object([name: .string("••••••••")])
        }
        return McpServer(id: id, projectId: draft.projectId ?? existing?.projectId, name: draft.name, config: config, enabled: draft.enabled, createdAt: existing?.createdAt ?? Self.now(), updatedAt: Self.now())
    }

    func createMcpServer(_ draft: McpServerDraft) async throws -> McpServer {
        await pause()
        let server = mcpServer(id: "mcp_\(UUID().uuidString.prefix(8).lowercased())", draft: draft, existing: nil)
        workspace.mcpServers.append(server)
        return server
    }

    func updateMcpServer(id: String, draft: McpServerDraft) async throws -> McpServer {
        await pause()
        guard let index = workspace.mcpServers.firstIndex(where: { $0.id == id }) else { throw notFound() }
        let server = mcpServer(id: id, draft: draft, existing: workspace.mcpServers[index])
        workspace.mcpServers[index] = server
        return server
    }

    func deleteMcpServer(id: String) async throws {
        await pause()
        workspace.mcpServers.removeAll { $0.id == id }
    }

    // MARK: Webhooks

    func webhooks() async throws -> [Webhook] {
        await pause()
        return workspace.webhooks
    }

    func createWebhook(url: String, projectId: String?, types: [String]) async throws -> WebhookSecret {
        await pause()
        let webhook = Webhook(id: "whs_\(UUID().uuidString.prefix(8).lowercased())", orgId: "org_acme", projectId: projectId, url: url, types: types, disabled: false, createdAt: Self.now(), updatedAt: Self.now())
        workspace.webhooks.insert(webhook, at: 0)
        return WebhookSecret(webhook: webhook, secret: DemoWorkspaceData.secret(prefix: "whsec_"))
    }

    func updateWebhook(id: String, url: String?, types: [String]?, disabled: Bool?) async throws -> Webhook {
        await pause()
        guard let index = workspace.webhooks.firstIndex(where: { $0.id == id }) else { throw notFound() }
        if let url { workspace.webhooks[index].url = url }
        if let types { workspace.webhooks[index].types = types }
        if let disabled { workspace.webhooks[index].disabled = disabled }
        workspace.webhooks[index].updatedAt = Self.now()
        return workspace.webhooks[index]
    }

    func deleteWebhook(id: String) async throws {
        await pause()
        workspace.webhooks.removeAll { $0.id == id }
        workspace.deliveries[id] = nil
    }

    func webhookDeliveries(id: String, cursor: String?) async throws -> WebhookDeliveryPage {
        await pause()
        return WebhookDeliveryPage(deliveries: workspace.deliveries[id] ?? [], nextCursor: nil)
    }

    func redeliver(webhookId: String, deliveryId: String) async throws {
        await pause()
        guard let source = workspace.deliveries[webhookId]?.first(where: { $0.id == deliveryId }) else { throw notFound() }
        let again = WebhookDelivery(id: "dlv_\(UUID().uuidString.prefix(8).lowercased())", eventId: source.eventId, state: "delivered", attempts: 1, lastStatus: 200, createdAt: Self.now(), finishedAt: Self.now(1))
        workspace.deliveries[webhookId, default: []].insert(again, at: 0)
    }

    func rotateWebhookSecret(id: String) async throws -> WebhookSecret {
        await pause()
        guard let webhook = workspace.webhooks.first(where: { $0.id == id }) else { throw notFound() }
        return WebhookSecret(webhook: webhook, secret: DemoWorkspaceData.secret(prefix: "whsec_"))
    }

    // MARK: Service accounts

    func serviceAccounts() async throws -> [ServiceAccount] {
        await pause()
        return workspace.accounts
    }

    func ownServiceAccount() async throws -> ServiceAccount {
        await pause()
        return DemoWorkspaceData.ownAccount
    }

    func createServiceAccount(_ draft: ServiceAccountDraft) async throws -> ServiceAccountSecret {
        await pause()
        let account = ServiceAccount(id: "sa_\(UUID().uuidString.prefix(8).lowercased())", orgId: "org_acme", name: draft.name, permissions: draft.permissions.filter { !$0.value.isEmpty }.mapValues { $0.sorted() }, projectIds: draft.projectIds, disabled: false, createdAt: Self.now(), updatedAt: Self.now())
        let credential = ServiceCredential(id: "cred_\(UUID().uuidString.prefix(8).lowercased())", accountId: account.id, expiresAt: Self.now(90 * 86_400), revoked: false, createdAt: Self.now())
        workspace.accounts.insert(account, at: 0)
        workspace.credentials[account.id] = [credential]
        return ServiceAccountSecret(account: account, credential: credential, key: DemoWorkspaceData.secret(prefix: "hop_"))
    }

    func updateServiceAccount(id: String, draft: ServiceAccountDraft) async throws -> ServiceAccount {
        await pause()
        guard let index = workspace.accounts.firstIndex(where: { $0.id == id }) else { throw notFound() }
        workspace.accounts[index].name = draft.name
        workspace.accounts[index].permissions = draft.permissions.filter { !$0.value.isEmpty }.mapValues { $0.sorted() }
        workspace.accounts[index].projectIds = draft.projectIds
        workspace.accounts[index].updatedAt = Self.now()
        return workspace.accounts[index]
    }

    func setServiceAccountDisabled(id: String, disabled: Bool) async throws -> ServiceAccount {
        await pause()
        guard let index = workspace.accounts.firstIndex(where: { $0.id == id }) else { throw notFound() }
        workspace.accounts[index].disabled = disabled
        return workspace.accounts[index]
    }

    func serviceCredentials(accountId: String) async throws -> [ServiceCredential] {
        await pause()
        return workspace.credentials[accountId] ?? []
    }

    func revokeCredential(accountId: String, credentialId: String) async throws {
        await pause()
        guard let index = workspace.credentials[accountId]?.firstIndex(where: { $0.id == credentialId }) else { throw notFound() }
        workspace.credentials[accountId]?[index].revoked = true
    }

    func rotateServiceAccount(id: String) async throws -> ServiceAccountSecret {
        await pause()
        guard let account = workspace.accounts.first(where: { $0.id == id }) else { throw notFound() }
        let credential = ServiceCredential(id: "cred_\(UUID().uuidString.prefix(8).lowercased())", accountId: id, expiresAt: Self.now(90 * 86_400), revoked: false, createdAt: Self.now())
        workspace.credentials[id, default: []].insert(credential, at: 0)
        return ServiceAccountSecret(account: account, credential: credential, key: DemoWorkspaceData.secret(prefix: "hop_"))
    }

    func rotateOwnCredential() async throws -> ServiceAccountSecret {
        await pause()
        let credential = ServiceCredential(id: "cred_\(UUID().uuidString.prefix(8).lowercased())", accountId: DemoWorkspaceData.ownAccount.id, expiresAt: Self.now(90 * 86_400), revoked: false, createdAt: Self.now())
        return ServiceAccountSecret(account: DemoWorkspaceData.ownAccount, credential: credential, key: DemoWorkspaceData.secret(prefix: "hop_"))
    }

    // MARK: Automations

    func projectAutomations(projectId: String) async throws -> [Automation] {
        try await automations(projectId: projectId)
    }

    private func automation(id: String, projectId: String, draft: AutomationDraft, existing: Automation?) -> Automation {
        var automation = Automation(
            id: id, projectId: projectId, name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines), enabled: draft.enabled,
            triggerKind: "webhook", prompt: draft.prompt, title: draft.name, repoFullName: draft.repoFullName, modelId: draft.modelId,
            lastRunAt: existing?.lastRunAt
        )
        switch draft.trigger {
        case .schedule(let schedule):
            automation.triggerKind = "schedule"
            automation.schedule = schedule
            automation.nextRunAt = Self.now(3 * 3600)
        case .event(let kind):
            automation.eventKind = kind
        }
        return automation
    }

    func createAutomation(projectId: String, draft: AutomationDraft) async throws -> AutomationCreateResult {
        await pause()
        let created = automation(id: "aut_\(UUID().uuidString.prefix(8).lowercased())", projectId: projectId, draft: draft, existing: nil)
        automationsStore.append(created)
        var result = AutomationCreateResult(automation: created)
        if case .event(nil) = draft.trigger {
            result.webhookToken = DemoWorkspaceData.secret(prefix: "hwa2_")
            result.webhookUrl = "https://api.hoplite.sh/api/automations/webhooks"
        }
        return result
    }

    func updateAutomation(projectId: String, id: String, draft: AutomationDraft) async throws -> Automation {
        await pause()
        let existing = try await projectAutomations(projectId: projectId).first { $0.id == id }
        let updated = automation(id: id, projectId: projectId, draft: draft, existing: existing)
        if let index = automationsStore.firstIndex(where: { $0.id == id }) {
            var merged = updated
            merged.enabled = automationsStore[index].enabled
            automationsStore[index] = merged
            return merged
        }
        return updated
    }

    func deleteAutomation(projectId: String, id: String) async throws {
        await pause()
        automationsStore.removeAll { $0.id == id }
    }

    func automationStatus(projectId: String) async throws -> AutomationStatusReport {
        await pause()
        let items = try await projectAutomations(projectId: projectId)
        let statuses = items.enumerated().map { index, automation -> AutomationStatus in
            guard automation.lastRunAt != nil else {
                return AutomationStatus(automationId: automation.id, runs30d: 0, succeeded30d: 0, failed30d: 0)
            }
            let runs = automation.triggerKind == "schedule" ? 30 - index * 6 : 11 + index * 4
            let failed = index == 0 ? 2 : 1
            return AutomationStatus(
                automationId: automation.id, lastStatus: "thread_created", lastRunStatus: "completed",
                lastExecutionAt: automation.lastRunAt, runs30d: runs, succeeded30d: runs - failed, failed30d: failed
            )
        }
        let totals = AutomationStatusTotals(runs30d: statuses.reduce(0) { $0 + ($1.runs30d ?? 0) }, succeeded30d: statuses.reduce(0) { $0 + ($1.succeeded30d ?? 0) })
        return AutomationStatusReport(statuses: statuses, totals: totals)
    }

    // MARK: About

    func capabilities() async throws -> FactoryCapabilities {
        await pause()
        return DemoWorkspaceData.capabilities
    }

    func health() async throws -> ServiceHealth {
        await pause()
        return ServiceHealth(ok: true, service: "hoplite-api", version: "2026.10.8")
    }
}

// MARK: Seed data

enum DemoWorkspaceData {
    nonisolated private static func ago(_ minutes: Double) -> String { ISO8601.string(.now.addingTimeInterval(-minutes * 60)) }

    static func secret(prefix: String) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        return prefix + String((0..<40).map { _ in alphabet.randomElement()! })
    }

    static let projects: [WorkspaceProject] = [
        WorkspaceProject(
            id: "prj_storefront", name: "storefront", description: "Next.js commerce frontend", taskCode: "WEB",
            repos: [ProjectRepo(repoFullName: "acme/storefront", repositoryId: "repo_storefront", branch: "main")],
            githubInstallationId: "ghi_acme", defaultBranch: "main", previewPort: 3000,
            setupScript: "pnpm install --frozen-lockfile", runScript: "pnpm dev", archiveScript: nil,
            instructions: "Use pnpm. Run `pnpm typecheck` and `pnpm test` before committing. Follow the component conventions in CONTRIBUTING.md and never touch generated files under `src/gen`.",
            defaultModel: "claude-fable-5", reasoningEffort: "high", agentSpeed: "standard", prReviewAutofixDefault: true,
            sandboxSpec: SandboxSpec(defaultCpu: 4, defaultMemoryGiB: 8, maxCpu: 8, maxDiskGiB: 64, maxMemoryGiB: 16, runtimeProfile: nil),
            framework: "nextjs", createdAt: ago(60 * 24 * 120), updatedAt: ago(60 * 30)
        ),
        WorkspaceProject(
            id: "prj_billing", name: "billing-service", description: "Go service for plans, invoices and metering", taskCode: "BIL",
            repos: [ProjectRepo(repoFullName: "acme/billing", repositoryId: "repo_billing", branch: "main")],
            githubInstallationId: "ghi_acme", defaultBranch: "main", previewPort: 8080,
            setupScript: "go mod download", runScript: "go run ./cmd/billing", archiveScript: "docker compose down -v",
            instructions: "Migrations must be reversible. Run `go test ./...` and `golangci-lint run` before opening a PR.",
            defaultModel: "gpt-6-sol", reasoningEffort: "medium", agentSpeed: "standard", prReviewAutofixDefault: false,
            sandboxSpec: SandboxSpec(defaultCpu: 4, defaultMemoryGiB: 8, maxCpu: 8, maxDiskGiB: 64, maxMemoryGiB: 16, runtimeProfile: "docker-compose"),
            framework: "go", createdAt: ago(60 * 24 * 90), updatedAt: ago(60 * 52)
        ),
        WorkspaceProject(
            id: "prj_ui", name: "design-system", description: "Shared React components", taskCode: "UI",
            repos: [
                ProjectRepo(repoFullName: "acme/ui", repositoryId: "repo_ui", branch: "main"),
                ProjectRepo(repoFullName: "acme/docs", repositoryId: "repo_docs", branch: "main"),
            ],
            githubInstallationId: "ghi_acme", defaultBranch: "main", previewPort: 6006,
            setupScript: "pnpm install", runScript: "pnpm storybook", archiveScript: nil, instructions: nil,
            defaultModel: "claude-sonnet-5", reasoningEffort: "low", agentSpeed: "fast", prReviewAutofixDefault: nil,
            sandboxSpec: nil, framework: "react", createdAt: ago(60 * 24 * 60), updatedAt: ago(60 * 24 * 3)
        ),
    ]

    static let installations: [GitHubInstallation] = {
        func repo(_ name: String, _ owner: String, language: String, framework: String? = nil, priv: Bool = true, branch: String = "main") -> GitHubRepository {
            GitHubRepository(id: "repo_\(name)", installationId: "ghi_\(owner)", repositoryId: abs(name.hashValue % 900_000) + 100_000, fullName: "\(owner)/\(name)", cloneUrl: "https://github.com/\(owner)/\(name).git", language: language, framework: framework, defaultBranch: branch, private: priv)
        }
        return [
            GitHubInstallation(id: "ghi_acme", installationId: 48_211_930, accountLogin: "acme", accountType: "Organization", managementUrl: "https://github.com/organizations/acme/settings/installations/48211930", repositories: [
                repo("storefront", "acme", language: "TypeScript", framework: "nextjs"),
                repo("billing", "acme", language: "Go"),
                repo("ui", "acme", language: "TypeScript", framework: "react"),
                repo("docs", "acme", language: "MDX", framework: "docusaurus", priv: false),
                repo("mobile-app", "acme", language: "Swift"),
                repo("data-pipeline", "acme", language: "Python", branch: "trunk"),
                repo("internal-tools", "acme", language: "TypeScript", framework: "vite"),
                repo("infra", "acme", language: "HCL"),
            ]),
            GitHubInstallation(id: "ghi_camden-rose", installationId: 51_904_112, accountLogin: "camden-rose", accountType: "User", managementUrl: nil, repositories: [
                repo("dotfiles", "camden-rose", language: "Shell", priv: false),
                repo("side-project", "camden-rose", language: "Rust"),
            ]),
        ]
    }()

    static let envVars: [String: [EnvVar]] = [
        "prj_storefront": [
            EnvVar(key: "DATABASE_URL", updatedAt: ago(60 * 24 * 40)),
            EnvVar(key: "NEXT_PUBLIC_API_BASE", updatedAt: ago(60 * 24 * 12)),
            EnvVar(key: "REDIS_URL", updatedAt: ago(60 * 5)),
            EnvVar(key: "SENTRY_AUTH_TOKEN", updatedAt: ago(60 * 24 * 21)),
            EnvVar(key: "STRIPE_SECRET_KEY", updatedAt: ago(60 * 24 * 8)),
        ],
        "prj_billing": [
            EnvVar(key: "DATABASE_URL", updatedAt: ago(60 * 24 * 30)),
            EnvVar(key: "KAFKA_BROKERS", updatedAt: ago(60 * 24 * 30)),
            EnvVar(key: "STRIPE_WEBHOOK_SECRET", updatedAt: ago(60 * 24 * 2)),
        ],
        "prj_ui": [EnvVar(key: "CHROMATIC_PROJECT_TOKEN", updatedAt: ago(60 * 24 * 45))],
    ]

    static let mcpServers: [McpServer] = [
        McpServer(id: "mcp_linear", projectId: nil, name: "Linear", config: ["transport": .string("http"), "url": .string("https://mcp.linear.app/mcp"), "headers": .object(["Authorization": .string("••••••••")])], enabled: true, createdAt: ago(60 * 24 * 50), updatedAt: ago(60 * 24 * 9)),
        McpServer(id: "mcp_sentry", projectId: "prj_storefront", name: "Sentry", config: ["transport": .string("http"), "url": .string("https://mcp.sentry.dev/mcp"), "needsAuth": .bool(true), "auth": .object(["kind": .string("oauth2"), "grantType": .string("authorization_code"), "status": .string("needs_reauth")])], enabled: true, createdAt: ago(60 * 24 * 30), updatedAt: ago(60 * 24 * 2)),
        McpServer(id: "mcp_docs", projectId: nil, name: "docs-search", config: ["transport": .string("sse"), "url": .string("https://docs-mcp.acme.dev/sse")], enabled: true, createdAt: ago(60 * 24 * 20), updatedAt: ago(60 * 24 * 20)),
        McpServer(id: "mcp_figma", projectId: "prj_ui", name: "Figma", config: ["transport": .string("http"), "url": .string("https://mcp.figma.com/mcp"), "headers": .object(["X-Figma-Token": .string("••••••••")])], enabled: false, createdAt: ago(60 * 24 * 14), updatedAt: ago(60 * 24 * 6)),
    ]

    static let webhooks: [Webhook] = [
        Webhook(id: "whs_ci", orgId: "org_acme", projectId: "prj_storefront", url: "https://ci.acme.dev/hooks/hoplite", types: ["run.completed", "run.failed"], disabled: false, createdAt: ago(60 * 24 * 35), updatedAt: ago(60 * 24 * 4)),
        Webhook(id: "whs_approvals", orgId: "org_acme", projectId: nil, url: "https://hooks.acme.dev/hoplite/approvals", types: ["approval.requested", "approval.resolved", "pull_request.updated"], disabled: false, createdAt: ago(60 * 24 * 18), updatedAt: ago(60 * 24 * 18)),
        Webhook(id: "whs_staging", orgId: "org_acme", projectId: "prj_billing", url: "https://staging.acme.dev/webhooks/hoplite", types: [], disabled: true, createdAt: ago(60 * 24 * 60), updatedAt: ago(60 * 24 * 10)),
    ]

    static let deliveries: [String: [WebhookDelivery]] = {
        func delivery(_ n: Int, _ id: String, minutes: Double, state: String, status: Int?, error: String? = nil, attempts: Int = 1) -> WebhookDelivery {
            WebhookDelivery(id: "dlv_\(id)_\(n)", eventId: "evt_\(String(format: "%06x", 0xa4c0de + n * 7919))", state: state, attempts: attempts, lastStatus: status, lastError: error, createdAt: ago(minutes), finishedAt: state == "pending" ? nil : ago(minutes - 0.1))
        }
        return [
            "whs_ci": [
                delivery(1, "ci", minutes: 4, state: "delivered", status: 200),
                delivery(2, "ci", minutes: 38, state: "delivered", status: 200),
                delivery(3, "ci", minutes: 95, state: "failed", status: 502, error: "Bad gateway", attempts: 6),
                delivery(4, "ci", minutes: 210, state: "delivered", status: 204, attempts: 2),
                delivery(5, "ci", minutes: 60 * 20, state: "delivered", status: 200),
                delivery(6, "ci", minutes: 60 * 26, state: "pending", status: nil, attempts: 0),
            ],
            "whs_approvals": [
                delivery(1, "ap", minutes: 12, state: "delivered", status: 200),
                delivery(2, "ap", minutes: 61, state: "delivered", status: 200),
                delivery(3, "ap", minutes: 300, state: "failed", status: nil, error: "Request timed out after 10s", attempts: 4),
            ],
            "whs_staging": [],
        ]
    }()

    static let accounts: [ServiceAccount] = [
        ServiceAccount(id: "sa_deploy", orgId: "org_acme", name: "ci-deploy-bot", permissions: ["thread": ["create", "read", "stop"], "project": ["read"], "repo": ["read"]], projectIds: ["prj_storefront"], disabled: false, createdAt: ago(60 * 24 * 70), updatedAt: ago(60 * 24 * 11)),
        ServiceAccount(id: "sa_release", orgId: "org_acme", name: "release-automation", permissions: ["thread": ["read"], "automation": ["read", "run"], "webhook": ["read"]], projectIds: nil, disabled: false, createdAt: ago(60 * 24 * 40), updatedAt: ago(60 * 24 * 40)),
        ServiceAccount(id: "sa_usage", orgId: "org_acme", name: "usage-exporter", permissions: ["usage": ["read"]], projectIds: nil, disabled: true, createdAt: ago(60 * 24 * 100), updatedAt: ago(60 * 24 * 26)),
    ]

    static let credentials: [String: [ServiceCredential]] = [
        "sa_deploy": [
            ServiceCredential(id: "cred_deploy_2", accountId: "sa_deploy", expiresAt: ago(-60 * 24 * 79), revoked: false, createdAt: ago(60 * 24 * 11)),
            ServiceCredential(id: "cred_deploy_1", accountId: "sa_deploy", expiresAt: ago(-60 * 24 * 1), revoked: false, createdAt: ago(60 * 24 * 69)),
        ],
        "sa_release": [ServiceCredential(id: "cred_release_1", accountId: "sa_release", expiresAt: ago(-60 * 24 * 50), revoked: false, createdAt: ago(60 * 24 * 40))],
        "sa_usage": [
            ServiceCredential(id: "cred_usage_1", accountId: "sa_usage", expiresAt: ago(-60 * 24 * 5), revoked: true, createdAt: ago(60 * 24 * 100)),
        ],
    ]

    static let ownAccount = ServiceAccount(id: "sa_ios", orgId: "org_acme", name: "hoplite-ios", permissions: ["thread": ["create", "read", "update", "stop", "retry"], "project": ["read", "update"], "usage": ["read"]], projectIds: nil, disabled: false, createdAt: ago(60 * 24 * 14), updatedAt: ago(60 * 24 * 14))

    static let capabilities: FactoryCapabilities = {
        let all: [String: [String]] = [
            "project": ["create", "read", "update", "delete"],
            "thread": ["create", "read", "update", "delete", "stop", "retry"],
            "repo": ["read", "update"],
            "mcpServer": ["create", "read", "update", "delete"],
            "modelKey": ["read"],
            "usage": ["read"],
            "webhook": ["create", "read", "update", "delete"],
            "automation": ["create", "read", "update", "delete", "run"],
        ]
        func op(_ id: String, _ method: String, _ path: String, _ permission: String?) -> FactoryOperation {
            FactoryOperation(operationId: id, method: method, path: path, permission: permission, permissions: permission.map { [$0] } ?? [])
        }
        return FactoryCapabilities(
            principalId: "user_demo", orgId: "org_acme", projectIds: nil, permissions: all,
            operations: [
                op("listProjects", "GET", "/api/projects", "project:read"), op("createProject", "POST", "/api/projects", "project:create"),
                op("getProject", "GET", "/api/projects/{id}", "project:read"), op("updateProject", "PATCH", "/api/projects/{id}", "project:update"),
                op("deleteProject", "DELETE", "/api/projects/{id}", "project:delete"), op("listThreads", "GET", "/api/threads", "thread:read"),
                op("createThread", "POST", "/api/threads", "thread:create"), op("listMcpServers", "GET", "/api/mcp/servers", "mcpServer:read"),
                op("createMcpServer", "POST", "/api/mcp/servers", "mcpServer:create"), op("listWebhooks", "GET", "/api/webhooks", "webhook:read"),
                op("createWebhook", "POST", "/api/webhooks", "webhook:create"), op("listAutomations", "GET", "/api/projects/{id}/automations", "automation:read"),
                op("createAutomation", "POST", "/api/projects/{id}/automations", "automation:create"), op("runAutomation", "POST", "/api/projects/{id}/automations/{automationId}/run", "automation:run"),
                op("listProjectEnvironment", "GET", "/api/projects/{id}/env-vars", "project:read"), op("setProjectEnvironment", "PUT", "/api/projects/{id}/env-vars/{key}", "project:update"),
                op("getOrganizationUsage", "GET", "/api/usage", "usage:read"), op("getFactoryCapabilities", "GET", "/api/capabilities", nil),
            ],
            availability: ["cloudSandboxes": true, "automations": true, "webhooks": true, "mcpServers": true, "previews": true, "bringYourOwnKeys": false],
            limits: FactoryLimits(eventRetentionDays: 7, idempotencyRetentionDays: 7, credentialLifetimeDays: 90, credentialOverlapHours: 24, attachmentMaxBytes: 26_214_400)
        )
    }()
}
