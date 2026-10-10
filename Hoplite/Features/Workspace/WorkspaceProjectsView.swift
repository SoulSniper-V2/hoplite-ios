import SwiftUI

struct WorkspaceProjectsView: View {
    @Environment(AppModel.self) private var app
    @State private var projects: [WorkspaceProject] = []
    @State private var loading = true
    @State private var error: String?
    @State private var creating = false

    var body: some View {
        List {
            if let error { LoadErrorRow(message: error) { Task { await load() } } }
            if loading && projects.isEmpty {
                SpinnerRow()
            } else if projects.isEmpty && error == nil {
                EmptyState(icon: "folder", title: "No projects", message: "A project connects a GitHub repository to Hoplite so agents can work in it.", action: ("New project", { creating = true }))
                    .emptyRow()
            }
            if !projects.isEmpty {
                Section {
                    ForEach(projects) { project in
                        NavigationLink {
                            ProjectDetailView(project: project) { updated in
                                if let updated { projects = projects.map { $0.id == updated.id ? updated : $0 } } else { projects.removeAll { $0.id == project.id } }
                                Task { await app.loadEverything() }
                            }
                        } label: {
                            ProjectRow(project: project)
                        }
                    }
                }
            }
        }
        .adminList()
        .navigationTitle("Projects")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("New project", systemImage: "plus") { creating = true } }
        }
        .sheet(isPresented: $creating) {
            NewProjectSheet { project in
                withAnimation(.snappy) { projects.insert(project, at: 0) }
                Task { await app.loadEverything() }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard let admin = app.admin else { return }
        defer { loading = false }
        do {
            let loaded = try await admin.workspaceProjects()
            withAnimation(.snappy) { projects = loaded }
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct ProjectRow: View {
    let project: WorkspaceProject

    var body: some View {
        HStack(spacing: 14) {
            IconTile(systemName: "folder")
            VStack(alignment: .leading, spacing: 4) {
                Text(project.name).font(.ui(16, weight: .medium)).foregroundStyle(HP.ink)
                if let repo = project.repos?.first {
                    Text(repo.repoFullName + ((project.repos?.count ?? 0) > 1 ? " +\((project.repos?.count ?? 1) - 1)" : ""))
                        .font(.mono(12)).foregroundStyle(HP.ink3).lineLimit(1)
                } else {
                    Text("No repository").font(.hpFootnote).foregroundStyle(HP.ink3)
                }
            }
            Spacer(minLength: 8)
            if let code = project.taskCode {
                Text(code).font(.mono(11, weight: .semibold)).tracking(1).foregroundStyle(HP.ink2)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: Detail

struct ProjectDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State var project: WorkspaceProject
    let onChange: (WorkspaceProject?) -> Void
    @State private var editing = false
    @State private var editingRepos = false
    @State private var confirmDelete = false
    @State private var deleting = false
    @State private var error: String?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text(project.name).font(.display(28, weight: .medium)).foregroundStyle(HP.ink)
                    if let description = project.description, !description.isEmpty {
                        Text(description).font(.hpCallout).foregroundStyle(HP.ink2)
                    }
                    FlowRow {
                        if let code = project.taskCode { MetaChip(icon: "number", text: code) }
                        if let framework = project.framework { MetaChip(icon: "square.stack.3d.up", text: framework) }
                        if let branch = project.defaultBranch { MetaChip(icon: "arrow.triangle.branch", text: branch) }
                    }
                }
                .padding(.vertical, 6)
            }

            if let error { FormError(message: error) }

            Section("Repositories") {
                ForEach(project.repos ?? []) { repo in
                    HStack {
                        Label { Text(repo.repoFullName).font(.mono(13.5)) } icon: { Image(systemName: "shippingbox").foregroundStyle(HP.ink3) }
                        Spacer()
                        if let branch = repo.branch {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.branch").font(.system(size: 10, weight: .semibold))
                                Text(branch).font(.mono(12))
                            }
                            .foregroundStyle(HP.ink3)
                        }
                    }
                }
                Button { editingRepos = true } label: { Label("Edit repositories", systemImage: "square.and.pencil") }
            }

            Section("Agent defaults") {
                LabeledContent("Model", value: app.modelName(project.defaultModel) ?? "Workspace default")
                LabeledContent("Reasoning", value: project.reasoningEffort?.capitalized ?? "Default")
                LabeledContent("Speed", value: project.agentSpeed?.capitalized ?? "Standard")
                if let port = project.previewPort { LabeledContent("Preview port", value: String(port)) }
                if let autofix = project.prReviewAutofixDefault { LabeledContent("Autofix review comments", value: autofix ? "On" : "Off") }
            }

            Section("Scripts") {
                scriptRow("Setup", project.setupScript)
                scriptRow("Run", project.runScript)
                scriptRow("Archive", project.archiveScript)
            }

            if let spec = project.sandboxSpec, spec.defaultCpu != nil || spec.maxCpu != nil {
                Section("Sandbox") {
                    if let cpu = spec.defaultCpu, let memory = spec.defaultMemoryGiB { LabeledContent("Default", value: "\(cpu) vCPU · \(memory) GiB") }
                    if let cpu = spec.maxCpu, let memory = spec.maxMemoryGiB { LabeledContent("Maximum", value: "\(cpu) vCPU · \(memory) GiB") }
                    if let disk = spec.maxDiskGiB { LabeledContent("Disk", value: "\(disk) GiB") }
                    if let profile = spec.runtimeProfile { LabeledContent("Runtime", value: profile) }
                }
            }

            if let instructions = project.instructions, !instructions.isEmpty {
                Section("Instructions") {
                    Text(instructions).font(.hpFootnote).foregroundStyle(HP.ink).textSelection(.enabled).padding(.vertical, 4)
                }
            }

            Section("Configuration") {
                NavigationLink { EnvVarsView(project: project) } label: { Label("Environment variables", systemImage: RoutesIcon.env) }
                NavigationLink { McpServersView(project: project) } label: { Label("MCP servers", systemImage: RoutesIcon.mcp) }
            }

            Section {
                Button("Delete project", role: .destructive) { confirmDelete = true }.disabled(deleting)
            }
        }
        .adminList()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Edit") { editing = true } } }
        .sheet(isPresented: $editing) {
            ProjectEditSheet(project: project) { updated in
                project = updated
                onChange(updated)
            }
        }
        .sheet(isPresented: $editingRepos) {
            RepositoriesEditorSheet(project: project) { updated in
                project = updated
                onChange(updated)
            }
        }
        .confirmationDialog("Delete \(project.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete project", role: .destructive) { Task { await delete() } }
        } message: {
            Text("Its threads, automations and environment variables are removed. This can't be undone.")
        }
        .task { await refreshRepositories() }
    }

    private func scriptRow(_ title: String, _ command: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer(minLength: 16)
            if let command, !command.isEmpty {
                Text(command).font(.mono(12.5)).foregroundStyle(HP.codeInk).lineLimit(2).multilineTextAlignment(.trailing)
            } else {
                Text("Not set").foregroundStyle(HP.ink3)
            }
        }
    }

    private func refreshRepositories() async {
        guard let admin = app.admin, let repos = try? await admin.projectRepositories(projectId: project.id), !repos.isEmpty else { return }
        project.repos = repos
    }

    private func delete() async {
        guard let admin = app.admin else { return }
        deleting = true
        defer { deleting = false }
        do {
            try await admin.deleteProject(id: project.id)
            onChange(nil)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

enum RoutesIcon {
    static let env = WorkspaceRoute.env.icon
    static let mcp = WorkspaceRoute.mcp.icon
}

// MARK: Edit

struct ProjectEditSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let project: WorkspaceProject
    let onSaved: (WorkspaceProject) -> Void
    @State private var draft: ProjectDraft
    @State private var saving = false
    @State private var error: String?
    @State private var showModels = false

    init(project: WorkspaceProject, onSaved: @escaping (WorkspaceProject) -> Void) {
        self.project = project
        self.onSaved = onSaved
        _draft = State(initialValue: ProjectDraft(project))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("General") {
                    LabeledField(title: "Name", text: $draft.name, identifier: "projectName")
                    LabeledField(title: "Description", text: $draft.description, multiline: true)
                    LabeledField(title: "Default branch", text: $draft.defaultBranch, mono: true)
                }

                Section("Agent") {
                    LabeledContent("Model") { ModelChip(selected: draft.defaultModel) { showModels = true } }
                    Picker("Reasoning", selection: $draft.reasoningEffort) {
                        Text("Default").tag(String?.none)
                        ForEach(["low", "medium", "high", "xhigh", "max"], id: \.self) { Text($0.capitalized).tag(String?.some($0)) }
                    }
                    Picker("Speed", selection: $draft.agentSpeed) {
                        Text("Standard").tag(String?.some("standard"))
                        Text("Fast").tag(String?.some("fast"))
                    }
                }

                Section {
                    LabeledField(title: "Preview port", text: $draft.previewPort, placeholder: "3000", mono: true, keyboard: .numberPad)
                    LabeledField(title: "Setup command", text: $draft.setupScript, placeholder: "None", mono: true, multiline: true)
                    LabeledField(title: "Run command", text: $draft.runScript, placeholder: "None", mono: true, multiline: true)
                    LabeledField(title: "Archive command", text: $draft.archiveScript, placeholder: "None", mono: true, multiline: true)
                } header: {
                    Text("Sandbox")
                } footer: {
                    Text("The preview port must be between 3000 and 9999.")
                }

                Section("Instructions") {
                    TextField("Guidance every thread starts with", text: $draft.instructions, axis: .vertical).lineLimit(3...10)
                }

                if let error { FormError(message: error) }
            }
            .adminList()
            .navigationTitle("Edit project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { SaveToolbar(label: "Save", canSave: draft.isValid, saving: saving) { Task { await save() } } }
        }
        .adminSheet()
        .sheet(isPresented: $showModels) { ModelPickerSheet(selected: $draft.defaultModel) }
    }

    private func save() async {
        guard let admin = app.admin else { return }
        saving = true
        defer { saving = false }
        do {
            onSaved(try await admin.updateProject(id: project.id, draft: draft))
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: Create

struct NewProjectSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let onCreated: (WorkspaceProject) -> Void
    @State private var name = ""
    @State private var picked: PickedRepository?
    @State private var branches: [String] = []
    @State private var branch: String?
    @State private var inspection: RepoInspection?
    @State private var inspecting = false
    @State private var creating = false
    @State private var error: String?

    private var canCreate: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && picked != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Project") {
                    TextField("Name", text: $name).accessibilityIdentifier("projectName")
                }

                Section {
                    NavigationLink {
                        GitHubRepositoryPicker { choice in
                            picked = choice
                            if name.isEmpty { name = choice.repository.name }
                            Task { await loadRepository(choice) }
                        }
                    } label: {
                        if let picked {
                            Label { Text(picked.repository.fullName).font(.mono(13.5)).foregroundStyle(HP.ink) } icon: { Image(systemName: "shippingbox").foregroundStyle(HP.ink3) }
                        } else {
                            Label("Choose a repository", systemImage: "shippingbox")
                        }
                    }
                } header: {
                    Text("GitHub")
                } footer: {
                    Text("Pick from the repositories your GitHub installation can reach.")
                }

                if picked != nil {
                    Section("Branch") {
                        if branches.isEmpty {
                            ProgressView()
                        } else {
                            Picker("Base branch", selection: $branch) {
                                ForEach(branches, id: \.self) { Text($0).font(.mono(14)).tag(String?.some($0)) }
                            }
                        }
                    }

                    Section {
                        if inspecting {
                            ProgressView()
                        } else if let settings = inspection?.settings {
                            if let framework = inspection?.framework { LabeledContent("Framework", value: framework) }
                            if let port = settings.previewPort { LabeledContent("Preview port", value: String(port)) }
                            detected("Setup", settings.scripts?.setup)
                            detected("Run", settings.scripts?.run)
                            if settings.invalid == true { Label("The repository's Hoplite settings file is invalid and was ignored.", systemImage: "exclamationmark.triangle").font(.hpFootnote).foregroundStyle(HP.waiting) }
                        } else {
                            Text("No Hoplite settings found. You can set scripts after creating the project.").font(.hpFootnote).foregroundStyle(HP.ink3)
                        }
                    } header: {
                        Text("Detected")
                    } footer: {
                        Text("Hoplite reads setup and run commands from the repository.")
                    }
                }

                if let error { FormError(message: error) }
            }
            .adminList()
            .navigationTitle("New project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { SaveToolbar(label: "Create", canSave: canCreate, saving: creating) { Task { await create() } } }
        }
        .adminSheet()
        .presentationDetents([.large])
    }

    private func detected(_ title: String, _ script: RepoScript?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer(minLength: 16)
            if let command = script?.command, script?.enabled != false {
                Text(command).font(.mono(12.5)).foregroundStyle(HP.codeInk).lineLimit(2).multilineTextAlignment(.trailing)
            } else {
                Text("None").foregroundStyle(HP.ink3)
            }
        }
    }

    private func loadRepository(_ choice: PickedRepository) async {
        guard let admin = app.admin else { return }
        branches = []
        branch = choice.repository.defaultBranch
        inspection = nil
        inspecting = true
        async let loadedBranches = try? await admin.githubBranches(repositoryId: choice.repository.id)
        async let loadedInspection = try? await admin.inspectRepository(repositoryId: choice.repository.id)
        let (found, inspected) = await (loadedBranches, loadedInspection)
        guard picked == choice else { return }
        branches = found ?? [choice.repository.defaultBranch].compactMap(\.self)
        inspection = inspected
        inspecting = false
    }

    private func create() async {
        guard let admin = app.admin, let picked else { return }
        creating = true
        defer { creating = false }
        let scripts = inspection?.settings?.scripts
        let project = NewProject(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines), repositoryId: picked.repository.id, repositoryFullName: picked.repository.fullName,
            sourceControlConnectionId: picked.installation?.id, baseBranch: branch, previewPort: inspection?.settings?.previewPort,
            setupScript: scripts?.setup?.enabled == false ? nil : scripts?.setup?.command,
            runScript: scripts?.run?.enabled == false ? nil : scripts?.run?.command,
            archiveScript: scripts?.archive?.enabled == false ? nil : scripts?.archive?.command, framework: inspection?.framework
        )
        do {
            onCreated(try await admin.createProject(project))
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct PickedRepository: Hashable, Sendable {
    var repository: GitHubRepository
    var installation: GitHubInstallation?
}

/// Lists the repositories the workspace's GitHub installations can reach, grouped by account.
struct GitHubRepositoryPicker: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let onPick: (PickedRepository) -> Void
    @State private var installations: [GitHubInstallation] = []
    @State private var repositories: [GitHubRepository] = []
    @State private var query = ""
    @State private var loading = true
    @State private var error: String?

    private var groups: [(owner: String, repos: [GitHubRepository])] {
        let filtered = repositories.filter { query.isEmpty || $0.fullName.localizedCaseInsensitiveContains(query) }
        let grouped = Dictionary(grouping: filtered) { $0.fullName.split(separator: "/").first.map(String.init) ?? "" }
        return grouped.keys.sorted().map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        List {
            if let error { LoadErrorRow(message: error) { Task { await load() } } }
            if loading && repositories.isEmpty {
                SpinnerRow()
            } else if repositories.isEmpty && error == nil {
                EmptyState(icon: "link", title: "No repositories", message: "Install the Hoplite GitHub app on an account or organization to make its repositories available.", action: ("Open GitHub settings", {
                    openURL(installations.first?.managementUrl.flatMap(URL.init(string:)) ?? URL(string: "https://app.hoplite.sh")!)
                }))
                .emptyRow()
            }
            ForEach(groups, id: \.owner) { group in
                Section {
                    ForEach(group.repos) { repo in
                        Button {
                            let installation = installations.first { $0.repositories?.contains { $0.id == repo.id } == true }
                                ?? installations.first { $0.accountLogin == group.owner } ?? installations.first
                            onPick(PickedRepository(repository: repo, installation: installation))
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: repo.private == false ? "globe" : "lock").font(.system(size: 13)).foregroundStyle(HP.ink3).frame(width: 18)
                                Text(repo.name).font(.mono(14)).foregroundStyle(HP.ink)
                                Spacer()
                                if let language = repo.language { Text(language).font(.hpCaption).foregroundStyle(HP.ink3) }
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(group.owner)
                }
            }
        }
        .adminList()
        .navigationTitle("Repository")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search repositories")
        .task { await load() }
    }

    private func load() async {
        guard let admin = app.admin else { return }
        defer { loading = false }
        do {
            async let found = admin.githubInstallations()
            async let repos = admin.githubRepositories()
            (installations, repositories) = try await (found, repos)
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: Repositories

struct RepositoriesEditorSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let project: WorkspaceProject
    let onSaved: (WorkspaceProject) -> Void
    @State private var assignments: [RepoAssignment] = []
    @State private var saving = false
    @State private var error: String?
    @State private var resolving = true

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if resolving { ProgressView() }
                    ForEach(assignments) { repo in
                        HStack {
                            Label { Text(repo.repoFullName).font(.mono(13.5)) } icon: { Image(systemName: "shippingbox").foregroundStyle(HP.ink3) }
                            Spacer()
                            if let branch = repo.baseBranch { Text(branch).font(.mono(12)).foregroundStyle(HP.ink3) }
                        }
                    }
                    .onDelete { assignments.remove(atOffsets: $0) }
                    NavigationLink {
                        GitHubRepositoryPicker { choice in
                            guard !assignments.contains(where: { $0.repositoryId == choice.repository.id }) else { return }
                            assignments.append(RepoAssignment(repositoryId: choice.repository.id, repoFullName: choice.repository.fullName, baseBranch: choice.repository.defaultBranch, sourceControlConnectionId: choice.installation?.id))
                        }
                    } label: {
                        Label("Add repository", systemImage: "plus")
                    }
                } footer: {
                    Text("Swipe a repository to remove it. A project needs at least one.")
                }
                if let error { FormError(message: error) }
            }
            .adminList()
            .navigationTitle("Repositories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { SaveToolbar(label: "Save", canSave: !assignments.isEmpty && !resolving, saving: saving) { Task { await save() } } }
            .task { await resolve() }
        }
        .adminSheet()
    }

    private func resolve() async {
        defer { resolving = false }
        let known = (try? await app.admin?.githubRepositories()) ?? []
        assignments = (project.repos ?? []).compactMap { repo in
            guard let id = repo.repositoryId ?? known.first(where: { $0.fullName == repo.repoFullName })?.id else { return nil }
            return RepoAssignment(repositoryId: id, repoFullName: repo.repoFullName, baseBranch: repo.branch, sourceControlConnectionId: project.githubInstallationId)
        }
    }

    private func save() async {
        guard let admin = app.admin else { return }
        saving = true
        defer { saving = false }
        do {
            onSaved(try await admin.assignRepositories(projectId: project.id, repositories: assignments))
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
