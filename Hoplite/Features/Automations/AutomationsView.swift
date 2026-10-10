import SwiftUI

/// Starting points that pre-fill the editor, matching app.hoplite.sh's template list.
struct AutomationTemplate: Identifiable, Hashable {
    let id: String
    let name: String
    let summary: String
    let icon: String
    let tint: Color
    let prompt: String
    let schedule: String?

    var kindLabel: String { schedule == nil ? "Webhook" : "Schedule" }

    static let all: [AutomationTemplate] = [
        AutomationTemplate(id: "digest", name: "Daily digest", summary: "Summarize activity across your threads every morning.", icon: "clock", tint: HP.running,
                           prompt: "Summarize yesterday's activity across this project's threads: what shipped, what's blocked, and what needs a human decision. Keep it short and link each thread.", schedule: "0 9 * * *"),
        AutomationTemplate(id: "triage", name: "Issue triage", summary: "Label and prioritize new issues as they land.", icon: "line.3.horizontal.decrease", tint: HP.failed,
                           prompt: "Triage the incoming issue: reproduce it if you can, label it, estimate severity and impact, and suggest an owner. Don't change code.", schedule: nil),
        AutomationTemplate(id: "deps", name: "Dependency patrol", summary: "Check for risky updates while everyone sleeps.", icon: "checkmark.shield", tint: HP.waiting,
                           prompt: "Check this repository's dependencies for security advisories and risky upgrades. Open a PR for safe patch updates and list anything that needs review.", schedule: "0 3 * * *"),
        AutomationTemplate(id: "sentry", name: "Sentry alert triage", summary: "Investigate new or regressed errors with release and user-impact context.", icon: "exclamationmark.triangle", tint: HP.failed,
                           prompt: "Investigate the Sentry alert in the payload: find the root cause using the stack trace, release and recent commits, estimate user impact, and propose a fix.", schedule: nil),
        AutomationTemplate(id: "sazabi", name: "Sazabi issue triage", summary: "Investigate each new Sazabi issue with its report, logs, and root-cause notes.", icon: "point.3.connected.trianglepath.dotted", tint: HP.waiting,
                           prompt: "Investigate the Sazabi issue in the payload using its report and logs. Write up the root cause and a proposed fix.", schedule: nil),
    ]
}

struct AutomationsView: View {
    @Environment(AppModel.self) private var app
    @State private var automations: [String: [Automation]] = [:]
    @State private var plan: BillingPlan?
    @State private var loading = true
    @State private var creating: AutomationTemplate??
    @State private var editing: Automation?
    @State private var pendingDelete: Automation?
    @State private var deleteError: String?

    private var projects: [Project] {
        app.selectedProjectId.flatMap { id in app.projects.filter { $0.id == id } } ?? app.projects
    }
    private var isEmpty: Bool { automations.values.allSatisfy(\.isEmpty) }
    private var enabledCount: Int { automations.values.joined().filter(\.enabled).count }
    private var isFree: Bool { (plan?.plan ?? "free") == "free" }

    var body: some View {
        List {
            if loading && automations.isEmpty {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40).listRowBackground(Color.clear)
            } else if isEmpty {
                emptyCard.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }

            ForEach(projects) { project in
                if let items = automations[project.id], !items.isEmpty {
                    Section {
                        ForEach(items) { automation in
                            NavigationLink {
                                AutomationDetailView(automation: automation, onChange: { updated in
                                    automations[project.id] = automations[project.id]?.map { $0.id == updated.id ? updated : $0 }
                                }, onDelete: { removed in
                                    withAnimation(.snappy) { automations[project.id]?.removeAll { $0.id == removed.id } }
                                })
                            } label: {
                                AutomationRow(automation: automation)
                            }
                            .listRowBackground(HP.surface)
                            .listRowSeparatorTint(HP.hairline)
                            .swipeActions {
                                if app.admin != nil {
                                    Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = automation }
                                    Button("Edit", systemImage: "pencil") { editing = automation }.tint(HP.ink3)
                                }
                            }
                        }
                    } header: {
                        sectionHeader(project.name)
                    }
                }
            }

