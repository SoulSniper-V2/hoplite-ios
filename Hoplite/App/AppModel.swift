import Observation
import SwiftUI

/// Holds the OAuth tokens and refreshes them once, even when many requests race.
actor CredentialBox {
    private var stored: StoredCredential
    private var refreshing: Task<OAuthTokens, Error>?

    init(_ stored: StoredCredential) { self.stored = stored }

    func current() async throws -> Credential {
        switch stored {
        case .apiKey(let key):
            return .apiKey(key)
        case .oauth(let tokens) where !tokens.isExpired:
            return .oauth(accessToken: tokens.accessToken)
        case .oauth(let tokens):
            if refreshing == nil { refreshing = Task { try await HopliteOAuth.refresh(tokens) } }
            defer { refreshing = nil }
            let next = try await refreshing!.value
            stored = .oauth(next)
            stored.save()
            return .oauth(accessToken: next.accessToken)
        }
    }
}

@Observable
final class AppModel {
    enum Phase: Equatable { case launching, signedOut, signedIn }

    private(set) var phase: Phase = .launching
    private(set) var service: (any HopliteService)?
    private(set) var credentialLabel = ""

    var projects: [Project] = []
    var catalog: ModelCatalog?
    var threads: [AgentThread] = []
    var statusCounts: [String: Int] = [:]
    var archived: [AgentThread] = []
    var pendingApprovals: [Approval] = []
    var selectedProjectId: String? {
        didSet { UserDefaults.standard.set(selectedProjectId, forKey: "selectedProjectId"); Task { await refreshThreads() } }
    }

    var isLoading = false
    var lastError: String?
    var openThreadId: String?
    var composingNewThread = false

    private let liveActivities = LiveActivityController()
    private var eventsTask: Task<Void, Never>?
    private var refreshDebounce: Task<Void, Never>?

    var isDemo: Bool { service?.isDemo == true }

    // MARK: Session

