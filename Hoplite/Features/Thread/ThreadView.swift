import SwiftUI

struct ThreadView: View {
    @Environment(AppModel.self) private var app
    let threadId: String
    @State private var model: ThreadModel?

    var body: some View {
        Group {
            if let model {
                ThreadContent(model: model)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).background(HP.canvas)
            }
        }
        .task(id: threadId) {
            guard let service = app.service else { return }
            if model == nil {
                model = ThreadModel(threadId: threadId, service: service) { [app] thread in app.replace(thread) }
            }
            await model?.start()
        }
        .onAppear { app.openThreadId = threadId }
        .onDisappear {
            if app.openThreadId == threadId { app.openThreadId = nil }
            model?.stopStreaming()
        }
    }
}

private struct ThreadContent: View {
    @Environment(AppModel.self) private var app
    @Bindable var model: ThreadModel
    @State private var draft = ""
    @State private var selectedModel: String?
    @State private var sheet: ThreadSheet?
    @State private var renaming = false
    @State private var newTitle = ""
    @State private var position = ScrollPosition(idType: String.self)
    @State private var viewportHeight: CGFloat = 0
    @State private var attachments: [PendingAttachment] = []
    @State private var atBottom = true

    enum ThreadSheet: Identifiable {
        case diff, pullRequest, info, preview
        var id: Self { self }
    }

    private var thread: AgentThread? { model.thread }

