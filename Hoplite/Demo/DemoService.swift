import Foundation

/// A self-contained simulated Hoplite workspace. Runs progress on their own, stream
/// drafts token by token, request approvals and publish the same event shapes as the
/// live `/api/events/stream`, so every screen behaves exactly as it does when signed in.
@MainActor
final class DemoService: HopliteService {
    nonisolated var isDemo: Bool { true }

    var projectsStore: [Project] = DemoData.projects
    private var threadsStore: [AgentThread] = DemoData.threads
    private var messagesStore: [String: [Message]] = DemoData.messages
    private var activityStore: [String: [ActivityItem]] = DemoData.activity
    private var approvalsStore: [String: [Approval]] = DemoData.approvals
    private var diffs: [String: [DiffFile]] = DemoData.diffs
    private var prStatuses: [String: PullRequestStatus] = DemoData.pullRequests
    var automationsStore: [Automation] = DemoData.automations
    private var uploads: [String: Data] = [:]
    private var reviewLoops: [String: ReviewLoop] = DemoData.reviewLoops
    private var recoveries: [String: WorkspaceRecovery] = [:]
    private var subscribers: [UUID: (filter: (String?, String?), continuation: AsyncStream<StreamFrame>.Continuation)] = [:]
    private var sequence = 1000
    private var started = false

    init() {}

    // MARK: Simulation

