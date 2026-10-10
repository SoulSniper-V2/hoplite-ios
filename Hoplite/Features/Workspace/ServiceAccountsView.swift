import SwiftUI

private func scopeSummary(_ account: ServiceAccount) -> String {
    let grants = account.grantCount == 1 ? "1 grant" : "\(account.grantCount) grants"
    guard let ids = account.projectIds else { return "\(grants) · All projects" }
    return "\(grants) · \(ids.count == 1 ? "1 project" : "\(ids.count) projects")"
}

struct ServiceAccountsView: View {
    @Environment(AppModel.self) private var app
    @State private var accounts: [ServiceAccount] = []
    @State private var own: ServiceAccount?
    @State private var loading = true
    @State private var error: String?
    @State private var creating = false
    @State private var confirmRotateOwn = false
    @State private var rotated: ServiceAccountSecret?

    var body: some View {
        List {
            if let error { LoadErrorRow(message: error) { Task { await load() } } }

            if let own {
                Section {
                    HStack(spacing: 14) {
                        IconTile(systemName: "key.horizontal")
                        VStack(alignment: .leading, spacing: 4) {
                            Text(own.name).font(.ui(16, weight: .medium)).foregroundStyle(HP.ink)
                            Text(scopeSummary(own)).font(.hpFootnote).foregroundStyle(HP.ink2)
                        }
                    }
                    .padding(.vertical, 4)
                    Button { confirmRotateOwn = true } label: { Label("Rotate this key", systemImage: "arrow.triangle.2.circlepath") }
                } header: {
                    Text("This key")
                } footer: {
                    Text("The credential this app is signed in with. The previous key keeps working for 24 hours after rotation.")
                }
            }

            if loading && accounts.isEmpty {
                SpinnerRow()
            } else if accounts.isEmpty && error == nil {
                EmptyState(icon: "person.badge.key", title: "No service accounts", message: "Give CI, scripts and other systems their own scoped credentials instead of sharing yours.", action: ("New service account", { creating = true }))
                    .emptyRow()
            }
            if !accounts.isEmpty {
                Section {
                    ForEach(accounts) { account in
                        NavigationLink {
                            ServiceAccountDetailView(account: account) { updated in
                                accounts = accounts.map { $0.id == updated.id ? updated : $0 }
                            }
                        } label: {
                            HStack(spacing: 14) {
                                IconTile(systemName: "person.badge.key", tint: account.disabled ? HP.ink3 : HP.action)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(account.name).font(.ui(16, weight: .medium)).foregroundStyle(account.disabled ? HP.ink2 : HP.ink)
                                    Text(scopeSummary(account)).font(.hpFootnote).foregroundStyle(HP.ink2).lineLimit(1)
                                }
                                Spacer(minLength: 8)
                                if account.disabled { StatusTag(text: "Disabled") }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: {
                    Text("Accounts")
                } footer: {
                    Text("Managing service accounts needs an owner or admin session.")
                }
            }
        }
        .adminList()
        .navigationTitle("Service accounts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("New service account", systemImage: "plus") { creating = true } }
        }
        .sheet(isPresented: $creating) {
            ServiceAccountSheet(account: nil) { saved in
                withAnimation(.snappy) { accounts.insert(saved, at: 0) }
            }
        }
        .sheet(item: $rotated) { secret in
            SecretRevealSheet(title: "New API key", message: "Copy this key now. Hoplite shows it once and can't retrieve it later.", rows: [("API key", secret.key ?? "Unavailable. Rotate again to get a new key.")])
        }
        .confirmationDialog("Rotate this key?", isPresented: $confirmRotateOwn, titleVisibility: .visible) {
            Button("Rotate key", role: .destructive) { Task { await rotateOwn() } }
        } message: {
            Text("Update anything that uses the current key. It stops working after 24 hours.")
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard let admin = app.admin else { return }
        defer { loading = false }
        async let identity = try? await admin.ownServiceAccount()
        do {
            let loaded = try await admin.serviceAccounts()
            withAnimation(.snappy) { accounts = loaded }
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
        own = await identity
    }

    private func rotateOwn() async {
        guard let admin = app.admin else { return }
        do {
            rotated = try await admin.rotateOwnCredential()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

extension ServiceAccountSecret: Identifiable {
    var id: String { credential?.id ?? account.id }
}

// MARK: Detail

struct ServiceAccountDetailView: View {
    @Environment(AppModel.self) private var app
    @State var account: ServiceAccount
    let onChange: (ServiceAccount) -> Void
    @State private var credentials: [ServiceCredential] = []
    @State private var loading = true
    @State private var editing = false
    @State private var confirmRotate = false
    @State private var pendingRevoke: ServiceCredential?
    @State private var rotated: ServiceAccountSecret?
    @State private var error: String?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(account.name).font(.display(26, weight: .medium)).foregroundStyle(HP.ink)
                    FlowRow {
                        MetaChip(icon: "folder", text: account.projectIds.map { ids in ids.map { app.projectName($0) }.joined(separator: ", ") } ?? "All projects")
                        if let created = account.createdAt.flatMap(ISO8601.parse) { MetaChip(icon: "calendar", text: created.formatted(.dateTime.month(.abbreviated).day().year())) }
                    }
                }
                .padding(.vertical, 6)
                Toggle(isOn: Binding(get: { !account.disabled }, set: { value in Task { await setActive(value) } })) {
                    Text(account.disabled ? "Disabled" : "Active")
                }
                .tint(HP.action)
            }

            if let error { FormError(message: error) }

            Section("Permissions") { PermissionSummary(permissions: account.permissions) }

            Section {
                if loading && credentials.isEmpty { ProgressView().frame(maxWidth: .infinity) }
                ForEach(credentials) { credential in
                    CredentialRow(credential: credential)
                        .swipeActions {
                            if !credential.revoked {
                                Button("Revoke", systemImage: "xmark.circle", role: .destructive) { pendingRevoke = credential }
                            }
                        }
                }
                if !loading && credentials.isEmpty { Text("No credentials.").foregroundStyle(HP.ink3) }
            } header: {
                Text("Credentials")
            } footer: {
                Text("Keys expire after 90 days. Swipe an active credential to revoke it.")
            }

            Section {
                Button { confirmRotate = true } label: { Label("Rotate key", systemImage: "arrow.triangle.2.circlepath") }
            } footer: {
                Text("Issues a new key. Existing keys keep working until they expire or you revoke them.")
            }
        }
        .adminList()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Edit") { editing = true } } }
        .sheet(isPresented: $editing) {
            ServiceAccountSheet(account: account) { saved in
                account = saved
                onChange(saved)
            }
        }
        .sheet(item: $rotated) { secret in
            SecretRevealSheet(title: "New API key", message: "Copy this key now. Hoplite shows it once and can't retrieve it later.", rows: [("API key", secret.key ?? "Unavailable. Rotate again to get a new key.")]) {
                Task { await load() }
            }
        }
        .confirmationDialog("Rotate the key for \(account.name)?", isPresented: $confirmRotate, titleVisibility: .visible) {
            Button("Rotate key", role: .destructive) { Task { await rotate() } }
        } message: {
            Text("Anything using the old key keeps working until it expires or you revoke it.")
        }
        .confirmationDialog("Revoke this credential?", isPresented: Binding(get: { pendingRevoke != nil }, set: { if !$0 { pendingRevoke = nil } }), titleVisibility: .visible) {
            Button("Revoke credential", role: .destructive) {
                if let credential = pendingRevoke { Task { await revoke(credential) } }
            }
        } message: {
            Text("It stops working immediately. This can't be undone.")
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard let admin = app.admin else { return }
        defer { loading = false }
        do {
            let loaded = try await admin.serviceCredentials(accountId: account.id)
            withAnimation(.snappy) { credentials = loaded }
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func setActive(_ active: Bool) async {
        guard let admin = app.admin else { return }
        do {
            account = try await admin.setServiceAccountDisabled(id: account.id, disabled: !active)
            onChange(account)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func rotate() async {
        guard let admin = app.admin else { return }
        do {
            rotated = try await admin.rotateServiceAccount(id: account.id)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func revoke(_ credential: ServiceCredential) async {
        guard let admin = app.admin else { return }
        do {
            try await admin.revokeCredential(accountId: account.id, credentialId: credential.id)
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct CredentialRow: View {
    let credential: ServiceCredential

    private var expiry: (text: String, tint: Color)? {
        guard !credential.revoked, let date = credential.expiresAt.flatMap(ISO8601.parse) else { return nil }
        return date < .now ? ("Expired", HP.failed) : ("Expires \(Format.until(date))", HP.ink3)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "key.horizontal").foregroundStyle(credential.revoked ? HP.ink3 : HP.ink2).frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(credential.id).font(.mono(12.5, weight: .medium)).foregroundStyle(credential.revoked ? HP.ink3 : HP.ink).lineLimit(1)
                if let created = credential.createdAt.flatMap(ISO8601.parse) {
                    Text("Created \(created.formatted(.dateTime.month(.abbreviated).day()))").font(.hpCaption).foregroundStyle(HP.ink3)
                }
            }
            Spacer(minLength: 8)
            if credential.revoked {
                StatusTag(text: "Revoked")
            } else if let expiry {
                Text(expiry.text).font(.mono(11.5)).foregroundStyle(expiry.tint)
            }
        }
    }
}

// MARK: Create / edit

struct ServiceAccountSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let account: ServiceAccount?
    let onSaved: (ServiceAccount) -> Void
    @State private var name = ""
    @State private var permissions: [String: Set<String>] = [:]
    @State private var limitProjects = false
    @State private var selectedProjects: Set<String> = []
    @State private var projects: [WorkspaceProject] = []
    @State private var saving = false
    @State private var created: ServiceAccountSecret?
    @State private var error: String?

    private var grantCount: Int { permissions.values.reduce(0) { $0 + $1.count } }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && grantCount > 0 && (!limitProjects || !selectedProjects.isEmpty) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("ci-deploy-bot", text: $name).font(.mono(14)).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("accountName")
                }

                Section {
                    PermissionsEditor(permissions: $permissions)
                } header: {
                    HStack {
                        Text("Permissions")
                        Spacer()
                        Menu {
                            Button("Read only") { permissions = PermissionCatalog.readOnly }
                            Button("Clear all", role: .destructive) { permissions = [:] }
                        } label: {
                            Text("Preset").font(.hpCaption).textCase(nil)
                        }
                    }
                } footer: {
                    Text(grantCount == 0 ? "Grant at least one permission." : "\(grantCount) granted.")
                }

                Section {
                    Toggle("Limit to specific projects", isOn: $limitProjects).tint(HP.action)
                    if limitProjects {
                        ForEach(projects) { project in
                            Toggle(project.name, isOn: Binding(get: { selectedProjects.contains(project.id) }, set: { if $0 { selectedProjects.insert(project.id) } else { selectedProjects.remove(project.id) } }))
                                .tint(HP.action)
                        }
                    }
                } header: {
                    Text("Scope")
                } footer: {
                    Text(limitProjects ? "The account can only act on the selected projects." : "The account can act on every project.")
                }

                if let error { FormError(message: error) }
            }
            .adminList()
            .navigationTitle(account == nil ? "New service account" : "Edit account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { SaveToolbar(label: account == nil ? "Create" : "Save", canSave: canSave, saving: saving) { Task { await save() } } }
            .task {
                if name.isEmpty, let account {
                    name = account.name
                    permissions = account.permissions.mapValues(Set.init)
                    limitProjects = account.projectIds != nil
                    selectedProjects = Set(account.projectIds ?? [])
                }
                projects = (try? await app.admin?.workspaceProjects()) ?? []
            }
        }
        .adminSheet()
        .presentationDetents([.large])
        .sheet(item: $created) { secret in
            SecretRevealSheet(title: "API key", message: "Copy this key now. Hoplite shows it once and can't retrieve it later.", rows: [("API key", secret.key ?? "Unavailable. Rotate the account's key to get a new one.")]) { dismiss() }
        }
    }

    private func save() async {
        guard let admin = app.admin else { return }
        saving = true
        defer { saving = false }
        let draft = ServiceAccountDraft(name: name.trimmingCharacters(in: .whitespaces), permissions: permissions, projectIds: limitProjects ? selectedProjects.sorted() : nil)
        do {
            if let account {
                onSaved(try await admin.updateServiceAccount(id: account.id, draft: draft))
                dismiss()
            } else {
                let secret = try await admin.createServiceAccount(draft)
                onSaved(secret.account)
                created = secret
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
