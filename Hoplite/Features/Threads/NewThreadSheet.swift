import PhotosUI
import SwiftUI

/// Mirrors app.hoplite.sh's mobile "New thread": a quiet prompt, then the project, branch and
/// target pills over a single composer with attach, model, effort and fast mode.
struct NewThreadSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let onCreated: (AgentThread) -> Void

    @State private var prompt = ""
    @State private var projectId: String?
    @State private var model: String?
    @State private var options = ThreadOptions()
    @State private var attachments: [PendingAttachment] = []
    @State private var picking: [PhotosPickerItem] = []
    @State private var showPhotos = false
    @State private var showModels = false
    @State private var creating = false
    @State private var error: String?
    @FocusState private var focused: Bool

    private var project: Project? { app.project(projectId) }
    private var projectName: String? { project.map { $0.name.split(separator: "/").last.map(String.init) ?? $0.name } }
    private var modelInfo: ModelInfo? { app.catalog?.model(model) }
    private var branch: String? { project?.defaultBranch ?? project?.repos?.first?.defaultBranch }
    private var canStart: Bool { projectId != nil && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !creating }

    private var efforts: [String] {
        modelInfo?.capabilities?.reasoningLevels?.filter { $0 != "none" } ?? app.catalog?.runConfig?.reasoningOptions ?? ["low", "medium", "high", "xhigh", "max"]
    }
    private var effort: String { options.reasoning ?? project?.reasoningEffort ?? app.catalog?.runConfig?.defaultReasoning ?? "medium" }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 24)
                VStack(alignment: .leading, spacing: 10) {
                    Text("What should Hoplite work on?")
                        .font(.display(30, weight: .medium))
                        .foregroundStyle(HP.ink)
                    Text("Describe the task. It runs in a cloud sandbox for \(projectName ?? "this project") and reports back here.")
                        .font(.ui(16))
                        .foregroundStyle(HP.ink2)
                        .lineSpacing(3)
                }
                .padding(.horizontal, 8)
                Spacer(minLength: 24)

                if let error {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(.hpFootnote)
                        .foregroundStyle(HP.failed)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 10)
                }

                HStack(spacing: 8) {
                    projectMenu
                    if let branch {
                        Pill { Image(systemName: "arrow.triangle.branch"); Text(branch).font(.ui(14)) }
                    }
                    Pill { Image(systemName: "cloud"); Text("Cloud").font(.ui(14)) }
                    Spacer(minLength: 0)
                }
                .padding(.bottom, 10)

                composer
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
            .background(HP.canvas)
            .navigationTitle("New thread")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(HP.ink2)
                }
            }
            .onAppear {
                applyDefaults()
                focused = true
                #if DEBUG
                if UserDefaults.standard.bool(forKey: "UITestModels") { focused = false; showModels = true }
                #endif
            }
            .onChange(of: app.projects) { applyDefaults() }
            .onChange(of: app.catalog) { applyDefaults() }
            .onChange(of: model) { if !(modelInfo?.capabilities?.supportsFast ?? false) { options.fast = false } }
            .onChange(of: picking) { _, items in Task { await load(items) } }
        }
        .presentationDetents([.large])
        .presentationBackground(HP.canvas)
        .sheet(isPresented: $showModels) { ModelPickerSheet(selected: $model) }
        .photosPicker(isPresented: $showPhotos, selection: $picking, maxSelectionCount: 4, matching: .images)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !attachments.isEmpty { AttachmentStrip(attachments: $attachments) }
            TextField("Ask Hoplite to build, fix or explain…", text: $prompt, axis: .vertical)
                .font(.ui(17))
                .foregroundStyle(HP.ink)
                .lineLimit(2...10)
                .focused($focused)
                .accessibilityIdentifier("newThreadPrompt")
            HStack(spacing: 6) {
                moreMenu
                ModelChip(selected: model) { showModels = true }
                effortMenu
                if modelInfo?.capabilities?.supportsFast == true {
                    Button {
                        options.fast.toggle()
                    } label: {
                        Image(systemName: options.fast ? "bolt.fill" : "bolt")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(options.fast ? HP.waiting : HP.ink3)
                            .frame(width: 28, height: 32)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(options.fast ? "Fast mode on" : "Fast mode off")
                }
                Spacer(minLength: 0)
                Button { Task { await start() } } label: {
                    Group {
                        if creating { ProgressView().tint(HP.canvas) } else { Image(systemName: "arrow.up").font(.system(size: 16, weight: .bold)) }
                    }
                    .foregroundStyle(canStart ? HP.canvas : HP.ink3)
                    .frame(width: 38, height: 38)
                    .background(canStart ? HP.ink : HP.control, in: .circle)
                }
                .buttonStyle(.plain)
                .disabled(!canStart)
                .accessibilityLabel("Start thread")
                .animation(.snappy, value: canStart)
            }
        }
        .padding(14)
        .background(HP.surface, in: .rect(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(HP.hairline))
    }

    private var moreMenu: some View {
        Menu {
            Button("Add photos", systemImage: "photo.on.rectangle") { showPhotos = true }
            Picker(selection: $options.autoMerge) {
                Text("Workspace default").tag(Bool?.none)
                Text("Merge when green").tag(Bool?.some(true))
                Text("Never").tag(Bool?.some(false))
            } label: { Label("Auto-merge", systemImage: "arrow.triangle.merge") }
                .pickerStyle(.menu)
            Picker(selection: $options.spendLimitMicros) {
                Text("No limit").tag(Int?.none)
                ForEach([2, 5, 10, 25], id: \.self) { Text("$\($0)").tag(Int?.some($0 * 1_000_000)) }
            } label: { Label("Spend limit", systemImage: "dollarsign.circle") }
                .pickerStyle(.menu)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(HP.ink2)
                .frame(width: 34, height: 34)
                .background(HP.control.opacity(0.8), in: .circle)
        }
        .accessibilityLabel("More options")
    }

    private var effortMenu: some View {
        Menu {
            Picker("Reasoning effort", selection: Binding(get: { effort }, set: { options.reasoning = $0 })) {
                ForEach(efforts, id: \.self) { Text(Self.effortName($0)).tag($0) }
            }
        } label: {
            HStack(spacing: 6) {
                EffortBars(level: (efforts.firstIndex(of: effort) ?? 1) + 1, total: max(efforts.count, 1))
                Text(Self.effortName(effort)).font(.ui(13, weight: .medium)).lineLimit(1).fixedSize()
            }
            .foregroundStyle(HP.ink2)
            .padding(.horizontal, 6)
            .frame(height: 32)
        }
        .accessibilityLabel("Reasoning effort: \(Self.effortName(effort))")
    }

    private var projectMenu: some View {
        Menu {
            ForEach(app.projects) { item in
                Button {
                    projectId = item.id
                    if let defaultModel = item.defaultModel { model = defaultModel }
                } label: {
                    if item.id == projectId { Label(item.name, systemImage: "checkmark") } else { Text(item.name) }
                }
            }
        } label: {
            Pill {
                Image("GitHubMark").resizable().scaledToFit().frame(width: 14, height: 14)
                Text(projectName ?? "Choose project").font(.ui(14, weight: .medium)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(HP.ink3)
            }
        }
    }

    private static func effortName(_ level: String) -> String {
        switch level {
        case "xhigh": "Extra high"
        case "none", "off": "Off"
        default: level.capitalized
        }
    }

    private func applyDefaults() {
        projectId = projectId ?? app.selectedProjectId ?? app.projects.first?.id
        model = model ?? project?.defaultModel ?? app.catalog?.runConfig?.defaultModelId
    }

    private func load(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { continue }
            attachments.append(PendingAttachment(image: image, data: image.jpegData(compressionQuality: 0.85) ?? data, name: "image-\(attachments.count + 1).jpg"))
        }
        picking = []
    }

    private func start() async {
        guard canStart, let projectId, let service = app.service else { return }
        creating = true
        error = nil
        defer { creating = false }
        do {
            var options = options
            options.reasoning = effort
            for attachment in attachments {
                options.attachmentTickets.append(try await service.stageInitialAttachment(
                    projectId: projectId, operationId: options.operationId, data: attachment.data,
                    filename: attachment.name, contentType: "image/jpeg", width: attachment.width, height: attachment.height
                ))
            }
            let thread = try await service.createThread(projectId: projectId, prompt: prompt, model: model, title: nil, options: options)
            app.replace(thread)
            dismiss()
            onCreated(thread)
        } catch {
            withAnimation { self.error = error.localizedDescription }
        }
    }
}

private struct Pill<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 6) { content }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(HP.ink)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(HP.surface, in: .rect(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(HP.hairline))
    }
}

/// The web composer's signal-strength effort indicator.
private struct EffortBars: View {
    let level: Int
    let total: Int

    var body: some View {
        HStack(alignment: .bottom, spacing: 1.5) {
            ForEach(0..<total, id: \.self) { index in
                RoundedRectangle(cornerRadius: 0.75)
                    .fill(index < level ? HP.ink2 : HP.ink3.opacity(0.4))
                    .frame(width: 2.5, height: 4 + CGFloat(index) * 2)
            }
        }
        .frame(height: 12, alignment: .bottom)
    }
}