    private func startAmbientSimulation() {
        guard !started else { return }
        started = true
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            await self?.simulateRateLimitRun()
        }
    }

    private func simulateRateLimitRun() async {
        let threadId = DemoData.rateLimitThreadId
        let runId = "run_rl_2"
        let steps: [(String, String, String)] = [
            ("read_file", "Read `src/middleware/rate-limit.ts`", "export function rateLimit(opts: RateLimitOptions) { … }"),
            ("search", "Searched for `X-RateLimit` across 214 files", "6 matches in 3 files"),
            ("edit_file", "Edited `src/middleware/rate-limit.ts` (+48 −6)", "Sliding-window limiter backed by Redis"),
            ("shell", "Ran `pnpm vitest run rate-limit` (exit 0)", "✓ 14 tests passed in 2.31s"),
        ]
        for (index, step) in steps.enumerated() {
            let id = "act_rl_live_\(index)"
            appendActivity(threadId: threadId, runId: runId, id: id, tool: step.0, description: step.1, status: "running")
            try? await Task.sleep(for: .seconds(2.2))
            completeActivity(threadId: threadId, id: id, output: step.2)
            persistTool(threadId: threadId, runId: runId, tool: step.0, content: step.1)
        }

        await streamAssistant(
            threadId: threadId, runId: runId,
            text: "The limiter now uses a sliding window in Redis, so bursts at a window boundary can no longer double the allowance. Next I need to add the new `RATE_LIMIT_REDIS_URL` secret to the CI workflow so the integration suite can run against a real Redis instance."
        )

        let approval = Approval(
            id: "apr_rl_ci", threadId: threadId, runId: runId, toolName: "edit_file", toolCallId: "call_ci",
            requestEventId: "evt_ci", actionable: true, createdAt: ISO8601.string(.now),
            summary: "Edit `.github/workflows/ci.yml` to add a Redis service container"
        )
        approvalsStore[threadId, default: []].append(approval)
        updateThread(threadId) { $0.status = .blocked; $0.runStatus = .waiting; $0.blockedOn = ["approval"] }
        emit("approval.requested", threadId: threadId, runId: runId, dataId: approval.id)
    }

    private func streamAssistant(threadId: String, runId: String, text: String) async {
        let messageId = "msg_\(UUID().uuidString.prefix(8))"
        var revision = 0
        var visible = ""
        for word in text.split(separator: " ", omittingEmptySubsequences: false) {
            visible += (visible.isEmpty ? "" : " ") + word
            revision += 1
            broadcast(.draft(DraftFrame(messageId: messageId, revision: revision, content: visible, kind: .chat)), threadId: threadId)
            try? await Task.sleep(for: .milliseconds(Int.random(in: 28...70)))
        }
        let message = Message(id: messageId, threadId: threadId, runId: runId, role: .assistant, kind: .chat, content: text, createdAt: ISO8601.string(.now))
        messagesStore[threadId, default: []].append(message)
        broadcast(.draftRemoved(messageId: messageId), threadId: threadId)
        emit("message.persisted", threadId: threadId, runId: runId, dataId: messageId)
    }

    private func simulateReply(threadId: String, prompt: String, isNewThread: Bool) async {
        let runId = "run_\(UUID().uuidString.prefix(6))"
        if isNewThread {
            for phase in ["provisioning_workspace", "fetching_repository", "configuring_workspace", "dispatching_run"] {
                updateThread(threadId) { $0.initializationState = "preparing"; $0.initializationPhase = phase }
                try? await Task.sleep(for: .seconds(1.1))
            }
            updateThread(threadId) { $0.initializationState = "completed"; $0.initializationPhase = nil }
        }
        updateThread(threadId) {
            $0.status = .running; $0.runStatus = .running; $0.latestRunId = runId
            $0.runStartedAt = ISO8601.string(.now); $0.runSteerable = true
        }
        emit("run.running", threadId: threadId, runId: runId, dataId: runId, status: "running")

        let steps: [(String, String, String)] = [
            ("search", "Searched the repository for related code", "Found 4 relevant files"),
            ("read_file", "Read `src/app/routes.ts`", "182 lines"),
            ("edit_file", "Edited `src/app/routes.ts` (+12 −3)", "Applied change"),
            ("shell", "Ran `pnpm test --filter app` (exit 0)", "✓ 38 tests passed"),
        ]
        for (index, step) in steps.enumerated() {
            let id = "act_\(runId)_\(index)"
            appendActivity(threadId: threadId, runId: runId, id: id, tool: step.0, description: step.1, status: "running")
            try? await Task.sleep(for: .seconds(1.6))
            completeActivity(threadId: threadId, id: id, output: step.2)
            persistTool(threadId: threadId, runId: runId, tool: step.0, content: step.1)
        }

        let summary = prompt.count > 80 ? String(prompt.prefix(80)) + "…" : prompt
        await streamAssistant(
            threadId: threadId, runId: runId,
            text: "Done. I worked through **\(summary)** in the existing workspace.\n\n- Updated `src/app/routes.ts` so the new path is registered before the catch-all handler\n- Added a regression test next to the existing route specs\n- The app test suite passes (38/38)\n\nThe change is uncommitted in the workspace. Want me to open a pull request?"
        )
        diffs[threadId, default: []].append(DemoData.routesDiff)
        updateThread(threadId) { $0.status = .ready; $0.runStatus = .completed; $0.runSteerable = nil }
        emit("run.completed", threadId: threadId, runId: runId, dataId: runId, status: "completed")
    }

    private func appendActivity(threadId: String, runId: String, id: String, tool: String, description: String, status: String) {
        let item = ActivityItem(kind: "tool", id: id, threadId: threadId, runId: runId, toolCallId: id, toolName: tool, status: status, createdAt: ISO8601.string(.now), description: description)
        activityStore[runId, default: []].append(item)
        emit("tool.updated", threadId: threadId, runId: runId, dataId: id, status: status)
    }

    private func completeActivity(threadId: String, id: String, output: String) {
        for (runId, items) in activityStore {
            guard let index = items.firstIndex(where: { $0.id == id }) else { continue }
            activityStore[runId]?[index].status = "completed"
            activityStore[runId]?[index].completedAt = ISO8601.string(.now)
            activityStore[runId]?[index].outputPreview = output
            emit("tool.updated", threadId: threadId, runId: runId, dataId: id, status: "completed")
        }
    }

    private func persistTool(threadId: String, runId: String, tool: String, content: String) {
        let message = Message(id: "msg_tool_\(UUID().uuidString.prefix(8))", threadId: threadId, runId: runId, role: .tool, kind: .tool, content: content, createdAt: ISO8601.string(.now), toolName: tool)
        messagesStore[threadId, default: []].append(message)
        emit("message.persisted", threadId: threadId, runId: runId, dataId: message.id)
    }

    private func updateThread(_ id: String, _ change: (inout AgentThread) -> Void) {
        guard let index = threadsStore.firstIndex(where: { $0.id == id }) else { return }
        change(&threadsStore[index])
        threadsStore[index].updatedAt = ISO8601.string(.now)
        threadsStore[index].version = (threadsStore[index].version ?? 0) + 1
        emit("thread.updated", threadId: id, runId: threadsStore[index].latestRunId, dataId: id, status: threadsStore[index].status.rawValue)
    }

    private func emit(_ type: String, threadId: String, runId: String?, dataId: String, status: String? = nil) {
        sequence += 1
        let projectId = threadsStore.first { $0.id == threadId }?.projectId
        let event = PublicEvent(
            id: "evt_\(sequence)", type: type, projectId: projectId, threadId: threadId, runId: runId,
            data: .init(id: dataId, status: status), occurredAt: ISO8601.string(.now), cursor: "c\(sequence)"
        )
        broadcast(.event(event), threadId: threadId)
    }

    private func broadcast(_ frame: StreamFrame, threadId: String) {
        let projectId = threadsStore.first { $0.id == threadId }?.projectId
        for subscriber in subscribers.values {
            let (projectFilter, threadFilter) = subscriber.filter
            if let threadFilter, threadFilter != threadId { continue }
            if let projectFilter, projectFilter != projectId { continue }
            if case .draft = frame, threadFilter == nil { continue }
            if case .draftRemoved = frame, threadFilter == nil { continue }
            subscriber.continuation.yield(frame)
        }
    }

    private func latency() async { try? await Task.sleep(for: .milliseconds(Int.random(in: 120...320))) }

    // MARK: HopliteService

    func projects() async throws -> [Project] {
        await latency()
        startAmbientSimulation()
        return projectsStore
    }

    func threads(projectId: String?, archived: Bool, query: String?) async throws -> ThreadPage {
        await latency()
        startAmbientSimulation()
        var list = threadsStore.filter { ($0.status == .archived) == archived }
        if let projectId { list = list.filter { $0.projectId == projectId } }
        if let query, !query.isEmpty { list = list.filter { $0.displayTitle.localizedCaseInsensitiveContains(query) } }
        list.sort { ($0.updated ?? .distantPast) > ($1.updated ?? .distantPast) }
        var counts: [String: Int] = [:]
        for thread in threadsStore { counts[thread.status.rawValue, default: 0] += 1 }
        return ThreadPage(threads: list, nextCursor: nil, statusCounts: counts, totalCount: list.count)
    }

    func thread(_ id: String) async throws -> AgentThread {
        guard let thread = threadsStore.first(where: { $0.id == id }) else { throw APIError(status: 404, code: "thread_not_found") }
        return thread
    }

    func createThread(projectId: String, prompt: String, model: String?, title: String?, options: ThreadOptions) async throws -> AgentThread {
        await latency()
        let id = "thr_\(UUID().uuidString.prefix(8).lowercased())"
        let generatedTitle = title?.isEmpty == false ? title! : DemoData.title(for: prompt)
        var thread = AgentThread(
            id: id, projectId: projectId, modelId: model ?? "claude-fable-5", title: generatedTitle, status: .queued,
            initializationState: "accepted", initializationPhase: "provisioning_workspace",
            createdAt: ISO8601.string(.now), updatedAt: ISO8601.string(.now), version: 1, archiveVersion: 0, titleVersion: 0,
            latestUserMessageAt: ISO8601.string(.now), participantUserIds: ["user_demo"]
        )
        thread.spendLimitMicros = options.spendLimitMicros
        threadsStore.insert(thread, at: 0)
        var first = Message(id: "msg_\(id)_0", threadId: id, authorUserId: "user_demo", author: DemoData.me, role: .user, kind: .chat, content: prompt, createdAt: ISO8601.string(.now))
        if !options.attachmentTickets.isEmpty {
            first.metadata = MessageMetadata(attachments: options.attachmentTickets.map { MessageAttachment(artifactId: $0, contentType: "image/jpeg", name: nil) })
        }
        messagesStore[id] = [first]
        emit("thread.updated", threadId: id, runId: nil, dataId: id, status: "queued")
        Task { [weak self] in await self?.simulateReply(threadId: id, prompt: prompt, isNewThread: true) }
        return thread
    }

    func setArchived(_ thread: AgentThread, archived: Bool) async throws -> AgentThread {
        await latency()
        updateThread(thread.id) {
            $0.status = archived ? .archived : .ready
            $0.archivedAt = archived ? ISO8601.string(.now) : nil
            $0.archiveVersion = ($0.archiveVersion ?? 0) + 1
        }
        return try await self.thread(thread.id)
    }

    func setSpendLimit(_ thread: AgentThread, micros: Int?) async throws -> AgentThread {
        await latency()
        updateThread(thread.id) { $0.spendLimitMicros = micros }
        return try await self.thread(thread.id)
    }

    func rename(_ thread: AgentThread, title: String) async throws -> AgentThread {
        updateThread(thread.id) { $0.title = title }
        return try await self.thread(thread.id)
    }

    func messages(threadId: String) async throws -> [Message] {
        await latency()
        return messagesStore[threadId] ?? []
    }

    func uploadAttachment(threadId: String, data: Data, filename: String, contentType: String, width: Int, height: Int) async throws -> UploadedAttachment {
        try await Task.sleep(for: .milliseconds(Int.random(in: 400...900)))
        let id = "art_\(UUID().uuidString.prefix(8))"
        uploads[id] = data
        return UploadedAttachment(artifactId: id, contentType: contentType, name: filename)
    }

    func stageInitialAttachment(projectId: String, operationId: String, data: Data, filename: String, contentType: String, width: Int, height: Int) async throws -> String {
        try await Task.sleep(for: .milliseconds(Int.random(in: 300...700)))
        let id = "art_\(UUID().uuidString.prefix(8))"
        uploads[id] = data
        return id
    }

    func sendMessage(threadId: String, content: String, model: String?, attachments: [UploadedAttachment]) async throws {
        var message = Message(id: "msg_\(UUID().uuidString.prefix(8))", threadId: threadId, authorUserId: "user_demo", author: DemoData.me, role: .user, kind: .chat, content: content, createdAt: ISO8601.string(.now))
        if !attachments.isEmpty {
            message.metadata = MessageMetadata(attachments: attachments.map { MessageAttachment(artifactId: $0.artifactId, contentType: $0.contentType, name: $0.name) })
        }
        messagesStore[threadId, default: []].append(message)
        emit("message.persisted", threadId: threadId, runId: nil, dataId: message.id)
        let current = threadsStore.first { $0.id == threadId }
        if current?.hasLiveRun == true { return }
        Task { [weak self] in await self?.simulateReply(threadId: threadId, prompt: content, isNewThread: false) }
    }

    func runs(threadId: String) async throws -> [Run] {
        guard let thread = threadsStore.first(where: { $0.id == threadId }), let runId = thread.latestRunId else { return [] }
        return [Run(id: runId, threadId: threadId, status: thread.runStatus ?? .completed, createdAt: thread.runStartedAt ?? thread.createdAt ?? "", startedAt: thread.runStartedAt, finishedAt: nil)]
    }

    func activity(threadId: String, runId: String) async throws -> [ActivityItem] {
        activityStore[runId] ?? []
    }

    func runFailure(threadId: String, runId: String) async throws -> RunFailure? {
        threadId == DemoData.failedThreadId
            ? RunFailure(code: "verification_failed", message: "Tests failed after 3 repair attempts")
            : nil
    }

    func stop(threadId: String, runId: String) async throws {
        await latency()
        updateThread(threadId) { $0.status = .ready; $0.runStatus = .cancelled; $0.stopRequestedAt = ISO8601.string(.now) }
        emit("run.cancelled", threadId: threadId, runId: runId, dataId: runId, status: "cancelled")
    }

    func retry(threadId: String) async throws {
        await latency()
        let prompt = messagesStore[threadId]?.last { $0.role == .user }?.content ?? "Retry"
        Task { [weak self] in await self?.simulateReply(threadId: threadId, prompt: prompt, isNewThread: false) }
    }

    func compact(threadId: String) async throws { await latency() }

    func approvals(threadId: String) async throws -> [Approval] {
        approvalsStore[threadId] ?? []
    }

    func resolveApproval(threadId: String, approvalId: String, approved: Bool, reason: String?) async throws {
        await latency()
        approvalsStore[threadId]?.removeAll { $0.id == approvalId }
        emit("approval.resolved", threadId: threadId, runId: nil, dataId: approvalId)
        updateThread(threadId) { $0.status = .running; $0.runStatus = .running; $0.blockedOn = [] }
        Task { [weak self] in
            guard let self else { return }
            let runId = self.threadsStore.first { $0.id == threadId }?.latestRunId ?? "run"
            if approved {
                self.appendActivity(threadId: threadId, runId: runId, id: "act_after_\(approvalId)", tool: "edit_file", description: "Edited `.github/workflows/ci.yml` (+9)", status: "running")
                try? await Task.sleep(for: .seconds(1.4))
                self.completeActivity(threadId: threadId, id: "act_after_\(approvalId)", output: "Added redis service")
                self.persistTool(threadId: threadId, runId: runId, tool: "edit_file", content: "Edited `.github/workflows/ci.yml` (+9)")
                await self.streamAssistant(threadId: threadId, runId: runId, text: "Approved change applied. CI now boots a Redis 7 service container and the integration suite runs against it. Everything is green locally, so this is ready for review.")
            } else {
                await self.streamAssistant(threadId: threadId, runId: runId, text: "Understood, I left the CI workflow untouched. The integration tests will keep using the in-memory store; I've noted the gap in the PR description instead.")
            }
            self.updateThread(threadId) { $0.status = .ready; $0.runStatus = .completed }
            self.emit("run.completed", threadId: threadId, runId: runId, dataId: runId, status: "completed")
        }
    }

    func diff(threadId: String, mode: DiffMode) async throws -> ThreadDiff {
        await latency()
        let files = diffs[threadId] ?? []
        return ThreadDiff(threadId: threadId, mode: mode, files: files, effectiveMode: mode, unavailableReason: files.isEmpty ? "No changes in this workspace yet." : nil)
    }

    func checkpoints(threadId: String) async throws -> [Checkpoint] {
        (messagesStore[threadId] ?? []).filter { $0.role == .user }.enumerated().map { index, message in
            Checkpoint(id: "cp_\(index)", threadId: threadId, runId: message.runId, label: "Before: \(message.content.prefix(40))", gitCommitSha: String(format: "%07x", 0xA1B2C3 + index * 7919), createdAt: message.createdAt)
        }
    }

    func restoreCheckpoint(threadId: String, checkpointId: String) async throws {
        try await Task.sleep(for: .seconds(1))
        let checkpoints = try await checkpoints(threadId: threadId)
        guard let checkpoint = checkpoints.first(where: { $0.id == checkpointId }) else { throw APIError(status: 404, code: "checkpoint_not_found") }
        let status = Message(id: "msg_restore_\(UUID().uuidString.prefix(6))", threadId: threadId, role: .system, kind: .status, content: "Workspace restored to **\(checkpoint.label ?? "checkpoint")**", createdAt: ISO8601.string(.now))
        messagesStore[threadId, default: []].append(status)
        emit("message.persisted", threadId: threadId, runId: nil, dataId: status.id)
    }

    func workspaceRecovery(threadId: String) async throws -> WorkspaceRecovery {
        recoveries[threadId] ?? WorkspaceRecovery(bricked: threadId == DemoData.failedThreadId, canReset: true, canRestoreSnapshot: true, snapshotSupersededAt: nil)
    }

    func recoverWorkspace(threadId: String, reset: Bool) async throws -> WorkspaceRecovery {
        try await Task.sleep(for: .seconds(1.2))
        let recovery = WorkspaceRecovery(bricked: false, canReset: true, canRestoreSnapshot: !reset, snapshotSupersededAt: nil)
        recoveries[threadId] = recovery
        return recovery
    }

    func exportTranscript(threadId: String) async throws -> String {
        let thread = try await self.thread(threadId)
        let body = (messagesStore[threadId] ?? []).filter { $0.resolvedKind == .chat }.map { message in
            "### \(message.role == .user ? (message.author?.name ?? "You") : "Agent")\n\n\(message.content)"
        }
        return "# \(thread.displayTitle)\n\n" + body.joined(separator: "\n\n")
    }

    func attachmentData(threadId: String, artifactId: String) async throws -> Data {
        guard let data = uploads[artifactId] else { throw APIError(status: 404, code: "attachment_not_found") }
        return data
    }

    func pullRequestComments(threadId: String) async throws -> PullRequestComments? {
        await latency()
        guard let status = prStatuses[threadId] else { return nil }
        let threads = DemoData.reviewThreads[threadId] ?? []
        return PullRequestComments(number: status.number, repoFullName: status.repoFullName, commentsAvailable: true, unresolvedCount: threads.filter { !$0.isResolved }.count, comments: [], reviewThreads: threads)
    }

    func reviewLoop(threadId: String) async throws -> ReviewLoop? {
        guard prStatuses[threadId] != nil else { return nil }
        return reviewLoops[threadId] ?? ReviewLoop(id: "rl_\(threadId)", pullRequestId: "pr_\(threadId)", enabled: false, autoMerge: false, status: "disabled", passCount: 0)
    }

    func setReviewLoop(threadId: String, enabled: Bool, autoMerge: Bool) async throws -> ReviewLoop {
        await latency()
        var loop = try await reviewLoop(threadId: threadId) ?? ReviewLoop(id: "rl_\(threadId)", pullRequestId: "pr_\(threadId)", enabled: false, status: "disabled", passCount: 0)
        loop.enabled = enabled
        loop.autoMerge = autoMerge
        loop.status = enabled ? "observing" : "disabled"
        loop.lastObservedAt = ISO8601.string(.now)
        reviewLoops[threadId] = loop
        return loop
    }

    func pullRequestStatus(threadId: String) async throws -> PullRequestStatus? {
        await latency()
        return prStatuses[threadId]
    }

    func createPullRequest(threadId: String, title: String?, body: String?, draft: Bool) async throws -> PullRequest {
        try await Task.sleep(for: .seconds(1.2))
        let thread = try await self.thread(threadId)
        let number = Int.random(in: 220...260)
        let repo = projectsStore.first { $0.id == thread.projectId }?.repos?.first?.display ?? "acme/storefront"
        let pr = PullRequest(id: "pr_\(number)", number: number, url: "https://github.com/\(repo)/pull/\(number)", repoFullName: repo, state: "open", headRef: "hoplite/\(threadId)", headSha: "4f2a9c1e8b7d6a5f4e3d2c1b0a9f8e7d6c5b4a39", baseRef: "main", draft: draft, githubSummary: GitHubSummary(state: "open", draft: draft, mergeable: "unknown", checks: ChecksSummary(total: 8, succeeded: 0, failing: 0, running: 8), unresolvedCount: 0))
        prStatuses[threadId] = PullRequestStatus(number: number, url: pr.url, repoFullName: repo, title: title ?? thread.displayTitle, body: body, state: "open", draft: draft, mergeable: "unknown", checks: DemoData.checks(running: 8, total: 8), additions: 14, deletions: 3, changedFiles: 2, baseRef: "main", headRef: pr.headRef, headSha: pr.headSha, allowedMergeMethods: ["squash", "merge", "rebase"])
        updateThread(threadId) { $0.primaryPullRequest = pr; $0.pullRequests = [pr] }
        emit("pull_request.updated", threadId: threadId, runId: nil, dataId: pr.id ?? "", status: "open")
        return pr
    }

    func mergePullRequest(threadId: String, expectedHeadSha: String, method: String) async throws -> MergeResult {
        try await Task.sleep(for: .seconds(1.0))
        prStatuses[threadId]?.state = "merged"
        updateThread(threadId) {
            $0.primaryPullRequest?.state = "merged"
            $0.primaryPullRequest?.githubSummary?.state = "merged"
        }
        emit("pull_request.updated", threadId: threadId, runId: nil, dataId: "pr", status: "merged")
        return MergeResult(merged: true, queued: false, sha: "9e8d7c6", message: "Pull request successfully merged")
    }

    func preview(threadId: String) async throws -> Preview {
        Preview(status: "ready", name: "web", port: 3000, url: "https://hoplite.sh", gateway: nil)
    }

    func previewAccess(threadId: String) async throws -> Preview {
        try await preview(threadId: threadId)
    }

    func startPreview(threadId: String) async throws -> Preview {
        try await Task.sleep(for: .seconds(1))
        return try await preview(threadId: threadId)
    }

    func models() async throws -> ModelCatalog { DemoData.catalog }

    func usage(threadId: String) async throws -> ThreadUsage {
        let seed = Double(abs(threadId.hashValue % 900)) / 100
        let limit = threadsStore.first { $0.id == threadId }?.spendLimitMicros
        return ThreadUsage(totalCostMicros: (0.18 + seed / 3) * 1_000_000, spendLimitMicros: limit, llmCostMicros: (0.14 + seed / 4) * 1_000_000, vmCostMicros: 40_000, runCount: 2, inputTokens: 412_000 + seed * 10_000, outputTokens: 18_400, latestContextTokens: 96_000, topModel: "claude-fable-5", runtimeMs: 412_000, usesByok: false)
    }

    func billingSummary() async throws -> BillingSummary {
        BillingSummary(grantedCredits: 200, remainingCredits: 142.6, usedCredits: 57.4, heldCredits: 1.2, available: true, nextResetAt: ISO8601.string(.now.addingTimeInterval(86_400 * 12)), includedCredits: 200, remainingIncludedCredits: 142.6)
    }

    func billingPlan() async throws -> BillingPlan {
        BillingPlan(plan: "pro", billingInterval: "monthly", sandboxIdleMinutes: 30, seatCount: 6)
    }

    func organizationUsage() async throws -> OrganizationUsage {
        OrganizationUsage(orgId: "org_acme", totalCostMicros: 57_400_000, inputTokens: 48_200_000, outputTokens: 2_140_000, events: 1_284)
    }

    func automations(projectId: String) async throws -> [Automation] {
        await latency()
        return automationsStore.filter { $0.projectId == projectId }
    }

    func automationExecutions(projectId: String, automationId: String) async throws -> [AutomationExecution] {
        await latency()
        return DemoData.executions(automationId: automationId, projectId: projectId)
    }

    func runAutomation(projectId: String, automationId: String) async throws {
        guard let automation = automationsStore.first(where: { $0.id == automationId }) else { return }
        _ = try await createThread(projectId: projectId, prompt: automation.prompt, model: automation.modelId, title: automation.title ?? automation.name, options: ThreadOptions())
    }

    func setAutomationEnabled(_ automation: Automation, enabled: Bool) async throws -> Automation {
        await latency()
        guard let index = automationsStore.firstIndex(where: { $0.id == automation.id }) else { return automation }
        automationsStore[index].enabled = enabled
        return automationsStore[index]
    }

    nonisolated func events(projectId: String?, threadId: String?) -> AsyncStream<StreamFrame> {
        AsyncStream { continuation in
            let token = UUID()
            Task { @MainActor in
                self.subscribers[token] = ((projectId, threadId), continuation)
            }
            continuation.onTermination = { _ in
                Task { @MainActor in self.subscribers[token] = nil }
            }
        }
    }
}
