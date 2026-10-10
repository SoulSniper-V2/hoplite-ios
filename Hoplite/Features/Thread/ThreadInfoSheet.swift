import SwiftUI
import WebKit

struct ThreadInfoSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let threadId: String
    let thread: AgentThread?
    var onChanged: () async -> Void = {}

    @State private var usage: ThreadUsage?
    @State private var checkpoints: [Checkpoint] = []
    @State private var recovery: WorkspaceRecovery?
    @State private var spendLimit: Int?
    @State private var restoring: Checkpoint?
    @State private var busy: String?
    @State private var confirmReset = false
    @State private var transcript: TranscriptFile?
    @State private var error: String?

    private static let limits: [(Int?, String)] = [(nil, "No limit"), (2_000_000, "$2"), (5_000_000, "$5"), (10_000_000, "$10"), (25_000_000, "$25"), (50_000_000, "$50")]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    spendCard
                    if let error {
                        Label(error, systemImage: "exclamationmark.circle.fill").font(.hpFootnote).foregroundStyle(HP.failed).padding(.horizontal, 4)
                    }
                    if let tasks = thread?.tasks, !tasks.isEmpty { subagents(tasks) }
                    checkpointsCard
                    if let recovery { workspaceCard(recovery) }
                    if let thread { identifiers(thread) }
                }
                .padding(16)
            }
            .background(HP.canvas)
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if let transcript {
                        ShareLink(item: transcript, preview: SharePreview(transcript.name)) { Image(systemName: "square.and.arrow.up") }
                            .accessibilityLabel("Export transcript")
                    } else {
                        ProgressView()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { Button("Done", systemImage: "checkmark") { dismiss() } }
            }
            .task { await load() }
            .confirmationDialog("Restore this checkpoint?", isPresented: Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } }), titleVisibility: .visible, presenting: restoring) { checkpoint in
                Button("Restore workspace") { Task { await restore(checkpoint) } }
            } message: { checkpoint in
                Text("The workspace files return to \(checkpoint.gitCommitSha.map { "commit " + String($0.prefix(7)) } ?? "this point"). The conversation stays as it is.")
            }
            .confirmationDialog("Reset the workspace?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset and discard changes", role: .destructive) { Task { await recover(reset: true) } }
            } message: {
                Text("Uncommitted work in the sandbox is lost. The thread and its pull request are kept.")
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Sections

    private var spendCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Eyebrow(text: "Spend")
                Spacer()
                Menu {
                    Picker("Spend limit", selection: Binding(get: { spendLimit }, set: { value in Task { await setLimit(value) } })) {
                        ForEach(Self.limits, id: \.1) { Text($0.1).tag($0.0) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(spendLimit.map { "Limit " + Format.dollars(micros: Double($0)) } ?? "Set limit").font(.ui(13, weight: .medium))
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(HP.ink2)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(HP.control.opacity(0.7), in: .capsule)
                }
                .accessibilityLabel("Spend limit")
            }
            if let usage {
                HStack(alignment: .firstTextBaseline) {
                    Text(Format.dollars(micros: usage.totalCostMicros)).font(.display(40, weight: .medium)).foregroundStyle(HP.ink).contentTransition(.numericText())
                    if let limit = spendLimit {
                        Text("of \(Format.dollars(micros: Double(limit)))").font(.hpCallout).foregroundStyle(HP.ink3)
                    }
                }
                if let limit = spendLimit, limit > 0 {
                    let fraction = min((usage.totalCostMicros ?? 0) / Double(limit), 1)
                    ProgressView(value: fraction).tint(fraction > 0.85 ? HP.waiting : HP.action)
                }
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    stat("Model", Format.dollars(micros: usage.llmCostMicros), "Sandbox", Format.dollars(micros: usage.vmCostMicros))
                    stat("Input", Format.tokens(usage.inputTokens), "Output", Format.tokens(usage.outputTokens))
                    stat("Context", Format.tokens(usage.latestContextTokens), "Runtime", Format.duration(ms: usage.runtimeMs ?? 0))
                }
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(24)
            }
        }
        .padding(18)
        .hpCard(radius: 22, fill: HP.surface)
    }

    private func subagents(_ tasks: [ThreadTask]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: "Subagents").padding(16)
            ForEach(tasks, id: \.id) { task in
                Divider().overlay(HP.hairline)
                HStack(spacing: 12) {
                    HopliteGlyph(status: glyph(task.status), size: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.title ?? task.identifier ?? "Subagent").font(.hpCallout).foregroundStyle(HP.ink).lineLimit(1)
                        Text([task.identifier, task.status?.replacingOccurrences(of: "_", with: " ").capitalized].compactMap(\.self).joined(separator: " · ")).font(.hpCaption).foregroundStyle(HP.ink3)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .hpCard(radius: 22, fill: HP.surface)
    }

    private var checkpointsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: "Checkpoints").padding(16)
            if checkpoints.isEmpty {
                Text("Checkpoints appear after each run.").font(.hpFootnote).foregroundStyle(HP.ink3).padding([.horizontal, .bottom], 16)
            }
            ForEach(checkpoints) { checkpoint in
                Divider().overlay(HP.hairline)
                HStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath").foregroundStyle(HP.ink3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(checkpoint.label ?? "Checkpoint").font(.hpCallout).foregroundStyle(HP.ink).lineLimit(1)
                        HStack(spacing: 6) {
                            if let sha = checkpoint.gitCommitSha { Text(String(sha.prefix(7))).font(.mono(11.5)).foregroundStyle(HP.ink3) }
                            Text(Format.relative(ISO8601.parse(checkpoint.createdAt))).font(.hpCaption).foregroundStyle(HP.ink3)
                        }
                    }
                    Spacer(minLength: 8)
                    if busy == checkpoint.id {
                        ProgressView()
                    } else {
                        Button("Restore") { restoring = checkpoint }
                            .font(.ui(13, weight: .semibold))
                            .foregroundStyle(HP.ink)
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background(HP.control, in: .capsule)
                            .buttonStyle(.plain)
                            .disabled(thread?.hasLiveRun == true || busy != nil)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .hpCard(radius: 22, fill: HP.surface)
    }

    private func workspaceCard(_ recovery: WorkspaceRecovery) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: "Workspace")
            HStack(spacing: 10) {
                HopliteGlyph(status: recovery.bricked ? "failed" : "ready", size: 20, animated: false)
                VStack(alignment: .leading, spacing: 2) {
                    Text(recovery.bricked ? "The sandbox can't start" : "Sandbox healthy").font(.hpCallout).foregroundStyle(HP.ink)
                    Text(recovery.bricked ? "Restore the last snapshot, or reset to a clean checkout of the branch." : "Recovery is available if the sandbox gets stuck.").font(.hpCaption).foregroundStyle(HP.ink3)
                }
            }
            if busy == "recovery" {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                HStack(spacing: 8) {
                    if recovery.canRestoreSnapshot {
                        Button { Task { await recover(reset: false) } } label: {
                            Text("Restore snapshot").font(.ui(14, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 40)
                        }
                        .foregroundStyle(recovery.bricked ? .white : HP.ink)
                        .background(recovery.bricked ? HP.action : HP.control, in: .rect(cornerRadius: 12, style: .continuous))
                    }
                    if recovery.canReset {
                        Button { confirmReset = true } label: {
                            Text("Reset").font(.ui(14, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 40)
                        }
                        .foregroundStyle(HP.failed)
                        .background(HP.control, in: .rect(cornerRadius: 12, style: .continuous))
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .hpCard(radius: 22, fill: HP.surface)
    }

    private func identifiers(_ thread: AgentThread) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "Identifiers")
            LabeledContent("Thread", value: thread.id)
            if let run = thread.latestRunId { LabeledContent("Latest run", value: run) }
        }
        .font(.mono(12))
        .foregroundStyle(HP.ink2)
        .padding(16)
        .hpCard(radius: 22, fill: HP.surface)
        .textSelection(.enabled)
    }

    private func stat(_ l1: String, _ v1: String, _ l2: String, _ v2: String) -> some View {
        GridRow {
            VStack(alignment: .leading, spacing: 2) { Text(l1).font(.hpCaption).foregroundStyle(HP.ink3); Text(v1).font(.mono(15, weight: .medium)).foregroundStyle(HP.ink) }
            VStack(alignment: .leading, spacing: 2) { Text(l2).font(.hpCaption).foregroundStyle(HP.ink3); Text(v2).font(.mono(15, weight: .medium)).foregroundStyle(HP.ink) }
        }
    }

    private func glyph(_ status: String?) -> String {
        switch status {
        case "running", "in_progress", "queued": "running"
        case "blocked", "waiting", "needs_input": "blocked"
        case "failed", "error", "cancelled": "failed"
        default: "ready"
        }
    }

    // MARK: Actions

    private func load() async {
        guard let service = app.service else { return }
        spendLimit = thread?.spendLimitMicros
        async let u = try? service.usage(threadId: threadId)
        async let c = (try? service.checkpoints(threadId: threadId)) ?? []
        async let r = try? service.workspaceRecovery(threadId: threadId)
        async let t = try? service.exportTranscript(threadId: threadId)
        let (usage, checkpoints, recovery, markdown) = await (u, c, r, t)
        withAnimation(.snappy) {
            self.usage = usage
            self.checkpoints = checkpoints
            self.recovery = recovery
            if spendLimit == nil { spendLimit = usage?.spendLimitMicros }
        }
        if let markdown { transcript = TranscriptFile(name: (thread?.displayTitle ?? "Thread") + ".md", markdown: markdown) }
    }

    private func setLimit(_ value: Int?) async {
        guard let service = app.service, let thread else { return }
        let previous = spendLimit
        spendLimit = value
        do {
            app.replace(try await service.setSpendLimit(thread, micros: value))
            usage = try? await service.usage(threadId: threadId)
        } catch {
            spendLimit = previous
            self.error = error.localizedDescription
        }
    }

    private func restore(_ checkpoint: Checkpoint) async {
        guard let service = app.service else { return }
        busy = checkpoint.id
        defer { busy = nil }
        do {
            try await service.restoreCheckpoint(threadId: threadId, checkpointId: checkpoint.id)
            await onChanged()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func recover(reset: Bool) async {
        guard let service = app.service else { return }
        busy = "recovery"
        defer { busy = nil }
        do {
            let result = try await service.recoverWorkspace(threadId: threadId, reset: reset)
            withAnimation(.snappy) { recovery = result }
            await onChanged()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// The exported markdown transcript, shared as a `.md` file.
struct TranscriptFile: Transferable {
    let name: String
    let markdown: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { file in
            let url = FileManager.default.temporaryDirectory.appending(path: file.name.replacingOccurrences(of: "/", with: "-"))
            try Data(file.markdown.utf8).write(to: url)
            return SentTransferredFile(url)
        }
    }
}

struct PreviewSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let threadId: String
    @State private var preview: Preview?
    @State private var starting = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if let preview, preview.status == "ready", let url = preview.url.flatMap(URL.init(string:)) {
                    PreviewWebView(url: url, gateway: preview.gateway).ignoresSafeArea(edges: .bottom)
                } else {
                    VStack {
                        EmptyState(
                            icon: "safari",
                            title: preview?.status == "starting" || starting ? "Starting preview…" : "Preview isn't running",
                            message: preview?.reason ?? "Hoplite runs the project's run script in the sandbox and serves it through a private gateway.",
                            action: starting ? nil : ("Start preview", { Task { await start() } })
                        )
                        if let error { Text(error).font(.hpFootnote).foregroundStyle(HP.failed) }
                    }
                    .frame(maxHeight: .infinity)
                }
            }
            .background(HP.canvas)
            .navigationTitle(preview?.name ?? "Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done", systemImage: "checkmark") { dismiss() } } }
            .task { await refresh() }
        }
    }

    private func start() async {
        guard let service = app.service else { return }
        starting = true
        defer { starting = false }
        do {
            preview = try await service.startPreview(threadId: threadId)
            await refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Ready previews sit behind a private gateway, so fetch a short-lived access token before loading.
    private func refresh() async {
        guard let service = app.service else { return }
        let current = try? await service.preview(threadId: threadId)
        if current?.status == "ready", let access = try? await service.previewAccess(threadId: threadId) {
            preview = access
        } else {
            preview = current
        }
    }
}

private struct PreviewWebView: UIViewRepresentable {
    let url: URL
    let gateway: PreviewGateway?

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.allowsBackForwardNavigationGestures = true
        var request = URLRequest(url: url)
        if let gateway { request.setValue(gateway.token, forHTTPHeaderField: gateway.header) }
        view.load(request)
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}
}