            if app.admin != nil {
                Section {
                    ForEach(AutomationTemplate.all) { template in
                        Button { creating = .some(template) } label: { TemplateRow(template: template) }
                            .buttonStyle(.plain)
                            .listRowBackground(HP.surface)
                            .listRowSeparatorTint(HP.hairline)
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Start from a template").font(.ui(18, weight: .semibold)).foregroundStyle(HP.ink)
                        Text("Pre-fills the instructions and trigger. You can edit everything before saving.").font(.ui(14)).foregroundStyle(HP.ink2)
                    }
                    .textCase(nil)
                    .padding(.top, isEmpty ? 6 : 14)
                    .padding(.bottom, 4)
                } footer: {
                    Text(isFree ? "Free · up to 3 enabled automations · schedules every 1 h at most" : "\(plan?.plan.capitalized ?? "Pro") · schedules as often as every 5 min")
                        .font(.mono(11.5))
                        .foregroundStyle(HP.ink3)
                        .padding(.top, 8)
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(14)
        .scrollContentBackground(.hidden)
        .background(HP.canvas)
        .navigationTitle("Automations")
        .toolbar {
            if isFree, !isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    Text("\(enabledCount) of 3").font(.mono(13)).foregroundStyle(HP.ink3).fixedSize()
                }
                .sharedBackgroundVisibility(.hidden)
            }
            if app.admin != nil {
                ToolbarItem(placement: .topBarTrailing) { Button("New automation", systemImage: "plus") { creating = .some(nil) } }
            }
        }
        .sheet(item: Binding(get: { creating.map { CreateRequest(template: $0) } }, set: { if $0 == nil { creating = nil } })) { request in
            AutomationEditorSheet(mode: .create, template: request.template) { created in
                withAnimation(.snappy) { automations[created.projectId, default: []].append(created) }
            }
        }
        .sheet(item: $editing) { automation in
            AutomationEditorSheet(mode: .edit(automation)) { updated in
                automations[updated.projectId] = automations[updated.projectId]?.map { $0.id == updated.id ? updated : $0 }
            }
        }
        .confirmationDialog("Delete \(pendingDelete?.name ?? "automation")?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
            Button("Delete automation", role: .destructive) {
                if let automation = pendingDelete { Task { await delete(automation) } }
            }
        } message: {
            Text("It stops running and its history is removed. Threads it already started are kept.")
        }
        .alert("Couldn't delete", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "")
        }
        .task(id: projects.map(\.id)) { await load() }
        .refreshable { await load() }
    }

    private struct CreateRequest: Identifiable {
        let template: AutomationTemplate?
        var id: String { template?.id ?? "blank" }
    }

    private var emptyCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                tile("clock", HP.running)
                tile("point.3.connected.trianglepath.dotted", HP.waiting)
            }
            VStack(spacing: 8) {
                Text("No automations yet").font(.ui(20, weight: .semibold)).foregroundStyle(HP.ink)
                Text("Run an agent on a schedule, or whenever a webhook fires. Each run starts a thread in this project.")
                    .font(.ui(15))
                    .foregroundStyle(HP.ink2)
                    .multilineTextAlignment(.center)
            }
            if app.admin != nil {
                Button { creating = .some(nil) } label: {
                    Label("New automation", systemImage: "plus")
                        .font(.ui(16, weight: .medium))
                        .foregroundStyle(HP.canvas)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(HP.ink, in: .rect(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
        .background(HP.surface, in: .rect(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(HP.hairline))
    }

    private func tile(_ icon: String, _ tint: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 50, height: 50)
            .background(HP.control, in: .rect(cornerRadius: 14, style: .continuous))
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title).font(.ui(13, weight: .semibold)).foregroundStyle(HP.ink2).textCase(nil)
    }

    private func delete(_ automation: Automation) async {
        guard let admin = app.admin else { return }
        do {
            try await admin.deleteAutomation(projectId: automation.projectId, id: automation.id)
            withAnimation(.snappy) { automations[automation.projectId]?.removeAll { $0.id == automation.id } }
        } catch {
            deleteError = error.localizedDescription
        }
    }

    private func load() async {
        guard let service = app.service else { return }
        loading = true
        async let loadedPlan = try? service.billingPlan()
        var result: [String: [Automation]] = [:]
        await withTaskGroup(of: (String, [Automation]).self) { group in
            for project in projects {
                group.addTask {
                    let items = if let admin = service as? any WorkspaceAdmin {
                        try? await admin.projectAutomations(projectId: project.id)
                    } else {
                        try? await service.automations(projectId: project.id)
                    }
                    return (project.id, items ?? [])
                }
            }
            for await (id, items) in group { result[id] = items }
        }
        plan = await loadedPlan
        withAnimation(.snappy) { automations = result; loading = false }
    }
}

private struct TemplateRow: View {
    let template: AutomationTemplate

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: template.icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(template.tint)
                .frame(width: 40, height: 40)
                .background(HP.control, in: .rect(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(template.name).font(.ui(16, weight: .medium)).foregroundStyle(HP.ink)
                    Spacer(minLength: 8)
                    Text(template.kindLabel).font(.mono(12)).foregroundStyle(HP.ink3)
                }
                Text(template.summary).font(.ui(14)).foregroundStyle(HP.ink2).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6)
        .contentShape(.rect)
    }
}

