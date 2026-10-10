import SwiftUI

struct DiffView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let threadId: String
    @State private var mode = DiffMode.uncommitted
    @State private var diff: ThreadDiff?
    @State private var error: String?
    @State private var collapsed: Set<String> = []

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    Picker("Compare", selection: $mode) {
                        ForEach(DiffMode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if let diff {
                        if diff.files.isEmpty {
                            EmptyState(icon: "checkmark.circle", title: "No changes", message: diff.unavailableReason ?? "The workspace matches \(mode == .uncommitted ? "the last commit" : "the base branch").")
                        } else {
                            DiffSummary(stats: diff.totals, fallback: diff.isFallback == true ? diff.effectiveMode : nil)
                            ForEach(diff.files) { file in
                                FileDiffCard(file: file, collapsed: collapsed.contains(file.id)) {
                                    withAnimation(.snappy) {
                                        if collapsed.contains(file.id) { collapsed.remove(file.id) } else { collapsed.insert(file.id) }
                                    }
                                }
                            }
                        }
                    } else if let error {
                        ErrorBanner(message: error) { Task { await load() } }
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(HP.canvas)
            .navigationTitle("Changes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done", systemImage: "checkmark") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation(.snappy) {
                            let all = Set(diff?.files.map(\.id) ?? [])
                            collapsed = collapsed.count == all.count ? [] : all
                        }
                    } label: {
                        Image(systemName: "rectangle.compress.vertical")
                    }
                    .accessibilityLabel("Collapse all files")
                }
            }
            .task(id: mode) { await load() }
        }
    }

    private func load() async {
        guard let service = app.service else { return }
        diff = nil
        error = nil
        do {
            let loaded = try await service.diff(threadId: threadId, mode: mode)
            collapsed = loaded.files.count > 3 ? Set(loaded.files.map(\.id)) : []
            diff = loaded
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct DiffSummary: View {
    let stats: DiffStats
    var fallback: DiffMode?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(stats.files) file\(stats.files == 1 ? "" : "s") changed").font(.ui(16, weight: .semibold)).foregroundStyle(HP.ink)
                if let fallback { Text("Showing \(fallback.label.lowercased()) diff").font(.hpCaption).foregroundStyle(HP.ink3) }
            }
            Spacer()
            Text("+\(stats.additions)").font(.mono(14, weight: .semibold)).foregroundStyle(HP.addition)
            Text("−\(stats.deletions)").font(.mono(14, weight: .semibold)).foregroundStyle(HP.deletion)
            ChangeBlocks(additions: stats.additions, deletions: stats.deletions)
        }
        .padding(16)
        .hpCard(radius: 20, fill: HP.surface)
    }
}

/// GitHub's five-square change bar.
struct ChangeBlocks: View {
    let additions: Int
    let deletions: Int

