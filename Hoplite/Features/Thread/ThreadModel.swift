import Observation
import SwiftUI

enum TimelineItem: Identifiable {
    case user(Message)
    case assistant(Message)
    case thinking(Message)
    case status(Message)
    case activity(id: String, tools: [Message])
    case draft(DraftFrame)

    var id: String {
        switch self {
        case .user(let m), .assistant(let m), .thinking(let m), .status(let m): m.id
        case .activity(let id, _): "act-\(id)"
        case .draft(let d): "draft-\(d.messageId)"
        }
    }
}

@Observable
final class ThreadModel {
    let threadId: String
    private let service: any HopliteService
    private let onThreadChange: (AgentThread) -> Void

    var thread: AgentThread?
    var messages: [Message] = []
    var drafts: [String: DraftFrame] = [:]
    var liveActivity: [ActivityItem] = []
    var approvals: [Approval] = []
    var failure: RunFailure?
    var loaded = false
    var error: String?
    var sending = false
    /// Images sent from this device, keyed by message text, so the bubble can show them immediately.
    var sentImages: [String: [UIImage]] = [:]

    private var streamTask: Task<Void, Never>?
    private var refreshTasks: [String: Task<Void, Never>] = [:]

    init(threadId: String, service: any HopliteService, onThreadChange: @escaping (AgentThread) -> Void) {
        self.threadId = threadId
        self.service = service
        self.onThreadChange = onThreadChange
    }

    var timeline: [TimelineItem] {
        var items: [TimelineItem] = []
        var pendingTools: [Message] = []
        func flushTools() {
            guard let first = pendingTools.first else { return }
            items.append(.activity(id: first.id, tools: pendingTools))
            pendingTools = []
        }
        for message in messages {
            switch (message.role, message.resolvedKind) {
            case (_, .tool), (.tool, _):
                pendingTools.append(message)
            case (.user, _):
                flushTools(); items.append(.user(message))
            case (_, .thinking):
                flushTools(); items.append(.thinking(message))
            case (.system, _), (_, .status):
                flushTools(); items.append(.status(message))
            default:
                flushTools(); items.append(.assistant(message))
            }
        }
        flushTools()
        let persisted = Set(messages.map(\.id))
        for draft in drafts.values.sorted(by: { $0.messageId < $1.messageId }) where !persisted.contains(draft.messageId) {
            items.append(.draft(draft))
        }
        return items
    }

    var isLive: Bool { thread?.hasLiveRun == true || thread?.status == .blocked }
    var isWorking: Bool { (thread?.status == .running || thread?.status == .queued) && drafts.isEmpty }
    var currentActivity: ActivityItem? { liveActivity.last { $0.isRunning } }

    var approvalSummaries: [String: String] {
        var map: [String: String] = [:]
        for approval in approvals {
            if let summary = approval.summary { map[approval.id] = summary; continue }
            let match = liveActivity.first { $0.toolCallId != nil && $0.toolCallId == approval.toolCallId }
            map[approval.id] = match?.description ?? match?.inputPreview ?? approval.toolName.map { "Run the `\($0)` tool" } ?? "Continue the run"
        }
        return map
    }

    // MARK: Loading

    func start() async {
        if !loaded { await reload() }
        startStream()
    }

    func stopStreaming() {
        streamTask?.cancel()
        streamTask = nil
    }

    func reload() async {
        do {
            async let thread = service.thread(threadId)
            async let messages = service.messages(threadId: threadId)
            let (t, m) = try await (thread, messages)
            withAnimation(.snappy) {
                self.thread = t
                self.messages = m
                self.loaded = true
            }
            error = nil
            onThreadChange(t)
            await refreshRunState()
        } catch {
            if !(error is CancellationError) { self.error = error.localizedDescription }
            loaded = true
        }
    }

    private func refreshThread() async {
        guard let t = try? await service.thread(threadId) else { return }
        withAnimation(.snappy) { thread = t }
        onThreadChange(t)
        await refreshRunState()
    }

    private func refreshMessages() async {
        guard let m = try? await service.messages(threadId: threadId) else { return }
        withAnimation(.snappy) {
            messages = m
            let persisted = Set(m.map(\.id))
            drafts = drafts.filter { !persisted.contains($0.key) }
        }
    }

