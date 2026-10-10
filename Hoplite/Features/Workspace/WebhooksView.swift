import SwiftUI

enum WebhookEvents {
    static let known = [
        "run.completed", "run.failed", "run.running", "thread.updated", "thread.deleted",
        "approval.requested", "approval.resolved", "pull_request.updated", "automation.execution.updated",
    ]
}

struct WebhooksView: View {
    @Environment(AppModel.self) private var app
    @State private var webhooks: [Webhook] = []
    @State private var loading = true
    @State private var error: String?
    @State private var creating = false

    var body: some View {
        List {
            if let error { LoadErrorRow(message: error) { Task { await load() } } }
            if loading && webhooks.isEmpty {
                SpinnerRow()
            } else if webhooks.isEmpty && error == nil {
                EmptyState(icon: "paperplane", title: "No webhooks", message: "Send signed Hoplite events to your own endpoint when runs finish or approvals are requested.", action: ("New webhook", { creating = true }))
                    .emptyRow()
            }
            if !webhooks.isEmpty {
                Section {
                    ForEach(webhooks) { webhook in
                        NavigationLink {
                            WebhookDetailView(webhook: webhook) { updated in
                                if let updated { webhooks = webhooks.map { $0.id == updated.id ? updated : $0 } } else { webhooks.removeAll { $0.id == webhook.id } }
                            }
                        } label: {
                            WebhookRow(webhook: webhook)
                        }
                    }
                }
            }
        }
        .adminList()
        .navigationTitle("Webhooks")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("New webhook", systemImage: "plus") { creating = true } }
        }
        .sheet(isPresented: $creating) {
            WebhookSheet(webhook: nil) { saved in
                withAnimation(.snappy) { webhooks.insert(saved, at: 0) }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard let admin = app.admin else { return }
        defer { loading = false }
        do {
            let loaded = try await admin.webhooks()
            withAnimation(.snappy) { webhooks = loaded }
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private func eventSummary(_ types: [String]?) -> String {
    guard let types, !types.isEmpty else { return "All events" }
    return types.count == 1 ? types[0] : "\(types.count) events"
}

private struct WebhookRow: View {
    @Environment(AppModel.self) private var app
    let webhook: Webhook

    var body: some View {
        HStack(spacing: 14) {
            IconTile(systemName: "paperplane", tint: webhook.disabled ? HP.ink3 : HP.action)
            VStack(alignment: .leading, spacing: 4) {
                Text(webhook.host).font(.ui(16, weight: .medium)).foregroundStyle(webhook.disabled ? HP.ink2 : HP.ink).lineLimit(1)
                Text(webhook.path.isEmpty ? eventSummary(webhook.types) : webhook.path).font(.mono(12)).foregroundStyle(HP.ink3).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 5) {
                if webhook.disabled { StatusTag(text: "Paused") }
                Text(webhook.projectId.map { app.projectName($0) } ?? "All projects").font(.hpCaption).foregroundStyle(HP.ink3).lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: Detail

struct WebhookDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State var webhook: Webhook
    let onChange: (Webhook?) -> Void
    @State private var deliveries: [WebhookDelivery] = []
    @State private var nextCursor: String?
    @State private var loadingDeliveries = true
    @State private var editing = false
    @State private var confirmRotate = false
    @State private var confirmDelete = false
    @State private var rotated: WebhookSecret?
    @State private var redelivering: String?
    @State private var error: String?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(webhook.host).font(.display(26, weight: .medium)).foregroundStyle(HP.ink)
                    Text(webhook.url).font(.mono(12.5)).foregroundStyle(HP.ink2).textSelection(.enabled)
                    FlowRow {
                        MetaChip(icon: "folder", text: webhook.projectId.map { app.projectName($0) } ?? "All projects")
                        if let created = webhook.createdAt.flatMap(ISO8601.parse) { MetaChip(icon: "calendar", text: created.formatted(.dateTime.month(.abbreviated).day().year())) }
                    }
                }
                .padding(.vertical, 6)
                Toggle(isOn: Binding(get: { !webhook.disabled }, set: { value in Task { await setActive(value) } })) {
                    Text(webhook.disabled ? "Paused" : "Active")
                }
                .tint(HP.action)
            }

            if let error { FormError(message: error) }

            Section("Events") {
                if let types = webhook.types, !types.isEmpty {
                    FlowRow(spacing: 6) { ForEach(types, id: \.self) { MetaChip(text: $0) } }.padding(.vertical, 4)
                } else {
                    Text("Every event").foregroundStyle(HP.ink2)
                }
            }

            Section {
                if loadingDeliveries && deliveries.isEmpty { ProgressView().frame(maxWidth: .infinity) }
                ForEach(deliveries) { delivery in
                    DeliveryRow(delivery: delivery, busy: redelivering == delivery.id) { Task { await redeliver(delivery) } }
                }
                if !loadingDeliveries && deliveries.isEmpty {
                    Text("No deliveries yet.").foregroundStyle(HP.ink3)
                }
                if nextCursor != nil {
                    Button("Load more") { Task { await loadDeliveries(more: true) } }
                }
            } header: {
                Text("Deliveries")
            } footer: {
                Text("Failed deliveries are retried for 24 hours. Redeliver sends the event again with a fresh retry window.")
            }

            Section {
                Button { confirmRotate = true } label: { Label("Rotate signing secret", systemImage: "arrow.triangle.2.circlepath") }
                Button("Delete webhook", role: .destructive) { confirmDelete = true }
            } footer: {
                Text("After rotation, deliveries carry signatures from both secrets for 24 hours.")
            }
        }
        .adminList()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Edit") { editing = true } } }
        .sheet(isPresented: $editing) {
            WebhookSheet(webhook: webhook) { saved in
                webhook = saved
                onChange(saved)
            }
        }
        .sheet(item: $rotated) { secret in
            SecretRevealSheet(
                title: "New signing secret",
                message: "Copy this secret now. Hoplite shows it once and can't retrieve it later.",
                rows: [("Signing secret", secret.secret ?? "Unavailable. Rotate again to get a new secret.")]
            )
        }
        .confirmationDialog("Rotate the signing secret?", isPresented: $confirmRotate, titleVisibility: .visible) {
            Button("Rotate secret", role: .destructive) { Task { await rotate() } }
        } message: {
            Text("Update your endpoint with the new secret within 24 hours or it will reject deliveries.")
        }
        .confirmationDialog("Delete this webhook?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete webhook", role: .destructive) { Task { await delete() } }
        } message: {
            Text("Hoplite stops sending events to \(webhook.host).")
        }
        .task { await loadDeliveries(more: false) }
        .refreshable { await loadDeliveries(more: false) }
    }

    private func loadDeliveries(more: Bool) async {
        guard let admin = app.admin else { return }
        defer { loadingDeliveries = false }
        do {
            let page = try await admin.webhookDeliveries(id: webhook.id, cursor: more ? nextCursor : nil)
            withAnimation(.snappy) { deliveries = more ? deliveries + page.deliveries : page.deliveries }
            nextCursor = page.nextCursor
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func setActive(_ active: Bool) async {
        guard let admin = app.admin else { return }
        do {
            webhook = try await admin.updateWebhook(id: webhook.id, url: nil, types: nil, disabled: !active)
            onChange(webhook)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func redeliver(_ delivery: WebhookDelivery) async {
        guard let admin = app.admin else { return }
        redelivering = delivery.id
        defer { redelivering = nil }
        do {
            try await admin.redeliver(webhookId: webhook.id, deliveryId: delivery.id)
            error = nil
            await loadDeliveries(more: false)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func rotate() async {
        guard let admin = app.admin else { return }
        do {
            rotated = try await admin.rotateWebhookSecret(id: webhook.id)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func delete() async {
        guard let admin = app.admin else { return }
        do {
            try await admin.deleteWebhook(id: webhook.id)
            onChange(nil)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

extension WebhookSecret: Identifiable {
    var id: String { webhook.id }
}

private struct DeliveryRow: View {
    let delivery: WebhookDelivery
    let busy: Bool
    let redeliver: () -> Void

    private var status: ThreadStatus {
        switch delivery.state {
        case "delivered": .ready
        case "failed": .failed
        default: .waiting
        }
    }

    private var detail: String {
        var parts: [String] = []
        if let code = delivery.lastStatus { parts.append("HTTP \(code)") }
        if let attempts = delivery.attempts, attempts > 0 { parts.append(attempts == 1 ? "1 attempt" : "\(attempts) attempts") }
        if parts.isEmpty { parts.append(delivery.state.capitalized) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            StatusGlyph(status: status, size: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text(delivery.eventId).font(.mono(12.5, weight: .medium)).foregroundStyle(HP.ink).lineLimit(1)
                Text(delivery.lastError ?? detail).font(.hpCaption).foregroundStyle(delivery.lastError == nil ? HP.ink3 : HP.failed).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(Format.relative(delivery.createdAt.flatMap(ISO8601.parse))).font(.mono(11.5)).foregroundStyle(HP.ink3)
            Button(action: redeliver) {
                if busy { ProgressView() } else { Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .semibold)) }
            }
            .buttonStyle(.borderless)
            .foregroundStyle(HP.ink2)
            .disabled(busy)
            .accessibilityLabel("Redeliver")
        }
        .padding(.vertical, 2)
    }
}

// MARK: Create / edit

struct WebhookSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let webhook: Webhook?
    let onSaved: (Webhook) -> Void
    @State private var url = ""
    @State private var projectId: String?
    @State private var types: Set<String> = []
    @State private var projects: [WorkspaceProject] = []
    @State private var saving = false
    @State private var created: WebhookSecret?
    @State private var error: String?

    private var parsedURL: URL? {
        guard let parsed = URL(string: url.trimmingCharacters(in: .whitespaces)), parsed.scheme == "https", parsed.host() != nil else { return nil }
        return parsed
    }

    private var choices: [String] { WebhookEvents.known + types.subtracting(WebhookEvents.known).sorted() }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("URL", text: $url, prompt: Text(verbatim: "https://example.com/hooks/hoplite"))
                        .font(.mono(14)).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("webhookURL")
                } header: {
                    Text("Endpoint")
                } footer: {
                    Text("A public HTTPS URL that verifies the signature on each request.")
                }

                if webhook == nil {
                    Section {
                        Picker("Scope", selection: $projectId) {
                            Text("All projects").tag(String?.none)
                            ForEach(projects) { Text($0.name).tag(String?.some($0.id)) }
                        }
                    }
                }

                Section {
                    FlowRow(spacing: 6) {
                        ForEach(choices, id: \.self) { type in
                            PermissionChip(title: type, selected: types.contains(type)) {
                                if types.contains(type) { types.remove(type) } else { types.insert(type) }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Events")
                } footer: {
                    Text(types.isEmpty ? "Leave empty to receive every event." : "\(types.count) selected.")
                }

                if let error { FormError(message: error) }
            }
            .adminList()
            .navigationTitle(webhook == nil ? "New webhook" : "Edit webhook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { SaveToolbar(label: webhook == nil ? "Create" : "Save", canSave: parsedURL != nil, saving: saving) { Task { await save() } } }
            .task {
                if url.isEmpty, let webhook {
                    url = webhook.url
                    types = Set(webhook.types ?? [])
                }
                projects = (try? await app.admin?.workspaceProjects()) ?? []
            }
        }
        .adminSheet()
        .presentationDetents([.large])
        .sheet(item: $created) { secret in
            SecretRevealSheet(
                title: "Signing secret",
                message: "Copy this secret now. Hoplite shows it once and can't retrieve it later.",
                rows: [("Signing secret", secret.secret ?? "Unavailable. Rotate the secret to get a new one.")]
            ) { dismiss() }
        }
    }

    private func save() async {
        guard let admin = app.admin, let parsedURL else { return }
        saving = true
        defer { saving = false }
        do {
            if let webhook {
                onSaved(try await admin.updateWebhook(id: webhook.id, url: parsedURL.absoluteString, types: types.sorted(), disabled: nil))
                dismiss()
            } else {
                let secret = try await admin.createWebhook(url: parsedURL.absoluteString, projectId: projectId, types: types.sorted())
                onSaved(secret.webhook)
                created = secret
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