extension Automation {
    var triggerIcon: String {
        if triggerKind == "schedule" { return "calendar.badge.clock" }
        let kind = eventKind ?? ""
        if kind.hasPrefix("github") { return "arrow.triangle.pull" }
        if kind.hasPrefix("sentry") { return "ladybug" }
        if kind.hasPrefix("linear") { return "checklist" }
        if kind.hasPrefix("slack") { return "number" }
        return "antenna.radiowaves.left.and.right"
    }

    var triggerDescription: String {
        if let schedule {
            if schedule.mode == "interval", let ms = schedule.intervalMs { return "Every \(Format.duration(ms: ms))" }
            return Self.describeCron(schedule.expression ?? "")
        }
        guard let kind = eventKind else { return "Webhook" }
        let parts = kind.split(separator: ".").map(String.init)
        let source = parts.first.map { $0 == "github" ? "GitHub" : $0.capitalized } ?? "Webhook"
        return "\(source): " + parts.dropFirst().joined(separator: " ").replacingOccurrences(of: "_", with: " ")
    }

    static func describeCron(_ expression: String) -> String {
        let f = expression.split(separator: " ").map(String.init)
        guard f.count == 5, let minute = Int(f[0]), let hour = Int(f[1]) else { return expression }
        let time = Calendar.current.date(from: DateComponents(hour: hour, minute: minute)).map { $0.formatted(date: .omitted, time: .shortened) } ?? "\(hour):\(minute)"
        if f[2] == "*" && f[3] == "*" && f[4] == "*" { return "Daily at \(time)" }
        if f[2] == "*" && f[3] == "*", let day = Int(f[4]), (0...6).contains(day) {
            return "\(Calendar.current.weekdaySymbols[day])s at \(time)"
        }
        return expression
    }
}

private struct AutomationRow: View {
    let automation: Automation

    private var tint: Color {
        guard automation.enabled else { return HP.ink3 }
        return automation.triggerKind == "schedule" ? HP.running : HP.waiting
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: automation.triggerKind == "schedule" ? "clock" : automation.triggerIcon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(HP.control, in: .rect(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(automation.name).font(.ui(16, weight: .medium)).foregroundStyle(automation.enabled ? HP.ink : HP.ink2).lineLimit(1)
                    Spacer(minLength: 8)
                    if !automation.enabled {
                        Text("Paused").font(.mono(12)).foregroundStyle(HP.ink3)
                    } else if let next = automation.nextRunAt.flatMap(ISO8601.parse) {
                        Text(Format.until(next)).font(.mono(12)).foregroundStyle(HP.ink3)
                    } else if let last = automation.lastRunAt.flatMap(ISO8601.parse) {
                        Text(Format.relative(last)).font(.mono(12)).foregroundStyle(HP.ink3)
                    }
                }
                Text(automation.triggerDescription).font(.ui(14)).foregroundStyle(HP.ink2).lineLimit(1)
            }
        }
        .padding(.vertical, 6)
    }
}

