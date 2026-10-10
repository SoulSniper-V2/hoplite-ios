import Foundation
import Testing
@testable import Hoplite

/// Read-only smoke test of every decoder against a real workspace. Runs only when
/// `TEST_RUNNER_HOPLITE_API_KEY` is set for `xcodebuild test`; never commit a key.
@MainActor
struct LiveAPITests {
    nonisolated static let key = ProcessInfo.processInfo.environment["HOPLITE_API_KEY"]

    private final class Log {
        var failures: [String] = []
        func check<T>(_ name: String, _ body: () async throws -> T) async -> T? {
            do {
                let value = try await body()
                print("LIVE OK   \(name)")
                return value
            } catch {
                print("LIVE FAIL \(name): \(error)")
                failures.append("\(name): \(error)")
                return nil
            }
        }
    }

    @Test(.enabled(if: key != nil), .timeLimit(.minutes(3)))
    func everyReadEndpointDecodes() async throws {
        let service = LiveService(client: HopliteClient { .apiKey(LiveAPITests.key!) })
        let log = Log()

        let projects = await log.check("projects") { try await service.projects() } ?? []
        let page = await log.check("threads") { try await service.threads(projectId: nil, archived: false, query: nil) }
        _ = await log.check("threads archived") { try await service.threads(projectId: nil, archived: true, query: nil) }
        _ = await log.check("models") { try await service.models() }
        _ = await log.check("billing summary") { try await service.billingSummary() }
        _ = await log.check("billing plan") { try await service.billingPlan() }
        _ = await log.check("organization usage") { try await service.organizationUsage() }

        for thread in (page?.threads ?? []).prefix(4) {
            let id = thread.id
            _ = await log.check("thread \(id)") { try await service.thread(id) }
            _ = await log.check("messages \(id)") { try await service.messages(threadId: id) }
            let runs = await log.check("runs \(id)") { try await service.runs(threadId: id) } ?? []
            if let run = runs.first {
                _ = await log.check("activity \(id)") { try await service.activity(threadId: id, runId: run.id) }
                _ = await log.check("failure \(id)") { try await service.runFailure(threadId: id, runId: run.id) }
            }
            _ = await log.check("approvals \(id)") { try await service.approvals(threadId: id) }
            _ = await log.check("diff \(id)") { try await service.diff(threadId: id, mode: .uncommitted) }
            _ = await log.check("checkpoints \(id)") { try await service.checkpoints(threadId: id) }
            _ = await log.check("pr status \(id)") { try await service.pullRequestStatus(threadId: id) }
            _ = await log.check("pr comments \(id)") { try await service.pullRequestComments(threadId: id) }
            _ = await log.check("review loop \(id)") { try await service.reviewLoop(threadId: id) }
            _ = await log.check("preview \(id)") { try await service.preview(threadId: id) }
            _ = await log.check("usage \(id)") { try await service.usage(threadId: id) }
            _ = await log.check("recovery \(id)") { try await service.workspaceRecovery(threadId: id) }
            _ = await log.check("export \(id)") { try await service.exportTranscript(threadId: id) }
        }

        for project in projects.prefix(3) {
            let automations = await log.check("automations \(project.id)") { try await service.automations(projectId: project.id) } ?? []
            if let automation = automations.first {
                _ = await log.check("executions \(automation.id)") { try await service.automationExecutions(projectId: project.id, automationId: automation.id) }
            }
            _ = await log.check("automation status \(project.id)") { try await service.automationStatus(projectId: project.id) }
            _ = await log.check("env vars \(project.id)") { try await service.envVars(projectId: project.id) }
            _ = await log.check("repositories \(project.id)") { try await service.projectRepositories(projectId: project.id) }
        }

        _ = await log.check("workspace projects") { try await service.workspaceProjects() }
        _ = await log.check("github installations") { try await service.githubInstallations() }
        let repos = await log.check("github repositories") { try await service.githubRepositories() } ?? []
        if let repo = repos.first {
            _ = await log.check("github branches") { try await service.githubBranches(repositoryId: repo.id) }
            _ = await log.check("inspect repository") { try await service.inspectRepository(repositoryId: repo.id) }
        }
        _ = await log.check("mcp servers") { try await service.mcpServers() }
        let hooks = (try? await service.webhooks()) ?? []
        if let hook = hooks.first {
            _ = await log.check("webhook deliveries") { try await service.webhookDeliveries(id: hook.id, cursor: nil) }
        }
        // Personal keys lack webhook/service-account scopes; the app must surface that as a permission error.
        for (name, call) in [("webhooks scope", { _ = try await service.webhooks() }), ("service accounts scope", { _ = try await service.serviceAccounts() })] as [(String, () async throws -> Void)] {
            do { try await call(); print("LIVE OK   \(name)") } catch let error as APIError where error.code == "insufficient_permissions" { print("LIVE OK   \(name) (no permission, surfaced correctly)") } catch { log.failures.append("\(name): \(error)") }
        }
        _ = await log.check("capabilities") { try await service.capabilities() }
        _ = await log.check("health") { try await service.health() }

        var frames = 0
        let stream = service.events(projectId: nil, threadId: nil)
        let reader = Task { for await _ in stream { frames += 1; if frames >= 1 { break } } }
        try? await Task.sleep(for: .seconds(8))
        reader.cancel()
        print("LIVE \(frames > 0 ? "OK  " : "INFO") event stream frames=\(frames)")

        #expect(log.failures.isEmpty, "\(log.failures.joined(separator: "\n"))")
    }
}
