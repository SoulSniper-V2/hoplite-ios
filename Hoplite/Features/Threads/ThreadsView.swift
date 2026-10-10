import SwiftUI

enum ThreadFilter: String, CaseIterable, Identifiable {
    case all, attention, active, ready
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: "All"
        case .attention: "Needs you"
        case .active: "Working"
        case .ready: "Ready"
        }
    }

    func matches(_ thread: AgentThread) -> Bool {
        switch self {
        case .all: true
        case .attention: thread.status.needsAttention
        case .active: thread.status.isActive
        case .ready: thread.status == .ready
        }
    }
}

struct ThreadsView: View {
    @Environment(AppModel.self) private var model
    @State private var filter = ThreadFilter.all
    @State private var showAccount = false

    private var visible: [AgentThread] { model.threads.filter(filter.matches) }

    private var sections: [(title: String, threads: [AgentThread])] {
        let list = visible
        let groups: [(String, [AgentThread])] = [
            ("Needs you", list.filter { $0.status.needsAttention }),
            ("In progress", list.filter { $0.status.isActive }),
            ("Ready for review", list.filter { $0.status == .ready && $0.pullRequest.map { ($0.githubSummary?.state ?? $0.state) == "open" } == true }),
            ("Done", list.filter { $0.status == .ready && $0.pullRequest.map { ($0.githubSummary?.state ?? $0.state) == "open" } != true }),
        ]
        return groups.filter { !$0.1.isEmpty }.map { (title: $0.0, threads: $0.1) }
    }