    var body: some View {
        let total = max(additions + deletions, 1)
        let green = additions == 0 ? 0 : max(1, Int((Double(additions) / Double(total) * 5).rounded()))
        let red = deletions == 0 ? 0 : min(5 - green, max(1, Int((Double(deletions) / Double(total) * 5).rounded())))
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(index < green ? HP.addition : index < green + red ? HP.deletion : HP.ink3.opacity(0.35))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct FileDiffCard: View {
    let file: DiffFile
    let collapsed: Bool
    let toggle: () -> Void

    private var badge: (String, Color) {
        switch file.state {
        case "added": ("A", HP.addition)
        case "deleted": ("D", HP.deletion)
        case "renamed", "copied": ("R", HP.info)
        default: ("M", HP.waiting)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 10) {
                    Text(badge.0)
                        .font(.mono(11, weight: .bold))
                        .foregroundStyle(badge.1)
                        .frame(width: 20, height: 20)
                        .background(badge.1.opacity(0.14), in: .rect(cornerRadius: 6))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(Text(file.directory).foregroundStyle(HP.ink3))\(Text(file.fileName).foregroundStyle(HP.ink))")
                            .font(.mono(13, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.head)
                        if let previous = file.previousPath {
                            Text("from \(previous)").font(.mono(11)).foregroundStyle(HP.ink3).lineLimit(1).truncationMode(.head)
                        }
                    }
                    Spacer(minLength: 6)
                    if let a = file.additions, a > 0 { Text("+\(a)").font(.mono(12, weight: .medium)).foregroundStyle(HP.addition) }
                    if let d = file.deletions, d > 0 { Text("−\(d)").font(.mono(12, weight: .medium)).foregroundStyle(HP.deletion) }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(HP.ink3)
                        .rotationEffect(.degrees(collapsed ? -90 : 0))
                }
                .padding(12)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if !collapsed {
                Divider().overlay(HP.hairline)
                if let patch = file.patch, !patch.isEmpty {
                    PatchView(patch: patch)
                } else {
                    Text(file.truncatedReason.map { "Diff hidden: \($0.replacingOccurrences(of: "_", with: " "))" } ?? "Binary or empty file")
                        .font(.hpFootnote).foregroundStyle(HP.ink3).padding(14)
                }
            }
        }
        .background(HP.surface, in: .rect(cornerRadius: 18, style: .continuous))
        .clipShape(.rect(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(HP.hairline))
    }
}

struct PatchLine: Identifiable {
    enum Kind { case hunk, add, remove, context }
    let id: Int
    let kind: Kind
    let text: String
    let old: Int?
    let new: Int?

    static func parse(_ patch: String) -> [PatchLine] {
        var lines: [PatchLine] = []
        var old = 0, new = 0
        for (index, raw) in patch.components(separatedBy: "\n").enumerated() {
            if raw.hasPrefix("@@") {
                let numbers = raw.split(separator: " ").dropFirst().prefix(2).map { part -> Int in
                    Int(part.dropFirst().split(separator: ",").first ?? "0") ?? 0
                }
                old = numbers.first ?? 0
                new = numbers.count > 1 ? numbers[1] : 0
                lines.append(PatchLine(id: index, kind: .hunk, text: raw, old: nil, new: nil))
            } else if raw.hasPrefix("+") {
                lines.append(PatchLine(id: index, kind: .add, text: String(raw.dropFirst()), old: nil, new: new))
                new += 1
            } else if raw.hasPrefix("-") {
                lines.append(PatchLine(id: index, kind: .remove, text: String(raw.dropFirst()), old: old, new: nil))
                old += 1
            } else if raw.hasPrefix("\\") {
                continue
            } else {
                lines.append(PatchLine(id: index, kind: .context, text: String(raw.dropFirst(raw.hasPrefix(" ") ? 1 : 0)), old: old, new: new))
                old += 1
                new += 1
            }
        }
        return lines
    }
}

struct PatchView: View {
    let lines: [PatchLine]
    @State private var width: CGFloat = 0

    init(patch: String) { lines = PatchLine.parse(patch) }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(lines) { line in
                    HStack(spacing: 0) {
                        if line.kind == .hunk {
                            Text(line.text)
                                .font(.mono(11.5))
                                .foregroundStyle(HP.info)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                        } else {
                            Text(line.kind == .remove ? "\(line.old ?? 0)" : "\(line.new ?? 0)")
                                .font(.mono(10.5))
                                .foregroundStyle(HP.ink3)
                                .frame(width: 36, alignment: .trailing)
                                .padding(.trailing, 8)
                            Text(line.kind == .add ? "+" : line.kind == .remove ? "−" : " ")
                                .font(.mono(12.5, weight: .semibold))
                                .foregroundStyle(line.kind == .add ? HP.addition : HP.deletion)
                                .frame(width: 14)
                            Text(line.text.isEmpty ? " " : line.text)
                                .font(.mono(12.5))
                                .foregroundStyle(HP.ink)
                                .fixedSize()
                                .padding(.trailing, 16)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                    .background(background(line.kind))
                }
            }
            .frame(minWidth: width, alignment: .leading)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.vertical, 6)
            .textSelection(.enabled)
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
    }

    private func background(_ kind: PatchLine.Kind) -> Color {
        switch kind {
        case .add: HP.addition.opacity(0.13)
        case .remove: HP.deletion.opacity(0.13)
        case .hunk: HP.info.opacity(0.07)
        case .context: .clear
        }
    }
}
