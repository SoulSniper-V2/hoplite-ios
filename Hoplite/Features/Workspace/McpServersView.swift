import SwiftUI

struct McpServersView: View {
    @Environment(AppModel.self) private var app
    var project: WorkspaceProject?
    @State private var servers: [McpServer] = []
    @State private var loading = true
    @State private var error: String?
    @State private var editing: McpTarget?
    @State private var pendingDelete: McpServer?

    private var visible: [McpServer] {
        guard let project else { return servers }
        return servers.filter { $0.projectId == nil || $0.projectId == project.id }
    }

    var body: some View {
        List {
            if let error { LoadErrorRow(message: error) { Task { await load() } } }
            if loading && servers.isEmpty {
                SpinnerRow()
            } else if visible.isEmpty && error == nil {
                EmptyState(icon: "puzzlepiece.extension", title: "No MCP servers", message: "Connect tools like Linear, Sentry or your own docs search so agents can call them.", action: ("Add server", { editing = .new }))
                    .emptyRow()
            }
            if !visible.isEmpty {
                Section {
                    ForEach(visible) { server in
                        Button { editing = .edit(server) } label: { McpRow(server: server) }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = server }
                            }
                    }
                } footer: {
                    Text("Credentials are encrypted and masked. Remote servers only; agents can't reach local stdio servers.")
                }
            }
        }
        .adminList()
        .navigationTitle(project == nil ? "MCP servers" : "MCP")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("Add server", systemImage: "plus") { editing = .new } }
        }
        .sheet(item: $editing) { target in
            McpServerSheet(target: target, defaultProjectId: project?.id) { saved in
                withAnimation(.snappy) {
                    if let index = servers.firstIndex(where: { $0.id == saved.id }) { servers[index] = saved } else { servers.append(saved) }
                }
            } onDeleted: { id in
                withAnimation(.snappy) { servers.removeAll { $0.id == id } }
            }
        }
        .confirmationDialog("Delete \(pendingDelete?.name ?? "server")?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
            Button("Delete server", role: .destructive) {
                if let server = pendingDelete { Task { await delete(server) } }
            }
        } message: {
            Text("Agents lose its tools on their next run.")
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard let admin = app.admin else { return }
        defer { loading = false }
        do {
            let loaded = try await admin.mcpServers()
            withAnimation(.snappy) { servers = loaded }
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func delete(_ server: McpServer) async {
        guard let admin = app.admin else { return }
        do {
            try await admin.deleteMcpServer(id: server.id)
            withAnimation(.snappy) { servers.removeAll { $0.id == server.id } }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct McpRow: View {
    @Environment(AppModel.self) private var app
    let server: McpServer

    var body: some View {
        HStack(spacing: 14) {
            IconTile(systemName: "puzzlepiece.extension", tint: server.isEnabled ? HP.action : HP.ink3)
            VStack(alignment: .leading, spacing: 4) {
                Text(server.name).font(.ui(16, weight: .medium)).foregroundStyle(server.isEnabled ? HP.ink : HP.ink2)
                Text(server.url.flatMap { URL(string: $0)?.host() } ?? server.transport)
                    .font(.mono(12)).foregroundStyle(HP.ink3).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 5) {
                if !server.isEnabled {
                    StatusTag(text: "Paused")
                } else if server.needsSignIn {
                    StatusTag(text: "Needs sign-in", tint: HP.waiting)
                }
                Text(server.projectId.map { app.projectName($0) } ?? "Organization").font(.hpCaption).foregroundStyle(HP.ink3).lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
    }
}

enum McpTarget: Identifiable {
    case new
    case edit(McpServer)

    var id: String {
        switch self {
        case .new: "new"
        case .edit(let server): server.id
        }
    }
}

struct McpServerSheet: View {
    private enum AuthMode: String, CaseIterable, Identifiable {
        case keep, none, bearer, header
        var id: String { rawValue }
        var label: String {
            switch self {
            case .keep: "Keep current"
            case .none: "None"
            case .bearer: "Bearer token"
            case .header: "Custom header"
            }
        }
    }

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let target: McpTarget
    let defaultProjectId: String?
    let onSaved: (McpServer) -> Void
    let onDeleted: (String) -> Void
    @State private var name = ""
    @State private var url = ""
    @State private var transport = "http"
    @State private var projectId: String?
    @State private var enabled = true
    @State private var mode = AuthMode.none
    @State private var token = ""
    @State private var headerName = ""
    @State private var headerValue = ""
    @State private var projects: [WorkspaceProject] = []
    @State private var saving = false
    @State private var confirmDelete = false
    @State private var error: String?

    private var existing: McpServer? { if case .edit(let server) = target { server } else { nil } }
    private var modes: [AuthMode] { existing == nil ? [.none, .bearer, .header] : AuthMode.allCases }

    private var parsedURL: URL? {
        guard let parsed = URL(string: url.trimmingCharacters(in: .whitespaces)), ["http", "https"].contains(parsed.scheme), parsed.host() != nil else { return nil }
        return parsed
    }

    private var credentialsValid: Bool {
        switch mode {
        case .keep, .none: true
        case .bearer: !token.isEmpty
        case .header: !headerName.isEmpty && !headerValue.isEmpty
        }
    }

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && parsedURL != nil && credentialsValid }

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("Name", text: $name).accessibilityIdentifier("mcpName")
                    TextField("URL", text: $url, prompt: Text(verbatim: "https://mcp.example.com/mcp"))
                        .font(.mono(14)).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("mcpURL")
                    Picker("Transport", selection: $transport) {
                        Text("HTTP").tag("http")
                        Text("SSE").tag("sse")
                    }
                    .pickerStyle(.segmented)
                }

                if existing == nil {
                    Section {
                        Picker("Scope", selection: $projectId) {
                            Text("Organization").tag(String?.none)
                            ForEach(projects) { Text($0.name).tag(String?.some($0.id)) }
                        }
                    } footer: {
                        Text("Organization servers are available to every project.")
                    }
                }

                Section {
                    Picker("Authentication", selection: $mode) {
                        ForEach(modes) { Text($0.label).tag($0) }
                    }
                    switch mode {
                    case .bearer:
                        SecureField("Token", text: $token).font(.mono(14))
                    case .header:
                        TextField("Header name", text: $headerName).font(.mono(14)).textInputAutocapitalization(.never).autocorrectionDisabled()
                        SecureField("Header value", text: $headerValue).font(.mono(14))
                    case .keep:
                        if existing?.usesOAuth == true {
                            Text("Signed in with OAuth. Reconnect from the Hoplite web app.").font(.hpFootnote).foregroundStyle(HP.ink3)
                        } else if !(existing?.headerNames.isEmpty ?? true) {
                            Text("Sends \(existing?.headerNames.joined(separator: ", ") ?? "") (masked).").font(.hpFootnote).foregroundStyle(HP.ink3)
                        }
                    case .none:
                        EmptyView()
                    }
                } header: {
                    Text("Credentials")
                } footer: {
                    Text("Secrets are encrypted at rest and can't be read back.")
                }

                Section {
                    Toggle("Enabled", isOn: $enabled).tint(HP.action)
                }

                if let error { FormError(message: error) }

                if existing != nil {
                    Section {
                        Button("Delete server", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .adminList()
            .navigationTitle(existing == nil ? "Add MCP server" : "Edit server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { SaveToolbar(label: existing == nil ? "Add" : "Save", canSave: canSave, saving: saving) { Task { await save() } } }
            .confirmationDialog("Delete \(existing?.name ?? "server")?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete server", role: .destructive) { Task { await delete() } }
            } message: {
                Text("Agents lose its tools on their next run.")
            }
            .task {
                populate()
                projects = (try? await app.admin?.workspaceProjects()) ?? []
            }
        }
        .adminSheet()
        .presentationDetents([.large])
    }

    private func populate() {
        guard name.isEmpty else { return }
        projectId = defaultProjectId
        guard let existing else { return }
        name = existing.name
        url = existing.url ?? ""
        transport = existing.transport == "sse" ? "sse" : "http"
        enabled = existing.isEnabled
        projectId = existing.projectId
        mode = .keep
    }

    private func save() async {
        guard let admin = app.admin else { return }
        saving = true
        defer { saving = false }
        let auth: McpServerDraft.Auth = switch mode {
        case .keep: .keep
        case .none: .none
        case .bearer: .bearer(token: token)
        case .header: .header(name: headerName, value: headerValue)
        }
        let draft = McpServerDraft(name: name.trimmingCharacters(in: .whitespaces), projectId: projectId, transport: transport, url: parsedURL?.absoluteString ?? url, auth: auth, enabled: enabled)
        do {
            if let existing {
                onSaved(try await admin.updateMcpServer(id: existing.id, draft: draft))
            } else {
                onSaved(try await admin.createMcpServer(draft))
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func delete() async {
        guard let admin = app.admin, let existing else { return }
        do {
            try await admin.deleteMcpServer(id: existing.id)
            onDeleted(existing.id)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