    var body: some View {
        List {
            Section {
                FilterBar(filter: $filter, counts: counts)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            if let error = model.lastError, model.threads.isEmpty {
                ErrorBanner(message: error) { Task { await model.loadEverything() } }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            if model.threads.isEmpty && model.isLoading {
                ForEach(0..<6, id: \.self) { _ in SkeletonRow() }
                    .listRowBackground(Color.clear)
            } else if visible.isEmpty {
                EmptyState(
                    icon: filter == .attention ? "checkmark.seal" : "square.stack.3d.up",
                    title: filter == .attention ? "Nothing needs you" : filter == .all ? "No active threads" : "Nothing here right now",
                    message: filter == .attention ? "Approvals and failed runs will show up here." : "Start a thread and Hoplite will spin up a cloud workspace for it. Older threads are in Archived.",
                    action: filter == .attention ? nil : ("New thread", { model.composingNewThread = true })
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            ForEach(sections, id: \.title) { section in
                Section {
                    ForEach(section.threads) { thread in
                        NavigationLink(value: thread.id) {
                            ThreadRow(thread: thread)
                        }
                        .navigationLinkIndicatorVisibility(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(HP.hairline)
                        .swipeActions(edge: .trailing) { archiveAction(thread) }
                        .contextMenu { ThreadContextMenu(thread: thread) }
                    }
                } header: {
                    HStack {
                        Text(section.title).font(.ui(13, weight: .semibold)).foregroundStyle(section.title == "Needs you" ? HP.waiting : HP.ink2)
                        Text("\(section.threads.count)").font(.mono(11.5)).foregroundStyle(HP.ink3)
                    }
                    .textCase(nil)
                }
            }

            Section {
                NavigationLink {
                    ArchivedThreadsView()
                } label: {
                    Label("Archived", systemImage: "archivebox").font(.hpCallout).foregroundStyle(HP.ink2)
                }
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(HP.canvas)
        .navigationTitle(model.project(model.selectedProjectId)?.name ?? "Threads")
        .toolbarTitleDisplayMode(.inlineLarge)
        .refreshable { await model.refreshThreads() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAccount = true } label: { Image(systemName: "person.crop.circle").foregroundStyle(HP.ink) }
                    .accessibilityLabel("Account")
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                Button { model.composingNewThread = true } label: { Image(systemName: "square.and.pencil") }
                    .buttonStyle(.glassProminent)
                    .tint(HP.action)
                    .accessibilityLabel("New thread")
            }
        }
        .toolbarTitleMenu { ProjectPicker() }
        .sheet(isPresented: $showAccount) { AccountView() }
        #if DEBUG
        .onAppear { if UserDefaults.standard.bool(forKey: "UITestAccount") { showAccount = true } }
        #endif
    }

    private var counts: [ThreadFilter: Int] {
        Dictionary(uniqueKeysWithValues: ThreadFilter.allCases.map { filter in (filter, model.threads.filter(filter.matches).count) })
    }

    private func archiveAction(_ thread: AgentThread) -> some View {
        Button {
            Task {
                guard let service = model.service, let updated = try? await service.setArchived(thread, archived: true) else { return }
                withAnimation { model.replace(updated) }
            }
        } label: {
            Label("Archive", systemImage: "archivebox")
        }
        .tint(HP.archived)
    }
}

struct ThreadContextMenu: View {
    @Environment(AppModel.self) private var model
    let thread: AgentThread

    var body: some View {
        if let pr = thread.pullRequest, let url = URL(string: pr.url) {
            Link(destination: url) { Label("Open PR #\(pr.number) on GitHub", systemImage: "arrow.up.right.square") }
        }
        Button {
            UIPasteboard.general.string = thread.id
        } label: { Label("Copy thread ID", systemImage: "doc.on.doc") }
        Button {
            Task {
                guard let service = model.service, let updated = try? await service.setArchived(thread, archived: thread.status != .archived) else { return }
                withAnimation { model.replace(updated) }
            }
        } label: {
            Label(thread.status == .archived ? "Unarchive" : "Archive", systemImage: thread.status == .archived ? "tray.and.arrow.up" : "archivebox")
        }
    }
}

private struct FilterBar: View {
    @Binding var filter: ThreadFilter
    let counts: [ThreadFilter: Int]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ThreadFilter.allCases) { item in
                    let selected = item == filter
                    Button {
                        withAnimation(.snappy) { filter = item }
                    } label: {
                        HStack(spacing: 6) {
                            if item == .attention, (counts[item] ?? 0) > 0 {
                                Circle().fill(HP.waiting).frame(width: 7, height: 7)
                            }
                            Text(item.label).font(.ui(14, weight: .medium))
                            if item != .all, let count = counts[item], count > 0 {
                                Text("\(count)").font(.mono(12, weight: .medium)).foregroundStyle(selected ? HP.canvas.opacity(0.7) : HP.ink3)
                            }
                        }
                        .foregroundStyle(selected ? HP.canvas : HP.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(selected ? HP.ink : HP.control.opacity(0.75), in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("filter-\(item.rawValue)")
                    .sensoryFeedback(.selection, trigger: filter)
                }
            }
            .padding(.horizontal, HP.pageGutter)
        }
        .scrollClipDisabled()
    }
}

struct ThreadRow: View {
    @Environment(AppModel.self) private var model
    let thread: AgentThread

    private var project: Project? { model.project(thread.projectId) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                ProjectBadge(project: project)
                Text(project?.name ?? "Project").font(.ui(13.5)).foregroundStyle(HP.ink3).lineLimit(1)
                if thread.createdByAutomation == true {
                    Image(systemName: "bolt.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(HP.ink3)
                }
                Spacer(minLength: 8)
                ThreadStatusWord(thread: thread)
            }
            Text(thread.displayTitle)
                .font(.ui(17, weight: .medium))
                .foregroundStyle(HP.ink)
                .lineLimit(2)
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch").font(.system(size: 10, weight: .semibold)).foregroundStyle(HP.ink3)
                Text(thread.pullRequest?.headRef ?? project?.repos?.first?.display ?? "main")
                    .font(.mono(12))
                    .foregroundStyle(HP.ink3)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                if let pr = thread.pullRequest {
                    HStack(spacing: 4) {
                        Text("#\(pr.number)").font(.mono(12, weight: .medium)).foregroundStyle(HP.ink2)
                        if let checks = pr.githubSummary?.checks, checks.total > 0, (pr.githubSummary?.state ?? pr.state) == "open" {
                            ChecksRing(checks: checks, size: 10)
                        }
                    }
                }
                if let people = thread.participantUserIds, people.count > 1 {
                    HStack(spacing: -5) {
                        ForEach(people.prefix(3), id: \.self) { id in
                            Avatar(name: id == "user_ines" ? "Ines Okafor" : id == "user_demo" ? "Camden Rose" : id, size: 16)
                                .overlay(Circle().stroke(HP.canvas, lineWidth: 1.5))
                        }
                    }
                }
            }
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }
}

struct ProjectBadge: View {
    let project: Project?

    var body: some View {
        Text(String((project?.taskCode ?? project?.name ?? "P").prefix(2)).uppercased())
            .font(.mono(8.5, weight: .bold))
            .foregroundStyle(HP.ink2)
            .frame(width: 18, height: 18)
            .background(HP.control, in: .rect(cornerRadius: 5, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// T3-style trailing status: a colored word for anything that needs eyes, a quiet timestamp otherwise.
struct ThreadStatusWord: View {
    let thread: AgentThread

    var body: some View {
        switch thread.status {
        case .running, .queued:
            if thread.isPreparing {
                label("Starting", glyph: .running, tint: HP.running).shimmer()
            } else if thread.status == .queued {
                label("Queued", glyph: .queued, tint: HP.ink3)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    label("Working \(Format.elapsed(since: thread.runStartedAt.flatMap(ISO8601.parse)))", glyph: .running, tint: HP.running)
                }
            }
        case .blocked:
            label("Needs input", glyph: .blocked, tint: HP.waiting)
        case .waiting:
            label(thread.waitingOn?.first == "checks" ? "CI running" : "Waiting", glyph: .waiting, tint: HP.waiting)
        case .failed:
            label("Failed", glyph: .failed, tint: HP.failed)
        default:
            if thread.pullRequest?.isReadyToMerge == true {
                label("Ready to merge", glyph: .ready, tint: HP.ready)
            } else {
                Text(Format.relative(thread.updated)).font(.mono(12)).foregroundStyle(HP.ink3)
            }
        }
    }

    private func label(_ text: String, glyph: ThreadStatus, tint: Color) -> some View {
        HStack(spacing: 5) {
            StatusGlyph(status: glyph, size: 12)
            Text(text).font(.ui(13, weight: .semibold)).foregroundStyle(tint).monospacedDigit()
        }
    }
}

func phaseLabel(_ phase: String?) -> String {
    switch phase {
    case "provisioning_workspace": "Provisioning workspace"
    case "resolving_repository": "Resolving repository"
    case "allocating_sandbox": "Allocating sandbox"
    case "fetching_repository": "Cloning repository"
    case "configuring_workspace": "Running setup script"
    case "dispatching_run": "Starting agent"
    default: "Preparing workspace"
    }
}

private struct SkeletonRow: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle().fill(HP.control).frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4).fill(HP.control).frame(height: 14)
                RoundedRectangle(cornerRadius: 4).fill(HP.control.opacity(0.6)).frame(width: 160, height: 12)
            }
        }
        .padding(.vertical, 10)
        .shimmer()
    }
}

struct ProjectPicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Picker("Project", selection: $model.selectedProjectId) {
            Label("All projects", systemImage: "square.grid.2x2").tag(String?.none)
            ForEach(model.projects) { project in
                Label(project.name, systemImage: "folder").tag(Optional(project.id))
            }
        }
    }
}

struct ArchivedThreadsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            ForEach(model.archived) { thread in
                NavigationLink(value: thread.id) { ThreadRow(thread: thread) }
                    .navigationLinkIndicatorVisibility(.hidden)
                    .listRowBackground(Color.clear)
                    .contextMenu { ThreadContextMenu(thread: thread) }
            }
            if model.archived.isEmpty {
                EmptyState(icon: "archivebox", title: "No archived threads").listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(HP.canvas)
        .navigationTitle("Archived")
        .task { await model.loadArchived() }
        .refreshable { await model.loadArchived() }
    }
}
