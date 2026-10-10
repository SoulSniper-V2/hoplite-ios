import Foundation

/// Everything the app needs from Hoplite. `LiveService` talks to api.hoplite.sh;
/// `DemoService` runs a believable simulated workspace so the app works signed out.
protocol HopliteService: AnyObject, Sendable {
    var isDemo: Bool { get }

    func projects() async throws -> [Project]
    func threads(projectId: String?, archived: Bool, query: String?) async throws -> ThreadPage
    func thread(_ id: String) async throws -> AgentThread
    func createThread(projectId: String, prompt: String, model: String?, title: String?, options: ThreadOptions) async throws -> AgentThread
    func setSpendLimit(_ thread: AgentThread, micros: Int?) async throws -> AgentThread
    func setArchived(_ thread: AgentThread, archived: Bool) async throws -> AgentThread
    func rename(_ thread: AgentThread, title: String) async throws -> AgentThread

    func messages(threadId: String) async throws -> [Message]
    func sendMessage(threadId: String, content: String, model: String?, attachments: [UploadedAttachment]) async throws
    func uploadAttachment(threadId: String, data: Data, filename: String, contentType: String, width: Int, height: Int) async throws -> UploadedAttachment
    /// Uploads an image for a thread that doesn't exist yet and returns the ticket to pass as `initialAttachmentTickets`.
    func stageInitialAttachment(projectId: String, operationId: String, data: Data, filename: String, contentType: String, width: Int, height: Int) async throws -> String
    func runs(threadId: String) async throws -> [Run]
    func activity(threadId: String, runId: String) async throws -> [ActivityItem]
    func runFailure(threadId: String, runId: String) async throws -> RunFailure?
    func stop(threadId: String, runId: String) async throws
    func retry(threadId: String) async throws
    func compact(threadId: String) async throws

    func approvals(threadId: String) async throws -> [Approval]
    func resolveApproval(threadId: String, approvalId: String, approved: Bool, reason: String?) async throws

    func diff(threadId: String, mode: DiffMode) async throws -> ThreadDiff
    func checkpoints(threadId: String) async throws -> [Checkpoint]
    func restoreCheckpoint(threadId: String, checkpointId: String) async throws
    func workspaceRecovery(threadId: String) async throws -> WorkspaceRecovery
    func recoverWorkspace(threadId: String, reset: Bool) async throws -> WorkspaceRecovery
    func exportTranscript(threadId: String) async throws -> String
    func attachmentData(threadId: String, artifactId: String) async throws -> Data
    func pullRequestComments(threadId: String) async throws -> PullRequestComments?
    func reviewLoop(threadId: String) async throws -> ReviewLoop?
    func setReviewLoop(threadId: String, enabled: Bool, autoMerge: Bool) async throws -> ReviewLoop
    func pullRequestStatus(threadId: String) async throws -> PullRequestStatus?
    func createPullRequest(threadId: String, title: String?, body: String?, draft: Bool) async throws -> PullRequest
    func mergePullRequest(threadId: String, expectedHeadSha: String, method: String) async throws -> MergeResult

    func preview(threadId: String) async throws -> Preview
    func startPreview(threadId: String) async throws -> Preview
    func previewAccess(threadId: String) async throws -> Preview

    func models() async throws -> ModelCatalog
    func usage(threadId: String) async throws -> ThreadUsage
    func billingSummary() async throws -> BillingSummary
    func billingPlan() async throws -> BillingPlan
    func organizationUsage() async throws -> OrganizationUsage

    func automations(projectId: String) async throws -> [Automation]
    func automationExecutions(projectId: String, automationId: String) async throws -> [AutomationExecution]
    func runAutomation(projectId: String, automationId: String) async throws
    func setAutomationEnabled(_ automation: Automation, enabled: Bool) async throws -> Automation

    func events(projectId: String?, threadId: String?) -> AsyncStream<StreamFrame>
}

