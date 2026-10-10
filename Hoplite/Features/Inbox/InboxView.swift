import SwiftUI

/// Everything blocked on a human, sorted by urgency: approvals first, then failures, then
/// pull requests that are green and waiting for a merge.
struct InboxView: View {
    @Environment(AppModel.self) private var app
    @State private var resolving: Set<String> = []

    private var failed: [AgentThread] { app.threads.filter { $0.status == .failed } }
    private var readyToMerge: [AgentThread] {
        app.threads.filter { $0.pullRequest?.isReadyToMerge == true }
    }
    private var failingChecks: [AgentThread] {
        app.threads.filter { ($0.pullRequest?.githubSummary?.checks?.failing ?? 0) > 0 || ($0.pullRequest?.githubSummary?.unresolvedCount ?? 0) > 0 }
    }

    private var isEmpty: Bool { app.pendingApprovals.isEmpty && failed.isEmpty && readyToMerge.isEmpty && failingChecks.isEmpty }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26) {
                if isEmpty {
                    EmptyState(icon: "tray", title: "Inbox zero", message: "Approvals, failed runs and pull requests that are ready to merge will land here.")
                        .padding(.top, 60)
                }

                if !app.pendingApprovals.isEmpty {
                    section("Approvals", count: app.pendingApprovals.count, tint: HP.waiting) {
                        ForEach(app.pendingApprovals) { approval in approvalRow(approval) }
                    }
                }
                if !failed.isEmpty {
                    section("Failed runs", count: failed.count, tint: HP.failed) {
                        ForEach(failed) { thread in threadLink(thread, detail: "Run failed", tint: HP.failed) }
                    }
                }
                if !readyToMerge.isEmpty {
                    section("Ready to merge", count: readyToMerge.count, tint: HP.ready) {
                        ForEach(readyToMerge) { thread in
                            threadLink(thread, detail: "All \(thread.pullRequest?.githubSummary?.checks?.total ?? 0) checks passed", tint: HP.ready)
                        }
                    }
                }
                if !failingChecks.isEmpty {
                    section("Needs changes", count: failingChecks.count, tint: HP.waiting) {
                        ForEach(failingChecks) { thread in
                            let summary = thread.pullRequest?.githubSummary
                            threadLink(thread, detail: [summary?.checks?.failing ?? 0 > 0 ? "\(summary?.checks?.failing ?? 0) failing check" : nil, summary?.unresolvedCount ?? 0 > 0 ? "\(summary?.unresolvedCount ?? 0) open comments" : nil].compactMap(\.self).joined(separator: " · "), tint: HP.waiting)
                        }
                    }
                }
            }
            .padding(.horizontal, HP.pageGutter)
            .padding(.bottom, 24)
        }
        .background(HP.canvas)
        .navigationTitle("Inbox")
        .refreshable { await app.refreshThreads() }
    }

    private func section<Content: View>(_ title: String, count: Int, tint: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text(title).font(.ui(14, weight: .semibold)).foregroundStyle(HP.ink)
                Text("\(count)").font(.mono(12)).foregroundStyle(HP.ink3)
            }
            VStack(spacing: 10) { content() }
        }
    }

    private func approvalRow(_ approval: Approval) -> some View {
        let thread = app.thread(approval.threadId)
        return VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: approval.threadId) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(thread?.displayTitle ?? "Thread").font(.ui(15, weight: .semibold)).foregroundStyle(HP.ink).lineLimit(1)
                        Spacer()
                        Text(Format.relative(ISO8601.parse(approval.createdAt))).font(.mono(11.5)).foregroundStyle(HP.ink3)
                    }
                    Text(MarkdownView.inline(approval.summary ?? approval.toolName.map { "Wants to run `\($0)`" } ?? "Wants to continue"))
                        .font(.hpSubhead)
                        .foregroundStyle(HP.ink2)
                        .multilineTextAlignment(.leading)
                    if let project = app.project(thread?.projectId) {
                        MetaChip(icon: "folder", text: project.name)
                    }
                }
            }
            .buttonStyle(.plain)
            HStack(spacing: 10) {
                Button { Task { await resolve(approval, approved: false) } } label: { Text("Deny").frame(maxWidth: .infinity) }
                    .buttonStyle(.glass)
                Button { Task { await resolve(approval, approved: true) } } label: {
                    HStack {
                        if resolving.contains(approval.id) { ProgressView().tint(.white) }
                        Text("Approve")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(HP.action)
            }
            .font(.ui(15, weight: .semibold))
            .disabled(resolving.contains(approval.id))
        }
        .padding(16)
        .hpCard(radius: 22)
        .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .trailing).combined(with: .opacity)))
    }

    private func threadLink(_ thread: AgentThread, detail: String, tint: Color) -> some View {
        NavigationLink(value: thread.id) {
            HStack(spacing: 12) {
                StatusGlyph(status: thread.status, size: 18)
                VStack(alignment: .leading, spacing: 4) {
                    Text(thread.displayTitle).font(.ui(15, weight: .medium)).foregroundStyle(HP.ink).lineLimit(1)
                    HStack(spacing: 6) {
                        Text(detail).font(.hpFootnote).foregroundStyle(tint)
                        if let pr = thread.pullRequest { PRBadge(pr: pr) }
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(HP.ink3)
            }
            .padding(14)
            .hpCard(radius: 20)
        }
        .buttonStyle(.plain)
    }

    private func resolve(_ approval: Approval, approved: Bool) async {
        guard let service = app.service else { return }
        resolving.insert(approval.id)
        defer { resolving.remove(approval.id) }
        do {
            try await service.resolveApproval(threadId: approval.threadId, approvalId: approval.id, approved: approved, reason: nil)
            withAnimation(.snappy) { app.pendingApprovals.removeAll { $0.id == approval.id } }
            await app.refreshThreads()
        } catch {
            app.lastError = error.localizedDescription
        }
    }
}