    func bootstrap() {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "UITestDemo") { enterDemo(); return }
        if UserDefaults.standard.bool(forKey: "UITestSignedOut") { phase = .signedOut; return }
        if let key = ProcessInfo.processInfo.environment["HOPLITE_API_KEY"], !key.isEmpty {
            connect(.apiKey(key))
            return
        }
        #endif
        if let stored = StoredCredential.load() {
            connect(stored)
        } else if UserDefaults.standard.bool(forKey: "demoMode") {
            enterDemo()
        } else {
            phase = .signedOut
        }
    }

    func enterDemo() {
        UserDefaults.standard.set(true, forKey: "demoMode")
        credentialLabel = "Demo workspace · Acme"
        activate(DemoService())
    }

    func signIn(apiKey: String) async throws {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let service = LiveService(client: HopliteClient { .apiKey(key) })
        _ = try await service.projects()
        let stored = StoredCredential.apiKey(key)
        stored.save()
        connect(stored)
    }

    func signInWithHoplite() async throws {
        let tokens = try await HopliteOAuth().signIn()
        let stored = StoredCredential.oauth(tokens)
        let box = CredentialBox(stored)
        let service = LiveService(client: HopliteClient { try await box.current() })
        _ = try await service.projects()
        stored.save()
        connect(stored)
    }

    private func connect(_ stored: StoredCredential) {
        UserDefaults.standard.set(false, forKey: "demoMode")
        credentialLabel = stored.label
        let box = CredentialBox(stored)
        activate(LiveService(client: HopliteClient { try await box.current() }))
    }

    private func activate(_ service: any HopliteService) {
        self.service = service
        ApprovalBridge.handler = { [weak self] threadId, approvalId, approved in
            guard let self, let service = self.service else { return }
            try? await service.resolveApproval(threadId: threadId, approvalId: approvalId, approved: approved, reason: nil)
            self.pendingApprovals.removeAll { $0.id == approvalId }
            await self.refreshThreads()
        }
        selectedProjectId = service.isDemo ? nil : UserDefaults.standard.string(forKey: "selectedProjectId")
        withAnimation(.smooth) { phase = .signedIn }
        Task { await loadEverything() }
        startEvents()
    }

    func signOut() {
        eventsTask?.cancel()
        liveActivities.endAll()
        ApprovalBridge.handler = nil
        StoredCredential.clear()
        UserDefaults.standard.set(false, forKey: "demoMode")
        service = nil
        projects = []; threads = []; archived = []; pendingApprovals = []; catalog = nil
        withAnimation(.smooth) { phase = .signedOut }
    }

    // MARK: Loading

    func loadEverything() async {
        guard let service else { return }
        isLoading = true
        defer { isLoading = false }
        async let projects = service.projects()
        async let catalog = try? service.models()
        do {
            self.projects = try await projects
            self.catalog = await catalog
            if let selected = selectedProjectId, !self.projects.contains(where: { $0.id == selected }) { selectedProjectId = nil }
            await refreshThreads()
        } catch {
            handle(error)
        }
    }

    func refreshThreads() async {
        guard let service else { return }
        do {
            let page = try await service.threads(projectId: selectedProjectId, archived: false, query: nil)
            withAnimation(.snappy) {
                threads = page.threads
                statusCounts = page.statusCounts
            }
            lastError = nil
            await refreshApprovals()
        } catch {
            handle(error)
        }
    }

    func loadArchived() async {
        guard let service else { return }
        archived = (try? await service.threads(projectId: selectedProjectId, archived: true, query: nil).threads) ?? []
    }

    func search(_ query: String) async -> [AgentThread] {
        guard let service, !query.isEmpty else { return [] }
        async let active = service.threads(projectId: selectedProjectId, archived: false, query: query)
        async let old = service.threads(projectId: selectedProjectId, archived: true, query: query)
        return ((try? await active.threads) ?? []) + ((try? await old.threads) ?? [])
    }

    func refreshApprovals() async {
        guard let service else { return }
        let blocked = threads.filter { $0.status == .blocked || $0.runStatus == .waiting }
        var collected: [Approval] = []
        await withTaskGroup(of: [Approval].self) { group in
            for thread in blocked { group.addTask { (try? await service.approvals(threadId: thread.id)) ?? [] } }
            for await approvals in group { collected += approvals }
        }
        withAnimation(.snappy) { pendingApprovals = collected.filter(\.actionable).sorted { $0.createdAt > $1.createdAt } }
        liveActivities.sync(threads: threads, approvals: pendingApprovals, projects: projects, workspace: isDemo ? "Acme" : "Hoplite")
    }

    private func handle(_ error: Error) {
        if error is CancellationError { return }
        if let api = error as? APIError, api.isAuthFailure, !isDemo {
            lastError = api.localizedDescription
            signOut()
            return
        }
        lastError = error.localizedDescription
    }

    // MARK: Live updates

    private func startEvents() {
        eventsTask?.cancel()
        guard let service else { return }
        eventsTask = Task { [weak self] in
            for await frame in service.events(projectId: nil, threadId: nil) {
                guard let self else { return }
                if case .event(let event) = frame { self.apply(event) }
            }
        }
    }

    private func apply(_ event: PublicEvent) {
        switch event.type {
        case "thread.updated", "thread.deleted", "pull_request.updated", "approval.requested", "approval.resolved":
            scheduleRefresh()
        default:
            if event.type.hasPrefix("run.") { scheduleRefresh() }
        }
    }

    private func scheduleRefresh() {
        refreshDebounce?.cancel()
        refreshDebounce = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await refreshThreads()
        }
    }

    // MARK: Lookups

    func project(_ id: String?) -> Project? { projects.first { $0.id == id } }
    func thread(_ id: String) -> AgentThread? { threads.first { $0.id == id } ?? archived.first { $0.id == id } }
    func modelName(_ id: String?) -> String? { catalog?.model(id)?.name ?? id }

    var liveThreads: [AgentThread] { threads.filter { $0.status == .running || $0.status == .queued } }
    var attentionCount: Int { pendingApprovals.count + threads.filter { $0.status == .failed }.count }

    func replace(_ thread: AgentThread) {
        if let index = threads.firstIndex(where: { $0.id == thread.id }) {
            if thread.status == .archived { threads.remove(at: index) } else { threads[index] = thread }
        } else if thread.status != .archived {
            threads.insert(thread, at: 0)
        }
        if let index = archived.firstIndex(where: { $0.id == thread.id }) {
            if thread.status == .archived { archived[index] = thread } else { archived.remove(at: index) }
        }
    }
}
