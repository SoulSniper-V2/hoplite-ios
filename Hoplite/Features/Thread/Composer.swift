import PhotosUI
import SwiftUI

struct PendingAttachment: Identifiable, Equatable {
    let id = UUID()
    let image: UIImage
    let data: Data
    let name: String

    var width: Int { Int(image.size.width * image.scale) }
    var height: Int { Int(image.size.height * image.scale) }
}

/// Hoplite's composer slash commands (hoplite.sh/docs/agent/slash-commands), run locally.
enum SlashCommand: String, CaseIterable, Identifiable {
    case pr, model, retry, stop, compact, rename, archive

    var id: String { rawValue }
    var takesArgument: Bool { self == .rename }
    var icon: String {
        switch self {
        case .pr: "arrow.triangle.pull"
        case .model: "cpu"
        case .retry: "arrow.clockwise"
        case .stop: "stop.circle"
        case .compact: "rectangle.compress.vertical"
        case .rename: "pencil"
        case .archive: "archivebox"
        }
    }
    var summary: String {
        switch self {
        case .pr: "Open the pull request, or create one from the diff"
        case .model: "Switch the model for the next run"
        case .retry: "Queue a new run in the same workspace"
        case .stop: "Cancel the run you're viewing"
        case .compact: "Summarize older context to free tokens"
        case .rename: "Rename the thread"
        case .archive: "Archive the thread"
        }
    }

    static func matching(_ text: String) -> [SlashCommand] {
        guard text.hasPrefix("/") else { return [] }
        let token = text.dropFirst().split(separator: " ", maxSplits: 1).first.map(String.init) ?? ""
        if text.contains(" ") { return [] }
        return allCases.filter { token.isEmpty || $0.rawValue.hasPrefix(token.lowercased()) }
    }

    static func parse(_ text: String) -> (SlashCommand, String)? {
        guard text.hasPrefix("/") else { return nil }
        let parts = text.dropFirst().split(separator: " ", maxSplits: 1)
        guard let name = parts.first, let command = SlashCommand(rawValue: name.lowercased()) else { return nil }
        return (command, parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : "")
    }
}

/// The bottom glass composer: a capsule at rest that opens into a card while you write.
/// Model, attachments and whether a message steers or queues are always visible.
struct Composer: View {
    @Environment(AppModel.self) private var app
    @Binding var text: String
    @Binding var selectedModel: String?
    @Binding var attachments: [PendingAttachment]
    let thread: AgentThread?
    let sending: Bool
    let onSend: () -> Void
    let onStop: () -> Void
    let onCommand: (SlashCommand, String) -> Void

    @FocusState private var focused: Bool
    @State private var picking: [PhotosPickerItem] = []
    @State private var showModels = false

    private var hasText: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var canSend: Bool { hasText || !attachments.isEmpty }
    private var live: Bool { thread?.hasLiveRun == true }
    private var steerable: Bool { live && thread?.runSteerable == true }
    private var expanded: Bool { focused || canSend }
    private var commands: [SlashCommand] { SlashCommand.matching(text) }

