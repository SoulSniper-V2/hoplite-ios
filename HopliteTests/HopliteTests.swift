import Foundation
import Testing
@testable import Hoplite

@MainActor
struct SSEParserTests {
    @Test func parsesDurableEventWithCursor() throws {
        var parser = SSEParser()
        #expect(parser.consume("id: opaque-cursor") == nil)
        #expect(parser.consume("event: run.completed") == nil)
        let messageLine = parser.consume(#"data: {"id":"event_example","orgId":"org","projectId":"p","threadId":"t","runId":"r","sequence":"42","type":"run.completed","data":{"id":"r","status":"completed"},"occurredAt":"2026-09-22T10:00:00.000Z","cursor":"opaque-cursor"}"#)
        let message = try #require(messageLine)
        #expect(message.id == "opaque-cursor")
        guard case .event(let event) = SSEParser.frame(from: message) else { Issue.record("expected event"); return }
        #expect(event.type == "run.completed")
        #expect(event.data?.status == "completed")
        #expect(event.threadId == "t")
    }

    @Test func parsesDraftSnapshotsAndRemovals() throws {
        var parser = SSEParser()
        _ = parser.consume("event: draft")
        let draftLine = parser.consume(#"data: {"messageId":"m1","streamId":"s","revision":3,"content":"Hello wor"}"#)
        let draft = try #require(draftLine)
        guard case .draft(let frame) = SSEParser.frame(from: draft) else { Issue.record("expected draft"); return }
        #expect(frame.messageId == "m1")
        #expect(frame.revision == 3)
        #expect(frame.content == "Hello wor")

        _ = parser.consume("event: draft.removed")
        let removedLine = parser.consume(#"data: {"messageId":"m1","streamId":"s","revision":4}"#)
        let removed = try #require(removedLine)
        guard case .draftRemoved(let id) = SSEParser.frame(from: removed) else { Issue.record("expected removal"); return }
        #expect(id == "m1")
    }

    @Test func heartbeatsAreRecognised() {
        var parser = SSEParser()
        let message = parser.consume(": keep-alive")
        #expect(message.flatMap(SSEParser.frame(from:)).map { if case .heartbeat = $0 { true } else { false } } == true)
    }
}

@MainActor
struct DecodingTests {
    @Test func decodesThreadWithUnknownStatusAndPullRequest() throws {
        let json = #"""
        {"ok":true,"thread":{"id":"t1","projectId":"p1","title":"Fix it","status":"hibernating","waitingOn":[],"blockedOn":[],"pendingWakeups":0,"tasks":[],
         "pullRequests":[{"number":184,"url":"https://github.com/a/b/pull/184","repoFullName":"a/b","state":"open",
          "githubSummary":{"state":"open","checks":{"total":3,"succeeded":2,"failing":1,"running":0},"unresolvedCount":0}}],
         "runStatus":"running","runSteerable":true,"latestRunId":"run_1"}}
        """#
        struct R: Decodable { var thread: AgentThread }
        let thread = try JSONDecoder().decode(R.self, from: Data(json.utf8)).thread
        #expect(thread.status == .unknown)
        #expect(thread.pullRequest?.number == 184)
        #expect(thread.pullRequest?.githubSummary?.checks?.failing == 1)
        #expect(thread.hasLiveRun)
    }

    @Test func messageKindFallsBackForTools() throws {
        let json = #"{"id":"m","threadId":"t","role":"tool","kind":"mystery","content":"Ran ls","createdAt":"2026-10-01T00:00:00Z"}"#
        let message = try JSONDecoder().decode(Message.self, from: Data(json.utf8))
        #expect(message.resolvedKind == .tool)
        #expect(message.created != nil)
    }

    @Test func apiErrorUsesStableCode() {
        let response = HTTPURLResponse(url: URL(string: "https://api.hoplite.sh")!, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "12", "x-request-id": "req_1"])!
        let error = HopliteClient.error(from: Data(#"{"ok":false,"error":"rate_limited"}"#.utf8), response: response)
        #expect(error.code == "rate_limited")
        #expect(error.retryAfter == 12)
        #expect(error.requestId == "req_1")
    }
}

@MainActor
struct RenderingTests {
    @Test func markdownBlocks() {
        let blocks = MarkdownBlock.parse("## Root cause\nThe test raced.\n\n1. Disable button\n2. Wait for enabled\n\n```ts\nawait x()\n```\n\n| A | B |\n|---|---|\n| 1 | 2 |")
        #expect(blocks.count == 5)
        #expect(blocks[0] == .heading(2, "Root cause"))
        #expect(blocks[2] == .list(["Disable button", "Wait for enabled"], ordered: true))
        #expect(blocks[3] == .code("ts", "await x()"))
        #expect(blocks[4] == .table([["A", "B"], ["1", "2"]]))
    }

    @Test func patchLineNumbers() {
        let lines = PatchLine.parse("@@ -10,3 +10,4 @@ fn\n ctx\n-old\n+new\n+added")
        #expect(lines.map(\.kind) == [.hunk, .context, .remove, .add, .add])
        #expect(lines[1].old == 10 && lines[1].new == 10)
        #expect(lines[2].old == 11)
        #expect(lines[3].new == 11)
        #expect(lines[4].new == 12)
    }

    @Test func cronDescriptions() {
        #expect(Automation.describeCron("0 3 * * *").hasPrefix("Daily at"))
        #expect(Automation.describeCron("0 9 * * 1").hasPrefix("Mondays at"))
        #expect(Automation.describeCron("*/5 * * * *") == "*/5 * * * *")
    }
}
