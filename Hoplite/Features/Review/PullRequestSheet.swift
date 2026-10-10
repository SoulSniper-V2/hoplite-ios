import SwiftUI

struct PullRequestSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let threadId: String
    let thread: AgentThread?

    @State private var status: PullRequestStatus?
    @State private var loaded = false
    @State private var error: String?
    @State private var mergeMethod = "squash"
    @State private var merging = false
    @State private var mergeResult: MergeResult?
    @State private var showDiff = false
    @State private var comments: PullRequestComments?
    @State private var reviewLoop: ReviewLoop?
    @State private var showResolved = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let status {
                        header(status)
                        if status.state == "open" { mergeCard(status) }
                        if status.state == "open" { reviewLoopCard }
                        checks(status)
                        if let comments, !(comments.reviewThreads ?? []).isEmpty || !(comments.comments ?? []).isEmpty { reviewThreads(comments) }
                        if let body = status.body, !body.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Eyebrow(text: "Description")
                                MarkdownView(text: body, baseFont: .hpCallout)
                            }
                            .padding(16)
                            .hpCard(radius: 20, fill: HP.surface)
                        }
                    } else if loaded {
                        CreatePullRequestForm(threadId: threadId, defaultTitle: thread?.displayTitle ?? "") { _ in
                            Task { await load() }
                        }
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
                    }
                    if let error { ErrorBanner(message: error) }
                }
                .padding(16)
            }
            .background(HP.canvas)
            .navigationTitle(status.map { "#\($0.number)" } ?? "Pull request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done", systemImage: "checkmark") { dismiss() } }
                if let url = status.flatMap({ URL(string: $0.url) }) {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { openURL(url) } label: { Image(systemName: "arrow.up.right.square") }.accessibilityLabel("Open on GitHub")
                    }
                }
            }
            .task { await load() }
            .refreshable { await load() }
            .sheet(isPresented: $showDiff) { DiffView(threadId: threadId) }
        }
    }

    private func header(_ status: PullRequestStatus) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                stateChip(status)
                Text(status.repoFullName).font(.mono(12)).foregroundStyle(HP.ink3)
            }
            Text(status.title ?? thread?.displayTitle ?? "Pull request").font(.display(24, weight: .medium)).foregroundStyle(HP.ink)
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch").font(.system(size: 11, weight: .semibold)).foregroundStyle(HP.ink3)
                Text(status.headRef ?? "head").font(.mono(12)).foregroundStyle(HP.ink2).lineLimit(1)
                Image(systemName: "arrow.right").font(.system(size: 9, weight: .bold)).foregroundStyle(HP.ink3)
                Text(status.baseRef ?? "main").font(.mono(12)).foregroundStyle(HP.ink2)
            }
            Button { showDiff = true } label: {
                HStack {
                    Text("\(status.changedFiles ?? 0) files").font(.ui(14, weight: .medium)).foregroundStyle(HP.ink)
                    Text("+\(status.additions ?? 0)").font(.mono(13, weight: .medium)).foregroundStyle(HP.addition)
                    Text("−\(status.deletions ?? 0)").font(.mono(13, weight: .medium)).foregroundStyle(HP.deletion)
                    ChangeBlocks(additions: status.additions ?? 0, deletions: status.deletions ?? 0)
                    Spacer()
                    Text("Review").font(.ui(14, weight: .medium)).foregroundStyle(HP.ink2)
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(HP.ink3)
                }
                .padding(14)
                .hpCard(radius: 16, fill: HP.surface)
            }
            .buttonStyle(.plain)
        }
    }

    private func stateChip(_ status: PullRequestStatus) -> some View {
        let (label, color, icon): (String, Color, String) = switch status.state {
        case "merged": ("Merged", HP.merged, "arrow.triangle.merge")
        case "closed": ("Closed", HP.ink3, "xmark.circle")
        default: status.draft == true ? ("Draft", HP.ink2, "circle.dashed") : ("Open", HP.ready, "arrow.triangle.pull")
        }
        return Label(label, systemImage: icon)
            .font(.ui(12.5, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.14), in: .capsule)
    }

    private var checkCounts: (passed: Int, failing: Int, running: Int, total: Int) {
        let checks = status?.checks ?? []
        let failing = checks.filter { ["failure", "timed_out", "cancelled", "action_required"].contains($0.conclusion ?? "") }.count
        let running = checks.filter { $0.status != "completed" }.count
        return (checks.count - failing - running, failing, running, checks.count)
    }

    private func mergeCard(_ status: PullRequestStatus) -> some View {
        let counts = checkCounts
        let blocked = status.mergeable == "conflicting" || counts.failing > 0
        let pending = counts.running > 0
        let headline: String = mergeResult?.merged == true ? "Merged" : status.mergeable == "conflicting" ? "Merge conflicts" : counts.failing > 0 ? "\(counts.failing) check\(counts.failing == 1 ? "" : "s") failing" : pending ? "Checks running · \(counts.passed)/\(counts.total)" : "Ready to merge"
        let tint: Color = blocked ? HP.failed : pending ? HP.waiting : HP.ready
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: blocked ? "xmark.octagon.fill" : pending ? "clock.fill" : "checkmark.seal.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline).font(.ui(17, weight: .semibold)).foregroundStyle(HP.ink)
                    Text(blocked ? "Ask Hoplite to fix it from the thread." : pending ? "You can merge once required checks finish." : "\(counts.total) checks passed · no conflicts with \(status.baseRef ?? "main")")
                        .font(.hpFootnote).foregroundStyle(HP.ink2)
                }
            }
            if mergeResult?.merged != true {
                VStack(spacing: 12) {
                    Menu {
                        Picker("Method", selection: $mergeMethod) {
                            ForEach(status.allowedMergeMethods ?? ["squash", "merge", "rebase"], id: \.self) { Text($0.capitalized).tag($0) }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("\(mergeMethod.capitalized) and merge into \(status.baseRef ?? "main")")
                            Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .bold))
                        }
                        .font(.ui(13.5, weight: .medium))
                        .foregroundStyle(HP.ink2)
                    }
                    SlideToConfirm(label: "Slide to merge", tint: HP.ready, busy: merging, enabled: !(blocked || pending) && status.headSha != nil) {
                        Task { await merge() }
                    }
                }
            } else if let message = mergeResult?.message {
                Text(message).font(.hpFootnote).foregroundStyle(HP.ink2)
            }
        }
        .padding(16)
        .background(tint.opacity(0.08), in: .rect(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(tint.opacity(0.25)))
        .sensoryFeedback(.success, trigger: mergeResult?.merged == true)
    }

    private func checks(_ status: PullRequestStatus) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Eyebrow(text: "Checks")
                Spacer()
                Text("\(checkCounts.passed)/\(checkCounts.total)").font(.mono(12)).foregroundStyle(HP.ink3)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            ForEach(status.checks ?? []) { check in
                Divider().overlay(HP.hairline).padding(.leading, 44)
                HStack(spacing: 12) {
                    checkIcon(check).frame(width: 18)
                    Text(check.name).font(.hpCallout).foregroundStyle(HP.ink)
                    Spacer()
                    if let started = check.startedAt.flatMap(ISO8601.parse) {
                        let end = check.completedAt.flatMap(ISO8601.parse) ?? .now
                        Text(Format.duration(ms: end.timeIntervalSince(started) * 1000)).font(.mono(11.5)).foregroundStyle(HP.ink3)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
            }
            if (status.checks ?? []).isEmpty {
                Text("No checks reported yet.").font(.hpFootnote).foregroundStyle(HP.ink3).padding(16)
            }
        }
        .hpCard(radius: 20, fill: HP.surface)
    }

    @ViewBuilder private func checkIcon(_ check: PRCheck) -> some View {
        if check.status != "completed" {
            StatusGlyph(status: .running, size: 14)
        } else if check.conclusion == "success" || check.conclusion == "neutral" || check.conclusion == "skipped" {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(HP.ready)
        } else {
            Image(systemName: "xmark.circle.fill").foregroundStyle(HP.failed)
        }
    }

    private var reviewLoopCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: Binding(get: { reviewLoop?.enabled == true }, set: { value in Task { await setLoop(enabled: value, autoMerge: reviewLoop?.autoMerge == true) } })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Review loop").font(.ui(15, weight: .semibold)).foregroundStyle(HP.ink)
                    Text(reviewLoop?.enabled == true ? reviewLoop?.statusLabel ?? "" : "Hoplite fixes review comments and failing checks until the PR is green.")
                        .font(.hpCaption).foregroundStyle(HP.ink3)
                }
            }
            .tint(HP.action)
            .accessibilityIdentifier("reviewLoop")
            if reviewLoop?.enabled == true {
                Divider().overlay(HP.hairline)
                Toggle(isOn: Binding(get: { reviewLoop?.autoMerge == true }, set: { value in Task { await setLoop(enabled: true, autoMerge: value) } })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Merge when ready").font(.ui(15, weight: .medium)).foregroundStyle(HP.ink)
                        if let passes = reviewLoop?.passCount, passes > 0 {
                            Text("\(passes) review \(passes == 1 ? "pass" : "passes") so far").font(.hpCaption).foregroundStyle(HP.ink3)
                        }
                    }
                }
                .tint(HP.action)
            }
        }
        .padding(16)
        .hpCard(radius: 20, fill: HP.surface)
    }

    private func reviewThreads(_ comments: PullRequestComments) -> some View {
        let threads = comments.reviewThreads ?? []
        let open = threads.filter { !$0.isResolved }
        let visible = showResolved ? threads : open
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Eyebrow(text: "Review comments")
                Spacer()
                Text(comments.unresolvedCount == 0 ? "All resolved" : "\(comments.unresolvedCount) unresolved")
                    .font(.mono(12)).foregroundStyle(comments.unresolvedCount == 0 ? HP.ready : HP.waiting)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            ForEach(visible) { thread in
                Divider().overlay(HP.hairline)
                ReviewThreadRow(thread: thread)
            }
            ForEach(comments.comments ?? []) { comment in
                Divider().overlay(HP.hairline)
                ReviewCommentRow(comment: comment).padding(16)
            }
            if open.count < threads.count {
                Divider().overlay(HP.hairline)
                Button(showResolved ? "Hide resolved" : "Show \(threads.count - open.count) resolved") { withAnimation(.snappy) { showResolved.toggle() } }
                    .font(.ui(13.5, weight: .medium))
                    .foregroundStyle(HP.ink2)
                    .padding(16)
            }
        }
        .hpCard(radius: 20, fill: HP.surface)
    }

    private func setLoop(enabled: Bool, autoMerge: Bool) async {
        guard let service = app.service else { return }
        let previous = reviewLoop
        withAnimation(.snappy) {
            reviewLoop = reviewLoop ?? ReviewLoop(id: "", pullRequestId: "", enabled: enabled, status: "observing", passCount: 0)
            reviewLoop?.enabled = enabled
            reviewLoop?.autoMerge = autoMerge
        }
        do {
            let updated = try await service.setReviewLoop(threadId: threadId, enabled: enabled, autoMerge: autoMerge)
            withAnimation(.snappy) { reviewLoop = updated }
        } catch {
            withAnimation(.snappy) { reviewLoop = previous }
            self.error = error.localizedDescription
        }
    }

    private func load() async {
        guard let service = app.service else { return }
        async let c = try? service.pullRequestComments(threadId: threadId)
        async let l = try? service.reviewLoop(threadId: threadId)
        do {
            status = try await service.pullRequestStatus(threadId: threadId)
            if let methods = status?.allowedMergeMethods, !methods.contains(mergeMethod), let first = methods.first { mergeMethod = first }
        } catch {
            self.error = error.localizedDescription
        }
        let (fetchedComments, fetchedLoop) = await (c, l)
        comments = fetchedComments ?? nil
        reviewLoop = fetchedLoop ?? nil
        loaded = true
    }

    private func merge() async {
        guard let service = app.service, let sha = status?.headSha else { return }
        merging = true
        defer { merging = false }
        do {
            mergeResult = try await service.mergePullRequest(threadId: threadId, expectedHeadSha: sha, method: mergeMethod)
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct CreatePullRequestForm: View {
    @Environment(AppModel.self) private var app
    let threadId: String
    let defaultTitle: String
    let created: (PullRequest) -> Void
    @State private var title = ""
    @State private var body_ = ""
    @State private var draft = false
    @State private var creating = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: "No pull request yet")
                Text("Open a pull request").font(.display(26, weight: .medium)).foregroundStyle(HP.ink)
                Text("Hoplite commits the workspace, pushes a branch and opens the PR on GitHub. Leave the fields blank to let the agent write them.")
                    .font(.hpCallout).foregroundStyle(HP.ink2)
            }
            VStack(spacing: 0) {
                TextField("Title", text: $title, prompt: Text(defaultTitle))
                    .font(.ui(16, weight: .medium))
                    .padding(14)
                Divider().overlay(HP.hairline)
                TextField("Description (optional)", text: $body_, axis: .vertical)
                    .font(.hpCallout)
                    .lineLimit(4...10)
                    .padding(14)
                Divider().overlay(HP.hairline)
                Toggle("Open as draft", isOn: $draft).font(.hpCallout).padding(.horizontal, 14).padding(.vertical, 8)
            }
            .hpCard(radius: 18, fill: HP.surface)
            if let error { Text(error).font(.hpFootnote).foregroundStyle(HP.failed) }
            Button {
                Task { await create() }
            } label: {
                HStack {
                    if creating { ProgressView().tint(.white) }
                    Text(creating ? "Opening…" : "Create pull request").font(.ui(16, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(HP.action)
            .controlSize(.large)
            .disabled(creating)
        }
    }

    private func create() async {
        guard let service = app.service else { return }
        creating = true
        defer { creating = false }
        do {
            created(try await service.createPullRequest(threadId: threadId, title: title.isEmpty ? nil : title, body: body_, draft: draft))
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Conductor-style slide control for irreversible actions: a deliberate drag, never an accidental tap.
struct SlideToConfirm: View {
    let label: String
    let tint: Color
    let busy: Bool
    let enabled: Bool
    let action: () -> Void

    @State private var offset: CGFloat = 0
    @State private var completed = false
    private let knob: CGFloat = 52

    var body: some View {
        GeometryReader { proxy in
            let track = proxy.size.width - knob - 8
            let progress = track > 0 ? offset / track : 0
            ZStack(alignment: .leading) {
                Capsule().fill(enabled ? tint.opacity(0.18) : HP.control)
                Capsule().fill(tint.opacity(enabled ? 0.85 : 0)).frame(width: offset + knob + 8)
                Text(busy ? "Merging…" : label)
                    .font(.ui(16, weight: .semibold))
                    .foregroundStyle(enabled ? HP.ink : HP.ink3)
                    .opacity(1 - Double(progress) * 1.4)
                    .frame(maxWidth: .infinity)
                    .shimmer(enabled && !busy)
                Circle()
                    .fill(enabled ? tint : HP.ink3.opacity(0.5))
                    .overlay {
                        if busy { ProgressView().tint(.white) } else {
                            Image(systemName: completed ? "checkmark" : "arrow.right").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                        }
                    }
                    .frame(width: knob, height: knob)
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                    .offset(x: 4 + offset)
            }
            .contentShape(Capsule())
            .highPriorityGesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        guard enabled, !busy, !completed, value.startLocation.x <= knob + 24 else { return }
                        offset = min(max(0, value.translation.width), track)
                    }
                    .onEnded { _ in
                        guard enabled, !busy, !completed else { return }
                        if offset > track * 0.85 {
                            withAnimation(.snappy) { offset = track; completed = true }
                            action()
                        } else {
                            withAnimation(.bouncy) { offset = 0 }
                        }
                    }
            )
        }
        .frame(height: knob + 8)
        .sensoryFeedback(.impact(weight: .heavy), trigger: completed) { _, new in new }
        .onChange(of: busy) { _, isBusy in
            if !isBusy, completed { withAnimation(.snappy) { offset = 0; completed = false } }
        }
        .accessibilityElement()
        .accessibilityIdentifier("slideToConfirm")
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if enabled && !busy { action() } }
    }
}

private struct ReviewThreadRow: View {
    let thread: ReviewThread

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let path = thread.path {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text").font(.system(size: 11, weight: .semibold))
                    Text(thread.line.map { "\(path):\($0)" } ?? path).font(.mono(12)).lineLimit(1).truncationMode(.head)
                    Spacer()
                    if thread.isResolved {
                        Text("Resolved").font(.ui(11.5, weight: .semibold)).foregroundStyle(HP.ready)
                    } else if thread.isOutdated {
                        Text("Outdated").font(.ui(11.5, weight: .semibold)).foregroundStyle(HP.ink3)
                    }
                }
                .foregroundStyle(HP.ink3)
            }
            ForEach(thread.comments) { comment in
                ReviewCommentRow(comment: comment)
            }
        }
        .padding(16)
        .opacity(thread.isResolved ? 0.6 : 1)
    }
}

private struct ReviewCommentRow: View {
    let comment: ReviewComment

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Avatar(name: comment.authorLogin ?? "?", size: 22)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(comment.authorLogin ?? "Reviewer").font(.ui(13.5, weight: .semibold)).foregroundStyle(HP.ink)
                    if let date = comment.createdAt.flatMap(ISO8601.parse) {
                        Text(Format.relative(date)).font(.hpCaption).foregroundStyle(HP.ink3)
                    }
                }
                MarkdownView(text: comment.body, baseFont: .ui(14.5))
            }
        }
    }
}