struct AutomationDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State var automation: Automation
    let onChange: (Automation) -> Void
    var onDelete: (Automation) -> Void = { _ in }
    @State private var executions: [AutomationExecution] = []
    @State private var status: AutomationStatus?
    @State private var editing = false
    @State private var confirmDelete = false
    @State private var deleteError: String?
    @State private var running = false
    @State private var ranAt: Date?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: automation.triggerIcon).foregroundStyle(HP.action)
                        Text(automation.triggerDescription).font(.ui(14, weight: .medium)).foregroundStyle(HP.ink2)
                    }
                    Text(automation.name).font(.display(28, weight: .medium)).foregroundStyle(HP.ink)
                    FlowRow {
                        if let repo = automation.repoFullName { MetaChip(icon: "folder", text: repo) }
                        if let model = app.modelName(automation.modelId) { MetaChip(icon: "cpu", asset: Provider.logo(app.catalog?.model(automation.modelId)?.provider, model: automation.modelId), text: model) }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow(text: "Prompt")
                    Text(automation.prompt).font(.hpCallout).foregroundStyle(HP.ink).textSelection(.enabled)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .hpCard(radius: 20, fill: HP.surface)

                HStack(spacing: 12) {
                    Toggle(isOn: Binding(get: { automation.enabled }, set: { value in Task { await setEnabled(value) } })) {
                        Text(automation.enabled ? "Enabled" : "Paused").font(.ui(15, weight: .medium))
                    }
                    .toggleStyle(.switch)
                    .tint(HP.action)
                }
                .padding(16)
                .hpCard(radius: 20, fill: HP.surface)

                Button {
                    Task { await runNow() }
                } label: {
                    HStack {
                        if running { ProgressView().tint(.white) } else { Image(systemName: "play.fill") }
                        Text(ranAt == nil ? "Run now" : "Started a new run").font(.ui(16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(HP.action)
                .controlSize(.large)
                .disabled(running)
                .sensoryFeedback(.success, trigger: ranAt)

                if let status, let runs = status.runs30d {
                    VStack(alignment: .leading, spacing: 14) {
                        Eyebrow(text: "Last 30 days")
                        HStack(alignment: .top, spacing: 0) {
                            statColumn("Runs", runs, tint: HP.ink)
                            statColumn("Succeeded", status.succeeded30d ?? 0, tint: HP.ready)
                            statColumn("Failed", status.failed30d ?? max(runs - (status.succeeded30d ?? 0), 0), tint: (status.failed30d ?? 0) > 0 ? HP.failed : HP.ink3)
                        }
                        if let error = status.lastError {
                            Text(error).font(.hpCaption).foregroundStyle(HP.failed).lineLimit(2)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .hpCard(radius: 20, fill: HP.surface)
                }

                if let deleteError {
                    Label(deleteError, systemImage: "exclamationmark.circle.fill").font(.hpFootnote).foregroundStyle(HP.failed)
                }

                VStack(alignment: .leading, spacing: 0) {
                    Eyebrow(text: "Recent runs").padding(16)
                    ForEach(executions) { execution in
                        Divider().overlay(HP.hairline)
                        executionRow(execution)
                    }
                    if executions.isEmpty {
                        Text("No runs yet.").font(.hpFootnote).foregroundStyle(HP.ink3).padding([.horizontal, .bottom], 16)
                    }
                }
                .hpCard(radius: 20, fill: HP.surface)
            }
            .padding(HP.pageGutter)
        }
        .background(HP.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if app.admin != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Manage", systemImage: "ellipsis") {
                        Button("Edit", systemImage: "pencil") { editing = true }
                        Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    }
                }
            }
        }
        .sheet(isPresented: $editing) {
            AutomationEditorSheet(mode: .edit(automation)) { updated in
                automation = updated
                onChange(updated)
            }
        }
        .confirmationDialog("Delete \(automation.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete automation", role: .destructive) { Task { await delete() } }
        } message: {
            Text("It stops running and its history is removed. Threads it already started are kept.")
        }
        .task { await loadExecutions() }
    }

    private func statColumn(_ title: String, _ value: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value.formatted()).font(.mono(22, weight: .medium)).foregroundStyle(tint)
            Text(title).font(.hpCaption).foregroundStyle(HP.ink3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func delete() async {
        guard let admin = app.admin else { return }
        do {
            try await admin.deleteAutomation(projectId: automation.projectId, id: automation.id)
            onDelete(automation)
            dismiss()
        } catch {
            deleteError = error.localizedDescription
        }
    }

    @ViewBuilder private func executionRow(_ execution: AutomationExecution) -> some View {
        let status: ThreadStatus = switch execution.status {
        case "completed", "succeeded": .ready
        case "failed": .failed
        case "running", "queued": .running
        default: .waiting
        }
        let row = HStack(spacing: 12) {
            StatusGlyph(status: status, size: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(execution.threadTitle ?? execution.status.capitalized).font(.hpCallout).foregroundStyle(HP.ink).lineLimit(1)
                if let error = execution.error { Text(error).font(.hpCaption).foregroundStyle(HP.failed).lineLimit(1) }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.relative(ISO8601.parse(execution.createdAt))).font(.mono(11.5)).foregroundStyle(HP.ink3)
                if let ms = execution.runDurationMs { Text(Format.duration(ms: Double(ms))).font(.mono(11)).foregroundStyle(HP.ink3) }
            }
            if execution.threadId != nil { Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(HP.ink3) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        if let threadId = execution.threadId {
            NavigationLink(value: threadId) { row }.buttonStyle(.plain)
        } else {
            row
        }
    }

    private func loadExecutions() async {
        executions = (try? await app.service?.automationExecutions(projectId: automation.projectId, automationId: automation.id)) ?? []
        status = try? await app.admin?.automationStatus(projectId: automation.projectId).status(for: automation.id)
    }

    private func setEnabled(_ enabled: Bool) async {
        guard let service = app.service else { return }
        automation.enabled = enabled
        if let updated = try? await service.setAutomationEnabled(automation, enabled: enabled) {
            automation = updated
            onChange(updated)
        }
    }

    private func runNow() async {
        guard let service = app.service else { return }
        running = true
        defer { running = false }
        do {
            try await service.runAutomation(projectId: automation.projectId, automationId: automation.id)
            ranAt = .now
            await loadExecutions()
            await app.refreshThreads()
        } catch {
            app.lastError = error.localizedDescription
        }
    }
}
