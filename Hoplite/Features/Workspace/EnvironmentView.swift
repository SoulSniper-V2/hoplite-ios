import SwiftUI

/// Pick a project to manage its environment variables.
struct EnvironmentProjectsView: View {
    @Environment(AppModel.self) private var app
    @State private var projects: [WorkspaceProject] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        List {
            if let error { LoadErrorRow(message: error) { Task { await load() } } }
            if loading && projects.isEmpty {
                SpinnerRow()
            } else if projects.isEmpty && error == nil {
                EmptyState(icon: "key.viewfinder", title: "No projects", message: "Environment variables belong to a project. Create one first.").emptyRow()
            }
            if !projects.isEmpty {
                Section {
                    ForEach(projects) { project in
                        NavigationLink { EnvVarsView(project: project) } label: {
                            HStack(spacing: 14) {
                                IconTile(systemName: "folder")
                                Text(project.name).font(.ui(16, weight: .medium)).foregroundStyle(HP.ink)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } footer: {
                    Text("Variables are injected into every command the agent runs in that project's sandbox.")
                }
            }
        }
        .adminList()
        .navigationTitle("Environment")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard let admin = app.admin else { return }
        defer { loading = false }
        do {
            projects = try await admin.workspaceProjects()
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct EnvVarsView: View {
    @Environment(AppModel.self) private var app
    let project: WorkspaceProject
    @State private var vars: [EnvVar] = []
    @State private var loading = true
    @State private var error: String?
    @State private var editing: EnvVarTarget?
    @State private var pendingDelete: EnvVar?

    var body: some View {
        List {
            if let error { LoadErrorRow(message: error) { Task { await load() } } }
            if loading && vars.isEmpty {
                SpinnerRow()
            } else if vars.isEmpty && error == nil {
                EmptyState(icon: "key.viewfinder", title: "No variables", message: "Add secrets and configuration your sandbox needs, such as API keys or database URLs.", action: ("Add variable", { editing = .new }))
                    .emptyRow()
            }
            if !vars.isEmpty {
                Section {
                    ForEach(vars) { variable in
                        Button { editing = .replace(variable.key) } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(variable.key).font(.mono(14, weight: .medium)).foregroundStyle(HP.ink)
                                    Text("••••••••").font(.mono(12)).foregroundStyle(HP.ink3)
                                }
                                Spacer()
                                if let updated = variable.updatedAt.flatMap(ISO8601.parse) {
                                    Text(Format.relative(updated)).font(.mono(11.5)).foregroundStyle(HP.ink3)
                                }
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = variable }
                        }
                    }
                } footer: {
                    Text("Values are encrypted and never shown again. Tap a variable to replace its value; swipe to delete it.")
                }
            }
        }
        .adminList()
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("Add variable", systemImage: "plus") { editing = .new } }
        }
        .sheet(item: $editing) { target in
            EnvVarSheet(project: project, target: target) { saved in
                withAnimation(.snappy) {
                    if let index = vars.firstIndex(where: { $0.key == saved.key }) { vars[index] = saved } else { vars = (vars + [saved]).sorted { $0.key < $1.key } }
                }
            }
        }
        .confirmationDialog("Delete \(pendingDelete?.key ?? "variable")?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
            Button("Delete variable", role: .destructive) {
                if let variable = pendingDelete { Task { await delete(variable) } }
            }
        } message: {
            Text("Agents lose access to it on their next run. This can't be undone.")
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard let admin = app.admin else { return }
        defer { loading = false }
        do {
            let loaded = try await admin.envVars(projectId: project.id)
            withAnimation(.snappy) { vars = loaded.sorted { $0.key < $1.key } }
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func delete(_ variable: EnvVar) async {
        guard let admin = app.admin else { return }
        do {
            try await admin.deleteEnvVar(projectId: project.id, key: variable.key)
            withAnimation(.snappy) { vars.removeAll { $0.key == variable.key } }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

enum EnvVarTarget: Identifiable, Hashable {
    case new
    case replace(String)

    var id: String {
        switch self {
        case .new: "new"
        case .replace(let key): key
        }
    }
}

struct EnvVarSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let project: WorkspaceProject
    let target: EnvVarTarget
    let onSaved: (EnvVar) -> Void
    @State private var key = ""
    @State private var value = ""
    @State private var saving = false
    @State private var error: String?

    private var fixedKey: String? { if case .replace(let key) = target { key } else { nil } }
    private var resolvedKey: String { fixedKey ?? key }
    private var validKey: Bool { resolvedKey.wholeMatch(of: /[A-Za-z_][A-Za-z0-9_]*/) != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let fixedKey {
                        Text(fixedKey).font(.mono(14, weight: .medium))
                    } else {
                        TextField("DATABASE_URL", text: $key)
                            .font(.mono(14))
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("envKey")
                    }
                } header: {
                    Text("Key")
                } footer: {
                    if fixedKey == nil && !key.isEmpty && !validKey {
                        Text("Use letters, digits and underscores, and don't start with a digit.").foregroundStyle(HP.failed)
                    }
                }

                Section {
                    SecureField("Value", text: $value).font(.mono(14)).accessibilityIdentifier("envValue")
                } header: {
                    Text(fixedKey == nil ? "Value" : "New value")
                } footer: {
                    Text("Values are encrypted and write-only. Hoplite can't show this one again after you save.")
                }

                if let error { FormError(message: error) }
            }
            .adminList()
            .navigationTitle(fixedKey == nil ? "Add variable" : "Replace value")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { SaveToolbar(label: "Save", canSave: validKey && !value.isEmpty, saving: saving) { Task { await save() } } }
        }
        .adminSheet()
        .presentationDetents([.medium, .large])
    }

    private func save() async {
        guard let admin = app.admin else { return }
        saving = true
        defer { saving = false }
        do {
            onSaved(try await admin.setEnvVar(projectId: project.id, key: resolvedKey, value: value))
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