    var body: some View {
        Group {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let thread { ThreadHeader(thread: thread) { sheet = .pullRequest } }

                    ForEach(model.timeline) { item in
                        TimelineRow(item: item, live: model.isLive && item.id == model.timeline.last?.id, images: model.sentImages)
                            .id(item.id)
                    }

                    if let thread, thread.isPreparing { PreparingCard(phase: thread.initializationPhase) }

                    if model.isWorking, thread?.isPreparing != true {
                        WorkingIndicator(activity: model.currentActivity)
                            .transition(.opacity)
                    }

                    if let thread, thread.status == .failed {
                        FailureCard(failure: model.failure) { Task { await model.retry() } }
                    }

                    if let error = model.error {
                        ErrorBanner(message: error) { model.error = nil; Task { await model.reload() } }
                    }

                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, HP.pageGutter)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .frame(minHeight: viewportHeight, alignment: .top)
            }
            .defaultScrollAnchor(.bottom)
            .scrollPosition($position)
            .onScrollGeometryChange(for: CGFloat.self, of: { $0.containerSize.height }) { _, height in
                viewportHeight = height
            }
            .onScrollGeometryChange(for: Bool.self, of: { $0.contentOffset.y + $0.contentInsets.top + $0.containerSize.height >= $0.contentSize.height - 80 }) { _, bottom in
                withAnimation(.snappy) { atBottom = bottom }
            }
            .scrollDismissesKeyboard(.interactively)
            .background(HP.canvas)
            .onChange(of: model.timeline.count) { withAnimation(.snappy) { position.scrollTo(edge: .bottom) } }
            .onChange(of: model.drafts.values.map(\.revision).max()) { position.scrollTo(edge: .bottom) }
            .safeAreaBar(edge: .bottom) {
                VStack(spacing: 10) {
                    if !atBottom {
                        Button {
                            withAnimation(.snappy) { position.scrollTo(edge: .bottom) }
                        } label: {
                            Image(systemName: "arrow.down").font(.system(size: 14, weight: .semibold)).foregroundStyle(HP.ink).frame(width: 40, height: 40)
                        }
                        .glassEffect(.regular.interactive(), in: .circle)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .accessibilityLabel("Jump to latest")
                        .transition(.scale.combined(with: .opacity))
                    }
                    if model.approvals.isEmpty, let thread, thread.status == .running, !thread.isPreparing {
                        WorkingPill(startedAt: thread.runStartedAt.flatMap(ISO8601.parse), stopping: thread.stopRequestedAt != nil)
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }
                    if model.approvals.isEmpty, let pr = thread?.pullRequest, pr.isReadyToMerge, thread?.hasLiveRun != true {
                        ReadyToMergeBar(pr: pr) { sheet = .pullRequest }
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    if !model.approvals.isEmpty {
                        ApprovalCard(approvals: model.approvals, summaries: model.approvalSummaries) { approval, approved in
                            Task { await model.resolve(approval, approved: approved) }
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    Composer(
                        text: $draft,
                        selectedModel: $selectedModel,
                        attachments: $attachments,
                        thread: thread,
                        sending: model.sending,
                        onSend: send,
                        onStop: { Task { await model.stop() } },
                        onCommand: run
                    )
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
                .animation(.snappy, value: model.approvals.count)
                .animation(.snappy, value: thread?.status)
                .animation(.snappy, value: atBottom)
            }
        }
        .navigationTitle(thread?.displayTitle ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .tabBar)
        .toolbar { toolbar }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .diff: DiffView(threadId: model.threadId)
            case .pullRequest: PullRequestSheet(threadId: model.threadId, thread: thread)
            case .info: ThreadInfoSheet(threadId: model.threadId, thread: thread) { await model.reload() }
            case .preview: PreviewSheet(threadId: model.threadId)
            }
        }
        .alert("Rename thread", isPresented: $renaming) {
            TextField("Title", text: $newTitle)
            Button("Save") { Task { await model.rename(newTitle) } }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear {
            if selectedModel == nil { selectedModel = thread?.modelId }
            #if DEBUG
            sheet = ["diff": .diff, "pr": .pullRequest, "info": .info][UserDefaults.standard.string(forKey: "UITestSheet") ?? ""]
            if let text = UserDefaults.standard.string(forKey: "UITestDraft") { draft = text }
            #endif
        }
        .onChange(of: thread?.modelId) { if selectedModel == nil { selectedModel = thread?.modelId } }
        .sensoryFeedback(.success, trigger: thread?.status == .ready)
        .sensoryFeedback(.warning, trigger: model.approvals.count) { old, new in new > old }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { sheet = .diff } label: { Image(systemName: "plus.forwardslash.minus").foregroundStyle(HP.ink) }
                .accessibilityLabel("Changes")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { sheet = .pullRequest } label: {
                    Label(thread?.pullRequest.map { "Pull request #\($0.number)" } ?? "Create pull request", systemImage: "arrow.triangle.pull")
                }
                Button { sheet = .preview } label: { Label("Preview", systemImage: "safari") }
                Button { sheet = .info } label: { Label("Details & checkpoints", systemImage: "gauge.with.dots.needle.33percent") }
                Divider()
                if model.thread?.hasLiveRun == true {
                    Button(role: .destructive) { Task { await model.stop() } } label: { Label("Stop run", systemImage: "stop.circle") }
                } else {
                    Button { Task { await model.retry() } } label: { Label("Retry", systemImage: "arrow.clockwise") }
                }
                Button { Task { await model.compact() } } label: { Label("Compact context", systemImage: "rectangle.compress.vertical") }
                Button { newTitle = thread?.title ?? ""; renaming = true } label: { Label("Rename", systemImage: "pencil") }
                Divider()
                Button { Task { await model.setArchived(thread?.status != .archived) } } label: {
                    Label(thread?.status == .archived ? "Unarchive" : "Archive", systemImage: "archivebox")
                }
            } label: {
                Image(systemName: "ellipsis").foregroundStyle(HP.ink)
            }
            .accessibilityLabel("Thread actions")
        }
    }

    private func send() {
        let text = draft
        let images = attachments
        draft = ""
        attachments = []
        Task {
            if await !model.send(text, model: selectedModel == thread?.modelId ? nil : selectedModel, attachments: images) {
                draft = text
                attachments = images
            }
        }
    }

    private func run(_ command: SlashCommand, _ argument: String) {
        switch command {
        case .pr: sheet = .pullRequest
        case .model: break
        case .retry: Task { await model.retry() }
        case .stop: Task { await model.stop() }
        case .compact: Task { await model.compact() }
        case .rename:
            if argument.isEmpty { newTitle = thread?.title ?? ""; renaming = true } else { Task { await model.rename(argument) } }
        case .archive: Task { await model.setArchived(true) }
        }
    }

}

// MARK: Header

private struct ThreadHeader: View {
    @Environment(AppModel.self) private var app
    let thread: AgentThread
    let openPR: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(thread.displayTitle)
                .font(.display(26, weight: .medium))
                .tracking(-0.5)
                .foregroundStyle(HP.ink)
                .fixedSize(horizontal: false, vertical: true)
            FlowRow {
                StatusPill(status: thread.status)
                if let project = app.project(thread.projectId) {
                    MetaChip(icon: "folder", text: project.repos?.first?.display ?? project.name)
                }
                if let name = app.modelName(thread.modelId) { MetaChip(icon: "cpu", asset: Provider.logo(app.catalog?.model(thread.modelId)?.provider, model: thread.modelId), text: name) }
                if let pr = thread.pullRequest {
                    Button(action: openPR) { PRBadge(pr: pr) }.buttonStyle(.plain)
                }
            }
        }
        .padding(.bottom, 6)
    }
}

