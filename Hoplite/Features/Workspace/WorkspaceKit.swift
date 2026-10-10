import SwiftUI
import UIKit

extension AppModel {
    var admin: (any WorkspaceAdmin)? { service as? any WorkspaceAdmin }
}

/// The destinations of the Workspace section in Account.
enum WorkspaceRoute: String, Hashable, CaseIterable {
    case projects, env, mcp, webhooks, accounts, about

    var title: String {
        switch self {
        case .projects: "Projects"
        case .env: "Environment"
        case .mcp: "MCP servers"
        case .webhooks: "Webhooks"
        case .accounts: "Service accounts"
        case .about: "About this workspace"
        }
    }

    var icon: String {
        switch self {
        case .projects: "folder"
        case .env: "key.viewfinder"
        case .mcp: "puzzlepiece.extension"
        case .webhooks: "paperplane"
        case .accounts: "person.badge.key"
        case .about: "info.circle"
        }
    }

    @ViewBuilder var destination: some View {
        switch self {
        case .projects: WorkspaceProjectsView()
        case .env: EnvironmentProjectsView()
        case .mcp: McpServersView()
        case .webhooks: WebhooksView()
        case .accounts: ServiceAccountsView()
        case .about: AboutWorkspaceView()
        }
    }
}

// MARK: Shared pieces

struct IconTile: View {
    let systemName: String
    var tint: Color = HP.action
    var size: CGFloat = 38

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.4, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.12), in: .rect(cornerRadius: size * 0.29, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct StatusTag: View {
    let text: String
    var tint: Color = HP.ink2

    var body: some View {
        Text(text)
            .font(.hpCaption)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12), in: .capsule)
    }
}

struct FormError: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.circle.fill")
            .font(.hpFootnote)
            .foregroundStyle(HP.failed)
            .listRowBackground(Color.clear)
    }
}

/// Banner row for a failed load, shown at the top of a list.
struct LoadErrorRow: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ErrorBanner(message: message, retry: retry)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            .listRowSeparator(.hidden)
    }
}

struct SpinnerRow: View {
    var body: some View {
        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 24).listRowBackground(Color.clear)
    }
}

extension View {
    func adminList() -> some View {
        self.font(.hpCallout).scrollContentBackground(.hidden).scrollDismissesKeyboard(.interactively).background(HP.canvas)
    }

    func adminSheet() -> some View {
        self.presentationBackground(HP.canvas).presentationDragIndicator(.visible)
    }

    func emptyRow() -> some View {
        self.listRowBackground(Color.clear).listRowSeparator(.hidden)
    }
}

/// A text field with its label above it, for forms where several fields hold similar values.
struct LabeledField: View {
    let title: String
    @Binding var text: String
    var placeholder = ""
    var mono = false
    var multiline = false
    var keyboard: UIKeyboardType = .default
    var identifier = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.hpCaption).foregroundStyle(HP.ink3)
            TextField(placeholder, text: $text, axis: multiline ? .vertical : .horizontal)
                .font(mono ? .mono(13.5) : .hpCallout)
                .lineLimit(multiline ? 1...4 : 1...1)
                .keyboardType(keyboard)
                .textInputAutocapitalization(mono ? .never : .sentences)
                .autocorrectionDisabled(mono)
                .accessibilityIdentifier(identifier)
        }
        .padding(.vertical, 2)
    }
}

struct SaveToolbar: ToolbarContent {
    @Environment(\.dismiss) private var dismiss
    let label: String
    let canSave: Bool
    let saving: Bool
    let save: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel", systemImage: "xmark") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
            Button(action: save) {
                if saving { ProgressView() } else { Text(label) }
            }
            .buttonStyle(.glassProminent)
            .disabled(!canSave || saving)
        }
    }
}

extension AppModel {
    func projectName(_ id: String?) -> String {
        guard let id else { return "All projects" }
        return project(id)?.name ?? id
    }
}

// MARK: One-time secrets

