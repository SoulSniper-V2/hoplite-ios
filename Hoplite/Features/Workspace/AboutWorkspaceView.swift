import SwiftUI

struct AboutWorkspaceView: View {
    @Environment(AppModel.self) private var app
    @State private var capabilities: FactoryCapabilities?
    @State private var health: ServiceHealth?
    @State private var healthFailed = false
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        List {
            Section { healthLine }

            if let error { LoadErrorRow(message: error) { Task { await load() } } }
            if loading && capabilities == nil { SpinnerRow() }

            if let capabilities {
                Section("Workspace") {
                    identifier("Organization", capabilities.orgId)
                    identifier("Principal", capabilities.principalId)
                    LabeledContent("Projects", value: capabilities.projectIds.map { $0.count == 1 ? "1 project" : "\($0.count) projects" } ?? "All projects")
                }

                if let availability = capabilities.availability, !availability.isEmpty {
                    Section("Availability") {
                        ForEach(availability.keys.sorted(), id: \.self) { key in
                            HStack {
                                Text(Self.humanize(key))
                                Spacer()
                                Image(systemName: availability[key] == true ? "checkmark.circle.fill" : "minus.circle")
                                    .foregroundStyle(availability[key] == true ? HP.ready : HP.ink3)
                                    .accessibilityLabel(availability[key] == true ? "Available" : "Unavailable")
                            }
                        }
                    }
                }

                if let limits = capabilities.limits {
                    Section("Limits") {
                        if let days = limits.eventRetentionDays { LabeledContent("Event retention", value: "\(days) days") }
                        if let days = limits.idempotencyRetentionDays { LabeledContent("Idempotency keys", value: "\(days) days") }
                        if let days = limits.credentialLifetimeDays { LabeledContent("Credential lifetime", value: "\(days) days") }
                        if let hours = limits.credentialOverlapHours { LabeledContent("Rotation overlap", value: "\(hours) hours") }
                        if let bytes = limits.attachmentMaxBytes { LabeledContent("Attachment size", value: bytes.formatted(.byteCount(style: .file))) }
                    }
                }

                Section("Permissions") {
                    PermissionSummary(permissions: capabilities.permissions ?? [:])
                }

                if let operations = capabilities.operations, !operations.isEmpty {
                    Section {
                        NavigationLink { OperationsListView(operations: operations) } label: {
                            LabeledContent("API operations", value: "\(operations.count)")
                        }
                    } footer: {
                        Text("Operations this credential can call.")
                    }
                }
            }
        }
        .adminList()
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private var healthLine: some View {
        HStack(spacing: 10) {
            Circle().fill(healthFailed ? HP.failed : (health?.ok == true ? HP.ready : HP.ink3)).frame(width: 8, height: 8)
            if healthFailed {
                Text("API unreachable").foregroundStyle(HP.ink)
            } else if let health {
                Text("API healthy").foregroundStyle(HP.ink)
                if let version = health.version { Text(version).font(.mono(12)).foregroundStyle(HP.ink3) }
            } else {
                Text("Checking API").foregroundStyle(HP.ink2)
            }
            Spacer()
            if let service = health?.service { Text(service).font(.mono(11.5)).foregroundStyle(HP.ink3) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("healthLine")
    }

    private func identifier(_ title: String, _ value: String) -> some View {
        LabeledContent(title) { Text(value).font(.mono(12.5)).textSelection(.enabled) }
    }

    private static func humanize(_ key: String) -> String {
        var words = ""
        for character in key {
            if character.isUppercase { words += " " }
            words += String(character).lowercased()
        }
        let spaced = words.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
        return spaced.split(separator: " ").map { $0 == "mcp" ? "MCP" : String($0) }.joined(separator: " ").capitalizedFirst
    }

    private func load() async {
        guard let admin = app.admin else { return }
        defer { loading = false }
        async let status = try? await admin.health()
        do {
            let loaded = try await admin.capabilities()
            withAnimation(.snappy) { capabilities = loaded }
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
        health = await status
        healthFailed = health == nil
    }
}

private struct OperationsListView: View {
    let operations: [FactoryOperation]
    @State private var query = ""

    private var filtered: [FactoryOperation] {
        query.isEmpty ? operations : operations.filter { $0.operationId.localizedCaseInsensitiveContains(query) || $0.path.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        List {
            ForEach(filtered) { operation in
                VStack(alignment: .leading, spacing: 5) {
                    Text(operation.operationId).font(.ui(15, weight: .medium)).foregroundStyle(HP.ink)
                    HStack(spacing: 8) {
                        Text(operation.method).font(.mono(11, weight: .semibold)).foregroundStyle(HP.action)
                        Text(operation.path).font(.mono(11.5)).foregroundStyle(HP.ink3).lineLimit(1)
                    }
                    if let permission = operation.permission { Text(permission).font(.mono(11)).foregroundStyle(HP.ink2) }
                }
                .padding(.vertical, 2)
            }
        }
        .adminList()
        .navigationTitle("Operations")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search operations")
    }
}