nonisolated final class LiveService: HopliteService {
    let client: HopliteClient
    var isDemo: Bool { false }

    init(client: HopliteClient) { self.client = client }

    private struct Ok: Decodable {}

    func projects() async throws -> [Project] {
        struct R: Decodable { var projects: [Project]; var nextCursor: String? }
        var all: [Project] = []
        var cursor: String?
        repeat {
            let page: R = try await client.get("/api/projects", query: ["limit": "100", "pagination": "cursor", "cursor": cursor])
            all += page.projects
            cursor = page.nextCursor
        } while cursor != nil && all.count < 500
        return all
    }

    func threads(projectId: String?, archived: Bool, query: String?) async throws -> ThreadPage {
        struct R: Decodable { var threads: [AgentThread]; var nextCursor: String?; var statusCounts: [String: Int]?; var totalCount: Int? }
        let r: R = try await client.get("/api/threads", query: [
            "projectId": projectId, "archived": archived ? "true" : "false",
            "q": query?.isEmpty == false ? query : nil, "limit": "100",
        ])
        return ThreadPage(threads: r.threads, nextCursor: r.nextCursor, statusCounts: r.statusCounts ?? [:], totalCount: r.totalCount ?? r.threads.count)
    }

    func thread(_ id: String) async throws -> AgentThread {
        struct R: Decodable { var thread: AgentThread }
        return try await client.get("/api/threads/\(id)", as: R.self).thread
    }

    func createThread(projectId: String, prompt: String, model: String?, title: String?, options: ThreadOptions) async throws -> AgentThread {
        struct R: Decodable { var thread: AgentThread }
        var body: [String: Any] = ["projectId": projectId, "prompt": prompt]
        if let model { body["model"] = model }
        if let title, !title.isEmpty { body["title"] = title }
        if let reasoning = options.reasoning { body["reasoning"] = ["mode": reasoning] }
        if options.fast { body["speed"] = "fast" }
        if let autoMerge = options.autoMerge { body["autoMerge"] = autoMerge }
        if let limit = options.spendLimitMicros { body["spendLimitMicros"] = limit }
        if !options.attachmentTickets.isEmpty {
            body["initialAttachmentTickets"] = options.attachmentTickets
            body["clientOperationId"] = options.operationId
        }
        return try await client.send("POST", "/api/threads", body: body, as: R.self).thread
    }

    func setArchived(_ thread: AgentThread, archived: Bool) async throws -> AgentThread {
        var body: [String: Any] = ["archived": archived]
        if let v = thread.archiveVersion { body["expectedArchiveVersion"] = v }
        return try await patchThread(thread.id, body: body, fallback: thread)
    }

    func rename(_ thread: AgentThread, title: String) async throws -> AgentThread {
        var body: [String: Any] = ["title": title]
        if let v = thread.titleVersion { body["expectedTitleVersion"] = v }
        return try await patchThread(thread.id, body: body, fallback: thread)
    }

    func setSpendLimit(_ thread: AgentThread, micros: Int?) async throws -> AgentThread {
        try await patchThread(thread.id, body: ["spendLimitMicros": micros.map { $0 as Any } ?? NSNull()], fallback: thread)
    }

    private func patchThread(_ id: String, body: [String: Any], fallback: AgentThread) async throws -> AgentThread {
        struct R: Decodable { var thread: AgentThread? }
        let r: R = try await client.send("PATCH", "/api/threads/\(id)", body: body)
        if let thread = r.thread { return thread }
        return try await thread(id)
    }

    func messages(threadId: String) async throws -> [Message] {
        struct R: Decodable { var messages: [Message] }
        return try await client.get("/api/threads/\(threadId)/messages", query: ["limit": "500", "activityLimit": "1000"], as: R.self).messages
    }

    func sendMessage(threadId: String, content: String, model: String?, attachments: [UploadedAttachment]) async throws {
        var body: [String: Any] = ["content": content, "clientMessageId": UUID().uuidString]
        if let model { body["model"] = model }
        if !attachments.isEmpty {
            body["attachments"] = attachments.map { ["artifactId": $0.artifactId, "contentType": $0.contentType, "name": $0.name] }
        }
        let _: Ok = try await client.send("POST", "/api/threads/\(threadId)/messages", body: body)
    }

    /// Presign, upload the bytes directly to storage, then persist the staged attachment.
    func uploadAttachment(threadId: String, data: Data, filename: String, contentType: String, width: Int, height: Int) async throws -> UploadedAttachment {
        struct Presigned: Decodable {
            struct Upload: Decodable { var artifactId: String; var ticket: String; var uploadUrl: String; var contentType: String }
            var upload: Upload
        }
        struct Confirmed: Decodable {
            struct Attachment: Decodable { var id: String; var name: String; var contentType: String }
            var attachment: Attachment
        }
        let presigned: Presigned = try await client.send("POST", "/api/threads/\(threadId)/attachments/presign", body: [
            "filename": filename, "contentType": contentType, "byteSize": data.count, "width": width, "height": height,
        ])
        guard let url = URL(string: presigned.upload.uploadUrl) else { throw APIError(status: 0, code: "upload_failed") }
        var put = URLRequest(url: url)
        put.httpMethod = "PUT"
        put.setValue(presigned.upload.contentType, forHTTPHeaderField: "Content-Type")
        let (_, response) = try await URLSession.shared.upload(for: put, from: data)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw APIError(status: (response as? HTTPURLResponse)?.statusCode ?? 0, code: "upload_failed") }
        let confirmed: Confirmed = try await client.send("POST", "/api/threads/\(threadId)/attachments/confirm", body: ["ticket": presigned.upload.ticket, "width": width, "height": height])
        return UploadedAttachment(artifactId: presigned.upload.artifactId, contentType: confirmed.attachment.contentType, name: confirmed.attachment.name)
    }

    func stageInitialAttachment(projectId: String, operationId: String, data: Data, filename: String, contentType: String, width: Int, height: Int) async throws -> String {
        struct Presigned: Decodable {
            struct Upload: Decodable { var ticket: String; var uploadUrl: String; var contentType: String }
            var upload: Upload
        }
        let presigned: Presigned = try await client.send("POST", "/api/threads/initial/attachments/presign", query: ["projectId": projectId], body: [
            "filename": filename, "contentType": contentType, "byteSize": data.count, "width": width, "height": height, "initialClientOperationId": operationId,
        ])
        guard let url = URL(string: presigned.upload.uploadUrl) else { throw APIError(status: 0, code: "upload_failed") }
        var put = URLRequest(url: url)
        put.httpMethod = "PUT"
        put.setValue(presigned.upload.contentType, forHTTPHeaderField: "Content-Type")
        let (_, response) = try await URLSession.shared.upload(for: put, from: data)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw APIError(status: (response as? HTTPURLResponse)?.statusCode ?? 0, code: "upload_failed") }
        return presigned.upload.ticket
    }

    func runs(threadId: String) async throws -> [Run] {
        struct R: Decodable { var runs: [Run] }
        return try await client.get("/api/threads/\(threadId)/runs", query: ["limit": "50"], as: R.self).runs
    }

    func activity(threadId: String, runId: String) async throws -> [ActivityItem] {
        struct R: Decodable { var items: [ActivityItem]; var nextCursor: String?; var hasMore: Bool? }
        var items: [ActivityItem] = []
        var cursor: String?
        repeat {
            let page = try await client.get("/api/threads/\(threadId)/runs/\(runId)/activity", query: ["limit": "100", "pagination": "cursor", "cursor": cursor], as: R.self)
            items += page.items
            cursor = page.hasMore == false ? nil : page.nextCursor
        } while cursor != nil && items.count < 1000
        return items
    }

    func runFailure(threadId: String, runId: String) async throws -> RunFailure? {
        struct R: Decodable { var detail: RunFailure? }
        return try await client.get("/api/threads/\(threadId)/runs/\(runId)/failure", as: R.self).detail
    }

    func stop(threadId: String, runId: String) async throws {
        let _: Ok = try await client.send("POST", "/api/threads/\(threadId)/stop", body: ["runId": runId])
    }

    func retry(threadId: String) async throws {
        let _: Ok = try await client.send("POST", "/api/threads/\(threadId)/retry", body: [:])
    }

    func compact(threadId: String) async throws {
        let _: Ok = try await client.send("POST", "/api/threads/\(threadId)/compact", body: [:])
    }

    func approvals(threadId: String) async throws -> [Approval] {
        struct R: Decodable { var approvals: [Approval] }
        return try await client.get("/api/threads/\(threadId)/approvals", as: R.self).approvals
    }

    func resolveApproval(threadId: String, approvalId: String, approved: Bool, reason: String?) async throws {
        var body: [String: Any] = ["approved": approved]
        if let reason, !reason.isEmpty { body["reason"] = reason }
        let _: Ok = try await client.send("POST", "/api/threads/\(threadId)/approvals/\(approvalId)", body: body)
    }

    func diff(threadId: String, mode: DiffMode) async throws -> ThreadDiff {
        struct R: Decodable { var diff: ThreadDiff }
        return try await client.get("/api/threads/\(threadId)/diff", query: ["mode": mode.rawValue], as: R.self).diff
    }

    func checkpoints(threadId: String) async throws -> [Checkpoint] {
        struct R: Decodable { var checkpoints: [Checkpoint] }
        return try await client.get("/api/threads/\(threadId)/checkpoints", as: R.self).checkpoints
    }

    func restoreCheckpoint(threadId: String, checkpointId: String) async throws {
        let _: Ok = try await client.send("POST", "/api/threads/\(threadId)/checkpoints/\(checkpointId)/restore", body: [:])
    }

    func workspaceRecovery(threadId: String) async throws -> WorkspaceRecovery {
        struct R: Decodable { var recovery: WorkspaceRecovery }
        return try await client.get("/api/threads/\(threadId)/workspace/recovery", as: R.self).recovery
    }

    func recoverWorkspace(threadId: String, reset: Bool) async throws -> WorkspaceRecovery {
        struct R: Decodable { var recovery: WorkspaceRecovery }
        let body: [String: Any] = reset ? ["action": "reset", "acceptDataLoss": true] : ["action": "restore_snapshot"]
        return try await client.send("POST", "/api/threads/\(threadId)/workspace/recovery", body: body, as: R.self).recovery
    }

    func exportTranscript(threadId: String) async throws -> String {
        let data = try await client.data("/api/threads/\(threadId)/export", query: ["format": "markdown", "level": "activity"], accept: "text/markdown")
        return String(decoding: data, as: UTF8.self)
    }

    func attachmentData(threadId: String, artifactId: String) async throws -> Data {
        try await client.data("/api/threads/\(threadId)/attachments/\(artifactId)", query: ["media": "inline"], accept: "*/*")
    }

    func pullRequestComments(threadId: String) async throws -> PullRequestComments? {
        struct R: Decodable { var pullRequestComments: PullRequestComments? }
        do {
            return try await client.get("/api/threads/\(threadId)/pr/comments", as: R.self).pullRequestComments
        } catch let error as APIError where error.status == 404 {
            return nil
        }
    }

    func reviewLoop(threadId: String) async throws -> ReviewLoop? {
        struct R: Decodable { var reviewLoop: ReviewLoop? }
        do {
            return try await client.get("/api/threads/\(threadId)/pr/review-loop", as: R.self).reviewLoop
        } catch let error as APIError where error.status == 404 {
            return nil
        }
    }

    func setReviewLoop(threadId: String, enabled: Bool, autoMerge: Bool) async throws -> ReviewLoop {
        struct R: Decodable { var reviewLoop: ReviewLoop }
        return try await client.send("PATCH", "/api/threads/\(threadId)/pr/review-loop", body: ["enabled": enabled, "autoMerge": autoMerge], as: R.self).reviewLoop
    }

    func pullRequestStatus(threadId: String) async throws -> PullRequestStatus? {
        struct R: Decodable { var pullRequestStatus: PullRequestStatus? }
        do {
            return try await client.get("/api/threads/\(threadId)/pr/status", as: R.self).pullRequestStatus
        } catch let error as APIError where error.status == 404 {
            return nil
        }
    }

    func createPullRequest(threadId: String, title: String?, body: String?, draft: Bool) async throws -> PullRequest {
        struct R: Decodable { var pullRequest: PullRequest }
        var payload: [String: Any] = ["draft": draft]
        if let title, !title.isEmpty { payload["title"] = title }
        if let body, !body.isEmpty { payload["body"] = body }
        return try await client.send("POST", "/api/threads/\(threadId)/pr", body: payload, as: R.self).pullRequest
    }

    func mergePullRequest(threadId: String, expectedHeadSha: String, method: String) async throws -> MergeResult {
        struct R: Decodable { var mergeResult: MergeResult }
        return try await client.send("POST", "/api/threads/\(threadId)/pr/merge", body: ["expectedHeadSha": expectedHeadSha, "mergeMethod": method], as: R.self).mergeResult
    }

    func preview(threadId: String) async throws -> Preview {
        struct R: Decodable { var preview: Preview }
        return try await client.get("/api/threads/\(threadId)/preview", as: R.self).preview
    }

    func startPreview(threadId: String) async throws -> Preview {
        struct R: Decodable { var preview: Preview? }
        let r: R = try await client.send("POST", "/api/threads/\(threadId)/preview/start", body: [:])
        if let preview = r.preview { return preview }
        return try await preview(threadId: threadId)
    }

    func previewAccess(threadId: String) async throws -> Preview {
        struct R: Decodable { var preview: Preview }
        return try await client.get("/api/threads/\(threadId)/preview/access", as: R.self).preview
    }

    func models() async throws -> ModelCatalog {
        try await client.get("/api/model-providers")
    }

    func usage(threadId: String) async throws -> ThreadUsage {
        struct R: Decodable { var usage: ThreadUsage }
        return try await client.get("/api/threads/\(threadId)/usage", as: R.self).usage
    }

    func billingSummary() async throws -> BillingSummary {
        struct R: Decodable { var billing: BillingSummary }
        return try await client.get("/api/billing/summary", as: R.self).billing
    }

    func billingPlan() async throws -> BillingPlan {
        struct R: Decodable { var plan: BillingPlan }
        return try await client.get("/api/billing/plan", as: R.self).plan
    }

    func organizationUsage() async throws -> OrganizationUsage {
        struct R: Decodable { var usage: OrganizationUsage }
        return try await client.get("/api/usage", as: R.self).usage
    }

    func automations(projectId: String) async throws -> [Automation] {
        struct R: Decodable { var automations: [Automation] }
        return try await client.get("/api/projects/\(projectId)/automations", as: R.self).automations
    }

    func automationExecutions(projectId: String, automationId: String) async throws -> [AutomationExecution] {
        struct R: Decodable { var executions: [AutomationExecution] }
        return try await client.get("/api/projects/\(projectId)/automations/\(automationId)/executions", query: ["limit": "20"], as: R.self).executions
    }

    func runAutomation(projectId: String, automationId: String) async throws {
        let _: Ok = try await client.send("POST", "/api/projects/\(projectId)/automations/\(automationId)/run")
    }

    func setAutomationEnabled(_ automation: Automation, enabled: Bool) async throws -> Automation {
        struct R: Decodable { var automation: Automation? }
        let r: R = try await client.send("PATCH", "/api/projects/\(automation.projectId)/automations/\(automation.id)", body: ["enabled": enabled])
        var updated = r.automation ?? automation
        updated.enabled = enabled
        return updated
    }

    func events(projectId: String?, threadId: String?) -> AsyncStream<StreamFrame> {
        client.events(projectId: projectId, threadId: threadId)
    }
}