/// Wraps chips onto multiple lines.
struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: Timeline rows

private struct TimelineRow: View {
    let item: TimelineItem
    let live: Bool
    let images: [String: [UIImage]]

    var body: some View {
        switch item {
        case .user(let message): UserBubble(message: message, images: message.attachments.isEmpty ? images[message.content] ?? [] : [])
        case .assistant(let message): AssistantMessage(message: message)
        case .thinking(let message): ThinkingRow(text: message.content)
        case .status(let message): StatusDivider(text: message.content)
        case .activity(_, let tools): ActivityGroup(tools: tools, live: live)
        case .draft(let draft): DraftView(draft: draft)
        }
    }
}

/// Agent prose sits directly on the page, as in Hoplite's web thread; long-press to copy or share.
private struct AssistantMessage: View {
    let message: Message
    @State private var copied = false

    var body: some View {
        MarkdownView(text: message.content)
            .transition(.opacity)
            .contextMenu {
                Button {
                    UIPasteboard.general.string = message.content
                } label: { Label("Copy", systemImage: "doc.on.doc") }
                ShareLink(item: message.content) { Label("Share", systemImage: "square.and.arrow.up") }
                if let date = message.created {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                }
            }
    }
}

private struct UserBubble: View {
    let message: Message
    let images: [UIImage]

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if let author = message.author, author.id != "user_demo" {
                HStack(spacing: 6) {
                    Avatar(name: author.name, size: 16)
                    Text(author.name).font(.hpCaption).foregroundStyle(HP.ink2)
                }
            }
            if !message.attachments.isEmpty {
                HStack(spacing: 6) {
                    ForEach(message.attachments, id: \.artifactId) { attachment in
                        AttachmentThumbnail(threadId: message.threadId, attachment: attachment, large: message.attachments.count == 1)
                    }
                }
            }
            if !images.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(images.enumerated()), id: \.offset) { _, image in
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: images.count == 1 ? 180 : 92, height: images.count == 1 ? 130 : 92)
                            .clipShape(.rect(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(HP.hairline))
                    }
                }
            }
            Text(MarkdownView.inline(message.content))
                .font(.ui(16))
                .foregroundStyle(HP.ink)
                .lineSpacing(3)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(HP.bubble, in: .rect(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(HP.hairline))
                .opacity(message.id.hasPrefix("local-") ? 0.6 : 1)
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = message.content
                    } label: { Label("Copy", systemImage: "doc.on.doc") }
                    if let date = message.created {
                        Text("Sent \(date.formatted(date: .abbreviated, time: .shortened))")
                    }
                }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, 48)
        .padding(.top, 10)
    }
}

/// An image attached to a sent message, fetched once through the attachment endpoint and cached for the session.
private struct AttachmentThumbnail: View {
    @Environment(AppModel.self) private var app
    let threadId: String
    let attachment: MessageAttachment
    let large: Bool
    @State private var image: UIImage?
    @State private var showFull = false

    @MainActor private static var cache: [String: UIImage] = [:]

    var body: some View {
        Button { showFull = image != nil } label: {
            ZStack {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    HP.surface
                    Image(systemName: "photo").foregroundStyle(HP.ink3)
                }
            }
            .frame(width: large ? 180 : 92, height: large ? 130 : 92)
            .clipShape(.rect(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(HP.hairline))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(attachment.name ?? "Attached image")
        .task(id: attachment.artifactId) {
            if let cached = Self.cache[attachment.artifactId] { image = cached; return }
            guard let data = try? await app.service?.attachmentData(threadId: threadId, artifactId: attachment.artifactId), let loaded = UIImage(data: data) else { return }
            Self.cache[attachment.artifactId] = loaded
            withAnimation(.easeOut(duration: 0.2)) { image = loaded }
        }
        .fullScreenCover(isPresented: $showFull) {
            ZStack(alignment: .topTrailing) {
                Color.black.ignoresSafeArea()
                if let image { Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity) }
                Button { showFull = false } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).frame(width: 40, height: 40)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .padding()
            }
        }
    }
}

private struct ThinkingRow: View {
    let text: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkle").font(.system(size: 11, weight: .semibold))
                    Text("Reasoning").font(.ui(14, weight: .medium))
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .foregroundStyle(HP.ink3)
            }
            .buttonStyle(.plain)
            if expanded {
                Text(MarkdownView.inline(text))
                    .font(.ui(15).italic())
                    .foregroundStyle(HP.ink2)
                    .lineSpacing(3)
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) { Rectangle().fill(HP.hairlineStrong).frame(width: 2) }
                    .transition(.opacity)
            }
        }
    }
}