    private var placeholder: String {
        if steerable { return "Steer the agent…" }
        if live { return "Queue a follow-up…" }
        return "Send a message…"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !commands.isEmpty {
                SlashPalette(commands: commands) { command in
                    if command.takesArgument {
                        text = "/\(command.rawValue) "
                    } else {
                        text = ""
                        run(command, "")
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            VStack(alignment: .leading, spacing: 10) {
                if !attachments.isEmpty {
                    AttachmentStrip(attachments: $attachments)
                }
                HStack(alignment: .bottom, spacing: 10) {
                    if !expanded {
                        attachButton
                            .transition(.scale.combined(with: .opacity))
                    }
                    TextField(placeholder, text: $text, axis: .vertical)
                        .font(.hpBody)
                        .lineLimit(1...8)
                        .focused($focused)
                        .accessibilityIdentifier("composer")
                        .padding(.horizontal, expanded ? 4 : 0)
                        .padding(.top, expanded ? 4 : 0)
                        .padding(.bottom, expanded ? 0 : 8)
                    if !expanded {
                        trailingButton
                    }
                }

                if expanded {
                    HStack(spacing: 8) {
                        attachButton
                        ModelChip(selected: selectedModel) { showModels = true }
                        if live {
                            Image(systemName: steerable ? "arrow.turn.down.right" : "text.line.last.and.arrowtriangle.forward")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(HP.ink3)
                                .accessibilityLabel(steerable ? "Steers the current run" : "Queues for the next run")
                        }
                        Spacer(minLength: 0)
                        trailingButton
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(.horizontal, expanded ? 12 : 8)
            .padding(.vertical, expanded ? 10 : 8)
            .glassEffect(.regular, in: .rect(cornerRadius: 26, style: .continuous))
        }
        .animation(.smooth(duration: 0.22), value: expanded)
        .animation(.smooth(duration: 0.22), value: live)
        .animation(.snappy, value: commands)
        .animation(.snappy, value: attachments)
        .sheet(isPresented: $showModels) { ModelPickerSheet(selected: $selectedModel) }
        .onChange(of: picking) { _, items in Task { await load(items) } }
        #if DEBUG
        .onAppear { if UserDefaults.standard.bool(forKey: "UITestModels") { showModels = true } }
        #endif
    }

    private func run(_ command: SlashCommand, _ argument: String) {
        if command == .model { showModels = true } else { onCommand(command, argument) }
    }

    private var attachButton: some View {
        PhotosPicker(selection: $picking, maxSelectionCount: 4, matching: .images) {
            Image(systemName: "paperclip")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(HP.ink2)
                .frame(width: 36, height: 36)
                .background(HP.control.opacity(expanded ? 0 : 0.8), in: .circle)
                .contentShape(.circle)
        }
        .accessibilityLabel("Attach images")
    }

    private func load(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { continue }
            let jpeg = image.jpegData(compressionQuality: 0.85) ?? data
            attachments.append(PendingAttachment(image: image, data: jpeg, name: "image-\(attachments.count + 1).jpg"))
        }
        picking = []
        focused = true
    }

    @ViewBuilder private var trailingButton: some View {
        if live && !canSend {
            Button(action: onStop) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(HP.canvas)
                    .frame(width: 36, height: 36)
                    .background(HP.ink, in: .rect(cornerRadius: 12, style: .continuous))
            }
            .accessibilityLabel("Stop run")
            .transition(.scale.combined(with: .opacity))
        } else {
            Button {
                if let (command, argument) = SlashCommand.parse(text.trimmingCharacters(in: .whitespacesAndNewlines)), attachments.isEmpty {
                    text = ""
                    run(command, argument)
                } else {
                    onSend()
                }
            } label: {
                Group {
                    if sending { ProgressView().tint(.white) } else { Image(systemName: "arrow.up").font(.system(size: 16, weight: .bold)) }
                }
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(canSend ? HP.action : HP.ink3.opacity(0.4), in: .rect(cornerRadius: 12, style: .continuous))
                .shadow(color: canSend ? HP.action.opacity(0.45) : .clear, radius: 8, y: 2)
            }
            .disabled(!canSend || sending)
            .accessibilityLabel(steerable ? "Steer" : "Send")
            .transition(.scale.combined(with: .opacity))
            .sensoryFeedback(.impact(weight: .light), trigger: sending) { _, new in new }
        }
    }
}

private struct SlashPalette: View {
    let commands: [SlashCommand]
    let pick: (SlashCommand) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(commands) { command in
                Button { pick(command) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: command.icon)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(HP.ink2)
                            .frame(width: 28, height: 28)
                            .background(HP.control, in: .rect(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("/\(command.rawValue)\(command.takesArgument ? " <title>" : "")").font(.mono(13.5, weight: .medium)).foregroundStyle(HP.ink)
                            Text(command.summary).font(.ui(12.5)).foregroundStyle(HP.ink3).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
        .background(HP.raised, in: .rect(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(HP.hairline))
        .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
    }
}

struct AttachmentStrip: View {
    @Binding var attachments: [PendingAttachment]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    Image(uiImage: attachment.image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 58, height: 58)
                        .clipShape(.rect(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(HP.hairline))
                        .overlay(alignment: .topTrailing) {
                            Button {
                                attachments.removeAll { $0.id == attachment.id }
                            } label: {
                                Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                                    .frame(width: 18, height: 18).background(.black.opacity(0.7), in: .circle)
                            }
                            .offset(x: 5, y: -5)
                            .accessibilityLabel("Remove image")
                        }
                }
            }
            .padding(.top, 6)
            .padding(.horizontal, 4)
        }
    }
}

// MARK: Models

enum Provider {
    private static let assets: Set<String> = ["anthropic", "openai", "google", "xai", "deepseek", "openrouter", "zhipu", "qwen", "moonshot", "meta", "mistral", "minimax"]

    /// The logo asset for a provider ("Anthropic", "openai", …) or, when a model id is given, for the
    /// lab that made the model, so OpenRouter's GLM and DeepSeek models show their own marks.
    static func logo(_ provider: String?, model: String? = nil) -> String? {
        if let key = vendor(of: model) ?? normalized(provider), assets.contains(key) { return "Provider-\(key)" }
        return nil
    }

    static func vendor(of model: String?) -> String? {
        guard let id = model?.lowercased() else { return nil }
        let name = id.split(separator: "/").last.map(String.init) ?? id
        let prefix = id.contains("/") ? String(id.split(separator: "/")[0]) : ""
        let rules: [(String, String)] = [
            ("claude", "anthropic"), ("gpt", "openai"), ("o1", "openai"), ("o3", "openai"), ("o4", "openai"), ("codex", "openai"),
            ("gemini", "google"), ("gemma", "google"), ("grok", "xai"), ("deepseek", "deepseek"), ("glm", "zhipu"),
            ("qwen", "qwen"), ("kimi", "moonshot"), ("llama", "meta"), ("muse", "meta"), ("mistral", "mistral"), ("devstral", "mistral"), ("minimax", "minimax"),
        ]
        if let match = rules.first(where: { name.hasPrefix($0.0) }) { return match.1 }
        let prefixes = ["anthropic": "anthropic", "openai": "openai", "google": "google", "x-ai": "xai", "xai": "xai", "deepseek": "deepseek", "z-ai": "zhipu", "zai": "zhipu", "qwen": "qwen", "moonshotai": "moonshot", "meta-llama": "meta", "meta": "meta", "mistralai": "mistral", "minimax": "minimax"]
        return prefixes[prefix]
    }

    private static func normalized(_ provider: String?) -> String? {
        guard let key = provider?.lowercased().replacingOccurrences(of: " ", with: "") else { return nil }
        return ["x-ai": "xai", "z-ai": "zhipu", "zai": "zhipu", "moonshotai": "moonshot", "mistralai": "mistral", "gemini": "google"][key] ?? key
    }

    static func name(_ provider: String) -> String {
        ["anthropic": "Anthropic", "openai": "OpenAI", "google": "Google", "xai": "xAI", "deepseek": "DeepSeek", "openrouter": "OpenRouter"][provider.lowercased()] ?? provider
    }
}

struct ProviderLogo: View {
    let provider: String?
    var model: String? = nil
    var size: CGFloat = 14

    var body: some View {
        if let asset = Provider.logo(provider, model: model) {
            Image(asset).resizable().renderingMode(.template).scaledToFit().frame(width: size, height: size)
        } else {
            Image(systemName: "cpu").font(.system(size: size * 0.85, weight: .semibold)).frame(width: size, height: size)
        }
    }
}

struct ModelChip: View {
    @Environment(AppModel.self) private var app
    let selected: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                ProviderLogo(provider: app.catalog?.model(selected)?.provider, model: selected, size: 13)
                Text(app.modelName(selected) ?? "Default model").font(.ui(13, weight: .medium)).lineLimit(1).fixedSize()
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(HP.ink3)
            }
            .foregroundStyle(HP.ink2)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(HP.control.opacity(0.8), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Model: \(app.modelName(selected) ?? "default")")
    }
}

/// The model picker as a sheet: provider marks, context window and capabilities at a glance.
struct ModelPickerSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Binding var selected: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    let models = app.catalog?.primaryModels ?? []
                    let providers = Dictionary(grouping: models, by: \.provider)
                    ForEach(providers.keys.sorted { order($0) < order($1) }, id: \.self) { provider in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 7) {
                                ProviderLogo(provider: provider, size: 13).foregroundStyle(HP.ink3)
                                Eyebrow(text: Provider.name(provider))
                            }
                            .padding(.leading, 4)
                            VStack(spacing: 0) {
                                ForEach(Array((providers[provider] ?? []).enumerated()), id: \.element.id) { index, model in
                                    if index > 0 { Divider().overlay(HP.hairline).padding(.leading, 56) }
                                    row(model)
                                }
                            }
                            .hpCard(radius: 20, fill: HP.surface)
                        }
                    }
                    if models.isEmpty {
                        EmptyState(icon: "cpu", title: "No models available", message: "Your workspace hasn't authorized any models yet.")
                    }
                }
                .padding(16)
            }
            .background(HP.canvas)
            .navigationTitle("Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done", systemImage: "checkmark") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func row(_ model: ModelInfo) -> some View {
        Button {
            selected = model.id
            dismiss()
        } label: {
            HStack(spacing: 12) {
                ProviderLogo(provider: model.provider, model: model.id, size: 18)
                    .foregroundStyle(HP.ink)
                    .frame(width: 34, height: 34)
                    .background(HP.control, in: .rect(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(model.name).font(.ui(16, weight: .medium)).foregroundStyle(HP.ink)
                        if model.requiredPlan == "pro" {
                            Text("PRO").font(.mono(9.5, weight: .bold)).tracking(0.8).foregroundStyle(HP.action)
                                .padding(.horizontal, 5).padding(.vertical, 2).background(HP.action.opacity(0.12), in: .capsule)
                        }
                        if model.id == app.catalog?.runConfig?.defaultModelId {
                            Text("Default").font(.ui(11, weight: .medium)).foregroundStyle(HP.ink3)
                        }
                    }
                    HStack(spacing: 10) {
                        if let context = model.capabilities?.contextWindowTokens {
                            Text("\(Format.tokens(Double(context))) context").font(.mono(11)).foregroundStyle(HP.ink3)
                        }
                        if model.capabilities?.supportsImages == true { Image(systemName: "photo").font(.system(size: 10)).foregroundStyle(HP.ink3).accessibilityLabel("Images") }
                        if model.capabilities?.supportsFast == true { Image(systemName: "bolt.fill").font(.system(size: 10)).foregroundStyle(HP.ink3).accessibilityLabel("Fast mode") }
                    }
                }
                Spacer()
                if selected == model.id {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundStyle(HP.action)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selected)
    }

    private func order(_ provider: String) -> Int {
        ["anthropic", "openai", "google", "xai", "deepseek", "openrouter"].firstIndex(of: provider.lowercased()) ?? 99
    }
}