/// Shows a credential the API will never return again, with a copy button.
struct SecretRevealSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let message: String
    let rows: [(label: String, value: String)]
    var onDone: () -> Void = {}
    @State private var copied: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(HP.waiting)
                        Text(message).font(.hpFootnote).foregroundStyle(HP.ink)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.regular.tint(HP.waiting.opacity(0.12)), in: .rect(cornerRadius: 18))

                    ForEach(rows, id: \.label) { row in
                        VStack(alignment: .leading, spacing: 10) {
                            Eyebrow(text: row.label)
                            Text(row.value)
                                .font(.mono(13.5, weight: .medium))
                                .foregroundStyle(HP.ink)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityIdentifier("secret-\(row.label)")
                            Button {
                                UIPasteboard.general.string = row.value
                                copied = row.label
                            } label: {
                                Label(copied == row.label ? "Copied" : "Copy", systemImage: copied == row.label ? "checkmark" : "doc.on.doc")
                                    .font(.ui(15, weight: .medium))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glass)
                            .controlSize(.large)
                            .contentTransition(.symbolEffect(.replace))
                            .sensoryFeedback(.success, trigger: copied)
                        }
                        .padding(16)
                        .hpCard(radius: 20, fill: HP.surface)
                    }
                }
                .padding(HP.pageGutter)
            }
            .background(HP.canvas)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done", systemImage: "checkmark") { onDone(); dismiss() } }
            }
        }
        .interactiveDismissDisabled()
        .presentationDetents([.medium, .large])
        .presentationBackground(HP.canvas)
    }
}

// MARK: Permissions

enum PermissionCatalog {
    static let resources: [(key: String, label: String, actions: [String])] = [
        ("project", "Projects", ["create", "read", "update", "delete"]),
        ("thread", "Threads", ["create", "read", "update", "delete", "stop", "retry"]),
        ("repo", "Repositories", ["read", "update"]),
        ("mcpServer", "MCP servers", ["create", "read", "update", "delete"]),
        ("modelKey", "Model keys", ["read"]),
        ("usage", "Usage", ["read"]),
        ("webhook", "Webhooks", ["create", "read", "update", "delete"]),
        ("automation", "Automations", ["create", "read", "update", "delete", "run"]),
    ]

    static func label(_ key: String) -> String { resources.first { $0.key == key }?.label ?? key }

    static var readOnly: [String: Set<String>] {
        Dictionary(uniqueKeysWithValues: resources.map { ($0.key, Set(["read"])) })
    }
}

struct PermissionChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.ui(13, weight: .medium))
                .foregroundStyle(selected ? HP.action : HP.ink2)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(selected ? HP.action.opacity(0.14) : HP.control.opacity(0.7), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: selected)
    }
}

/// Rows of grant toggles, one per resource.
struct PermissionsEditor: View {
    @Binding var permissions: [String: Set<String>]

    var body: some View {
        ForEach(PermissionCatalog.resources, id: \.key) { resource in
            VStack(alignment: .leading, spacing: 8) {
                Text(resource.label).font(.ui(15, weight: .medium)).foregroundStyle(HP.ink)
                FlowRow(spacing: 6) {
                    ForEach(resource.actions, id: \.self) { action in
                        PermissionChip(title: action, selected: permissions[resource.key]?.contains(action) == true) {
                            if permissions[resource.key]?.contains(action) == true {
                                permissions[resource.key]?.remove(action)
                            } else {
                                permissions[resource.key, default: []].insert(action)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

/// A read-only summary of grants: resource name with its actions.
struct PermissionSummary: View {
    let permissions: [String: [String]]

    var body: some View {
        let ordered = PermissionCatalog.resources.compactMap { resource in
            permissions[resource.key].flatMap { $0.isEmpty ? nil : (resource.label, $0) }
        }
        ForEach(ordered, id: \.0) { label, actions in
            VStack(alignment: .leading, spacing: 6) {
                Text(label).font(.ui(15, weight: .medium)).foregroundStyle(HP.ink)
                FlowRow(spacing: 6) {
                    ForEach(actions, id: \.self) { MetaChip(text: $0) }
                }
            }
            .padding(.vertical, 4)
        }
        if ordered.isEmpty {
            Text("No permissions granted").foregroundStyle(HP.ink3)
        }
    }
}