private struct StatusDivider: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(HP.hairline).frame(height: 1)
            Text(MarkdownView.inline(text)).font(.hpCaption).foregroundStyle(HP.ink3).multilineTextAlignment(.center).layoutPriority(1)
            Rectangle().fill(HP.hairline).frame(height: 1)
        }
        .padding(.vertical, 4)
    }
}

private struct DraftView: View {
    let draft: DraftFrame

    var body: some View {
        MarkdownView(text: draft.content + " ▍")
            .transaction { $0.animation = nil }
    }
}

enum ToolStyle {
    static func icon(_ name: String?) -> String {
        let name = name?.lowercased() ?? ""
        if name.contains("read") || name.contains("view") || name.contains("open") { return "doc.text" }
        if name.contains("edit") || name.contains("write") || name.contains("patch") || name.contains("create") { return "pencil" }
        if name.contains("shell") || name.contains("bash") || name.contains("exec") || name.contains("command") || name.contains("run") { return "terminal" }
        if name.contains("search") || name.contains("grep") || name.contains("find") || name.contains("glob") { return "magnifyingglass" }
        if name.contains("github") || name.contains("git") || name.contains("pr") { return "arrow.triangle.pull" }
        if name.contains("browser") || name.contains("web") || name.contains("fetch") { return "globe" }
        if name.contains("sentry") { return "ladybug" }
        if name.contains("linear") || name.contains("issue") { return "checklist" }
        return "wrench.and.screwdriver"
    }

    static func verb(_ name: String?) -> String {
        switch icon(name) {
        case "doc.text": "read"
        case "pencil": "edit"
        case "terminal": "command"
        case "magnifyingglass": "search"
        case "arrow.triangle.pull": "git"
        default: "other"
        }
    }

    static func summary(_ tools: [Message]) -> String {
        let counts = Dictionary(grouping: tools, by: { verb($0.toolName) }).mapValues(\.count)
        var parts: [String] = []
        if let n = counts["read"] { parts.append("read \(n) file\(n == 1 ? "" : "s")") }
        if let n = counts["search"] { parts.append("\(n) search\(n == 1 ? "" : "es")") }
        if let n = counts["edit"] { parts.append("edited \(n) file\(n == 1 ? "" : "s")") }
        if let n = counts["command"] { parts.append("ran \(n) command\(n == 1 ? "" : "s")") }
        if let n = counts["git"] { parts.append("\(n) git action\(n == 1 ? "" : "s")") }
        if let n = counts["other"] { parts.append("\(n) tool call\(n == 1 ? "" : "s")") }
        return parts.joined(separator: ", ").capitalizedFirst
    }
}

/// Consecutive tool calls fold into one quiet, expandable line, so long runs stay scannable.
private struct ActivityGroup: View {
    let tools: [Message]
    let live: Bool
    @State private var expanded: Bool?

    private var isExpanded: Bool { expanded ?? live }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                withAnimation(.snappy) { expanded = !isExpanded }
            } label: {
                HStack(spacing: 6) {
                    Text("Activity").font(.ui(15, weight: .medium)).foregroundStyle(HP.ink2)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(HP.ink3)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    if !isExpanded {
                        Text(ToolStyle.summary(tools)).font(.ui(13.5)).foregroundStyle(HP.ink3).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(HP.ink3)
                .padding(.vertical, 4)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(tools) { tool in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: ToolStyle.icon(tool.toolName))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(HP.ink3)
                                .frame(width: 16)
                            Text(MarkdownView.inline(tool.content.split(separator: "\n").first.map(String.init) ?? tool.toolName ?? "Tool call"))
                                .font(.hpSubhead)
                                .foregroundStyle(HP.ink2)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 5)
                    }
                }
                .padding(.leading, 8)
                .overlay(alignment: .leading) { Rectangle().fill(HP.hairlineStrong).frame(width: 1).padding(.vertical, 4) }
                .transition(.opacity)
            }
        }
        .clipped()
    }
}

private struct WorkingIndicator: View {
    let activity: ActivityItem?