    private func refreshRunState() async {
        guard let thread else { return }
        async let approvals = (try? service.approvals(threadId: threadId)) ?? []
        async let activity: [ActivityItem] = {
            guard let runId = thread.latestRunId, thread.hasLiveRun || thread.status == .blocked else { return [] }
            return (try? await service.activity(threadId: threadId, runId: runId)) ?? []
        }()
        async let failure: RunFailure? = {
            guard thread.status == .failed, let runId = thread.latestRunId else { return nil }
            return try? await service.runFailure(threadId: threadId, runId: runId)
        }()
        let (a, act, f) = await (approvals, activity, failure)
        withAnimation(.snappy) {
            self.approvals = a.filter(\.actionable)
            self.liveActivity = act
            self.failure = f
        }
    }

    // MARK: Events

    private func startStream() {
        guard streamTask == nil else { return }
        streamTask = Task { [weak self] in
            guard let self else { return }
            for await frame in self.service.events(projectId: nil, threadId: self.threadId) {
                self.apply(frame)
            }
        }
    }

    private func apply(_ frame: StreamFrame) {
        switch frame {
        case .draft(let draft):
            if let existing = drafts[draft.messageId], existing.revision > draft.revision { return }
            drafts[draft.messageId] = draft
        case .draftRemoved(let id):
            drafts[id] = nil
        case .heartbeat:
            break
        case .event(let event):
            switch event.type {
            case "message.persisted": debounce("messages") { await $0.refreshMessages() }
            case "tool.updated", "approval.requested", "approval.resolved": debounce("run") { await $0.refreshRunState() }
            default: debounce("thread") { await $0.refreshThread() }
            }
        }
    }

    private func debounce(_ key: String, _ work: @escaping (ThreadModel) async -> Void) {
        refreshTasks[key]?.cancel()
        refreshTasks[key] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard let self, !Task.isCancelled else { return }
            await work(self)
        }
    }

    // MARK: Actions

    func send(_ text: String, model: String?, attachments: [PendingAttachment] = []) async -> Bool {
        var content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty || !attachments.isEmpty else { return false }
        if content.isEmpty { content = attachments.count == 1 ? "See the attached image." : "See the attached images." }
        sending = true
        defer { sending = false }
        if !attachments.isEmpty { sentImages[content] = attachments.map(\.image) }
        let optimistic = Message(id: "local-\(UUID().uuidString)", threadId: threadId, role: .user, kind: .chat, content: content, createdAt: ISO8601.string(.now))
        withAnimation(.snappy) { messages.append(optimistic) }
        do {
            var uploaded: [UploadedAttachment] = []
            for attachment in attachments {
                uploaded.append(try await service.uploadAttachment(threadId: threadId, data: attachment.data, filename: attachment.name, contentType: "image/jpeg", width: attachment.width, height: attachment.height))
            }
            try await service.sendMessage(threadId: threadId, content: content, model: model, attachments: uploaded)
            await refreshMessages()
            await refreshThread()
            return true
        } catch {
            withAnimation { messages.removeAll { $0.id == optimistic.id } }
            self.error = error.localizedDescription
            return false
        }
    }

    func stop() async {
        guard let runId = thread?.latestRunId else { return }
        do { try await service.stop(threadId: threadId, runId: runId); await refreshThread() } catch { self.error = error.localizedDescription }
    }

    func retry() async {
        do { try await service.retry(threadId: threadId); await refreshThread() } catch { self.error = error.localizedDescription }
    }

    func compact() async {
        do { try await service.compact(threadId: threadId) } catch { self.error = error.localizedDescription }
    }

    func resolve(_ approval: Approval, approved: Bool) async {
        withAnimation(.snappy) { approvals.removeAll { $0.id == approval.id } }
        do {
            try await service.resolveApproval(threadId: threadId, approvalId: approval.id, approved: approved, reason: nil)
            await refreshThread()
        } catch {
            self.error = error.localizedDescription
            await refreshRunState()
        }
    }

    func rename(_ title: String) async {
        guard let thread, let updated = try? await service.rename(thread, title: title) else { return }
        self.thread = updated
        onThreadChange(updated)
    }

    func setArchived(_ archived: Bool) async {
        guard let thread, let updated = try? await service.setArchived(thread, archived: archived) else { return }
        self.thread = updated
        onThreadChange(updated)
    }
}