    var body: some View {
        HStack(spacing: 10) {
            StatusGlyph(status: .running, size: 14)
            Text(MarkdownView.inline(activity?.description ?? "Thinking…"))
                .font(.ui(14.5, weight: .medium))
                .foregroundStyle(HP.ink2)
                .lineLimit(1)
                .shimmer()
                .id(activity?.id)
                .transition(.push(from: .bottom))
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
        }
        .animation(.snappy, value: activity?.id)
        .padding(.vertical, 4)
    }
}

private struct PreparingCard: View {
    let phase: String?
    private let phases = ["provisioning_workspace", "resolving_repository", "allocating_sandbox", "fetching_repository", "configuring_workspace", "dispatching_run"]

    var body: some View {
        let current = phases.firstIndex(of: phase ?? "") ?? 0
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: "Preparing cloud workspace")
            ForEach(Array(phases.enumerated()), id: \.offset) { index, item in
                HStack(spacing: 10) {
                    ZStack {
                        if index < current {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(HP.ready)
                        } else if index == current {
                            StatusGlyph(status: .running, size: 15)
                        } else {
                            Circle().stroke(HP.ink3.opacity(0.5), lineWidth: 1.5).frame(width: 14, height: 14)
                        }
                    }
                    .frame(width: 18)
                    Text(phaseLabel(item))
                        .font(.hpSubhead)
                        .foregroundStyle(index <= current ? HP.ink : HP.ink3)
                        .shimmer(index == current)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hpCard(radius: 20, fill: HP.surface)
        .animation(.snappy, value: current)
    }
}

private struct FailureCard: View {
    let failure: RunFailure?
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                StatusGlyph(status: .failed, size: 16)
                Text("Run failed").font(.ui(16, weight: .semibold)).foregroundStyle(HP.ink)
            }
            Text(failure?.message ?? "The last run stopped before finishing.").font(.hpSubhead).foregroundStyle(HP.ink2)
            if let code = failure?.code { Text(code).font(.mono(11.5)).foregroundStyle(HP.ink3) }
            Button(action: retry) {
                Label("Retry in the same workspace", systemImage: "arrow.clockwise").font(.ui(14, weight: .semibold))
            }
            .buttonStyle(.glass)
            .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HP.failed.opacity(0.08), in: .rect(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(HP.failed.opacity(0.3)))
    }
}

// MARK: Approvals

struct ApprovalCard: View {
    let approvals: [Approval]
    let summaries: [String: String]
    let resolve: (Approval, Bool) -> Void

    var body: some View {
        if let approval = approvals.first {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(HP.action, in: .circle)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Eyebrow(text: "Approval needed", color: HP.action)
                            Spacer()
                            if approvals.count > 1 { Text("1 of \(approvals.count)").font(.mono(11)).foregroundStyle(HP.ink3) }
                        }
                        Text(MarkdownView.inline(summaries[approval.id] ?? "Continue the run"))
                            .font(.ui(15, weight: .medium))
                            .foregroundStyle(HP.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if let tool = approval.toolName { Text(tool).font(.mono(11.5)).foregroundStyle(HP.ink3) }
                    }
                }
                HStack(spacing: 10) {
                    Button { resolve(approval, false) } label: {
                        Text("Deny").font(.ui(15, weight: .semibold)).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    Button { resolve(approval, true) } label: {
                        Text("Approve").font(.ui(15, weight: .semibold)).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(HP.action)
                }
                .controlSize(.large)
            }
            .padding(14)
            .background(HP.raised, in: .rect(cornerRadius: 26, style: .continuous))
            .background(HP.action.opacity(0.10), in: .rect(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(HP.action.opacity(0.45), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
            .sensoryFeedback(.impact, trigger: approvals.count)
        }
    }
}

private struct ReadyToMergeBar: View {
    let pr: PullRequest
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(HP.ready)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Ready to merge").font(.ui(14.5, weight: .semibold)).foregroundStyle(HP.ink)
                    Text("#\(pr.number) · \(pr.githubSummary?.checks?.total ?? 0) checks passed").font(.ui(12)).foregroundStyle(HP.ink2)
                }
                Spacer()
                Text("Review").font(.ui(14, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(HP.ready, in: .capsule)
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pull request \(pr.number) is ready to merge. Review")
    }
}

/// Codex/T3-style floating timer above the composer while a run is active.
private struct WorkingPill: View {
    let startedAt: Date?
    let stopping: Bool

    var body: some View {
        HStack(spacing: 8) {
            StatusGlyph(status: .running, size: 13)
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(stopping ? "Stopping…" : "Working \(Format.elapsed(since: startedAt))")
                    .font(.ui(14, weight: .medium))
                    .foregroundStyle(HP.ink)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .combine)
    }
}
