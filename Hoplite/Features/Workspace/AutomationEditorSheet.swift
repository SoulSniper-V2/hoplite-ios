import SwiftUI

enum AutomationEvents {
    static let options: [(kind: String, label: String)] = [
        ("github.pull_request.opened", "GitHub: pull request opened"),
        ("github.pull_request.updated", "GitHub: pull request updated"),
        ("github.pull_request.changes_requested", "GitHub: changes requested"),
        ("github.pull_request.merged", "GitHub: pull request merged"),
        ("github.pull_request.closed", "GitHub: pull request closed"),
        ("github.check_run.failed", "GitHub: check run failed"),
        ("linear.issue.created", "Linear: issue created"),
        ("linear.issue.status_changed", "Linear: status changed"),
        ("linear.issue.label_added", "Linear: label added"),
        ("hoplite.thread.finished", "Hoplite: thread finished"),
    ]

    static func label(_ kind: String) -> String {
        if let known = options.first(where: { $0.kind == kind }) { return known.label }
        let parts = kind.split(separator: ".").map(String.init)
        return (parts.first?.capitalized ?? kind) + ": " + parts.dropFirst().joined(separator: " ").replacingOccurrences(of: "_", with: " ")
    }
}

struct AutomationEditorSheet: View {
    enum Mode {
        case create
        case edit(Automation)
    }

    private enum Frequency: String, CaseIterable, Identifiable {
        case interval, daily, weekly, cron
        var id: String { rawValue }
        var label: String {
            switch self {
            case .interval: "Every few hours"
            case .daily: "Daily"
            case .weekly: "Weekly"
            case .cron: "Custom cron"
            }
        }
    }

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let mode: Mode
    var template: AutomationTemplate? = nil
    let onSaved: (Automation) -> Void

    @State private var projectId: String?
    @State private var name = ""
    @State private var prompt = ""
    @State private var enabled = true
    @State private var isSchedule = true
    @State private var frequency = Frequency.daily
    @State private var time = Calendar.current.date(from: DateComponents(hour: 9, minute: 0)) ?? .now
    @State private var weekday = 1
    @State private var intervalMinutes = 60
    @State private var cron = "0 9 * * *"
    @State private var timezone = TimeZone.current.identifier
    @State private var eventKind: String?
    @State private var repo: String?
    @State private var repos: [ProjectRepo] = []
    @State private var modelId: String?
    @State private var showModels = false
    @State private var saving = false
    @State private var created: AutomationCreateResult?
    @State private var error: String?

    private var existing: Automation? { if case .edit(let automation) = mode { automation } else { nil } }

    private var expression: String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        let base = "\(parts.minute ?? 0) \(parts.hour ?? 9)"
        switch frequency {
        case .daily: return "\(base) * * *"
        case .weekly: return "\(base) * * \(weekday)"
        case .cron: return cron.trimmingCharacters(in: .whitespaces)
        case .interval: return ""
        }
    }

    private var scheduleValid: Bool {
        guard isSchedule, frequency == .cron else { return true }
        return expression.split(separator: " ").count == 5
    }

    private var canSave: Bool {
        projectId != nil && !name.trimmingCharacters(in: .whitespaces).isEmpty && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && scheduleValid
    }

    private var intervalChoices: [Int] { Array(Set([60, 120, 360, 720, intervalMinutes])).sorted() }

    var body: some View {
        NavigationStack {
            Form {
                if existing == nil {
                    Section("Project") {
                        Picker("Project", selection: $projectId) {
                            ForEach(app.projects) { Text($0.name).tag(String?.some($0.id)) }
                        }
                    }
                }

                Section("Automation") {
                    TextField("Name", text: $name).accessibilityIdentifier("automationName")
                    TextField("What should the agent do each time?", text: $prompt, axis: .vertical)
                        .lineLimit(4...12)
                        .accessibilityIdentifier("automationPrompt")
                }

                Section {
                    if existing == nil {
                        Picker("Trigger", selection: $isSchedule) {
                            Text("Schedule").tag(true)
                            Text("Event").tag(false)
                        }
                        .pickerStyle(.segmented)
                    }
                    if isSchedule { scheduleFields } else { eventFields }
                } header: {
                    Text("Trigger")
                } footer: {
                    if !isSchedule && eventKind == nil {
                        Text("Hoplite gives you a URL and bearer token once after you create it. POST to it from any system to start a run.")
                    } else if !isSchedule {
                        Text("Sentry and Slack triggers need an integration set up in the Hoplite web app.")
                    } else if frequency != .interval {
                        Text("\(Automation.describeCron(expression)) · \(timezone)")
                    }
                }

                Section("Run") {
                    if repos.count > 1 || repo != nil {
                        Picker("Repository", selection: $repo) {
                            Text("Project default").tag(String?.none)
                            ForEach(repos) { Text($0.repoFullName).tag(String?.some($0.repoFullName)) }
                        }
                    }
                    LabeledContent("Model") { ModelChip(selected: modelId) { showModels = true } }
                    Toggle("Enabled", isOn: $enabled).tint(HP.action)
                }

                if let error { FormError(message: error) }
            }
            .adminList()
            .navigationTitle(existing == nil ? "New automation" : "Edit automation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { SaveToolbar(label: existing == nil ? "Create" : "Save", canSave: canSave, saving: saving) { Task { await save() } } }
            .task { populate() }
            .task(id: projectId) { await loadRepos() }
        }
        .adminSheet()
        .presentationDetents([.large])
        .sheet(isPresented: $showModels) { ModelPickerSheet(selected: $modelId) }
        .sheet(item: $created) { result in
            SecretRevealSheet(
                title: "Webhook trigger",
                message: "Copy the token now. Hoplite shows it once and can't retrieve it later.",
                rows: [("Endpoint", result.webhookUrl ?? "https://api.hoplite.sh/api/automations/webhooks"), ("Bearer token", result.webhookToken ?? "")]
            ) { dismiss() }
        }
    }

    @ViewBuilder private var scheduleFields: some View {
        Picker("Repeats", selection: $frequency) {
            ForEach(Frequency.allCases) { Text($0.label).tag($0) }
        }
        switch frequency {
        case .interval:
            Picker("Every", selection: $intervalMinutes) {
                ForEach(intervalChoices, id: \.self) { minutes in
                    Text(minutes == 60 ? "Hour" : minutes % 60 == 0 ? "\(minutes / 60) hours" : "\(minutes) minutes").tag(minutes)
                }
            }
        case .daily:
            DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
        case .weekly:
            Picker("Day", selection: $weekday) {
                ForEach(0..<7, id: \.self) { Text(Calendar.current.weekdaySymbols[$0]).tag($0) }
            }
            DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
        case .cron:
            TextField("0 9 * * 1", text: $cron)
                .font(.mono(14)).textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityIdentifier("automationCron")
        }
    }

    @ViewBuilder private var eventFields: some View {
        let known = AutomationEvents.options.map(\.kind)
        Picker("When", selection: $eventKind) {
            Text("Incoming webhook").tag(String?.none)
            ForEach(AutomationEvents.options, id: \.kind) { Text($0.label).tag(String?.some($0.kind)) }
            if let eventKind, !known.contains(eventKind) { Text(AutomationEvents.label(eventKind)).tag(String?.some(eventKind)) }
        }
    }

    private func populate() {
        guard name.isEmpty else { return }
        if let automation = existing {
            projectId = automation.projectId
            name = automation.name
            prompt = automation.prompt
            enabled = automation.enabled
            repo = automation.repoFullName
            modelId = automation.modelId
            isSchedule = automation.triggerKind == "schedule"
            eventKind = automation.eventKind
            if let schedule = automation.schedule { apply(schedule) }
        } else {
            projectId = app.selectedProjectId ?? app.projects.first?.id
            if let template {
                name = template.name
                prompt = template.prompt
                isSchedule = template.schedule != nil
                if let expression = template.schedule { apply(AutomationSchedule(mode: "cron", expression: expression, timezone: timezone)) }
            }
        }
    }

    private func apply(_ schedule: AutomationSchedule) {
        timezone = schedule.timezone ?? timezone
        if schedule.mode == "interval", let ms = schedule.intervalMs {
            frequency = .interval
            intervalMinutes = max(Int(ms / 60_000), 1)
            return
        }
        let expression = schedule.expression ?? ""
        cron = expression
        frequency = .cron
        let fields = expression.split(separator: " ").map(String.init)
        guard fields.count == 5, let minute = Int(fields[0]), let hour = Int(fields[1]), fields[2] == "*", fields[3] == "*" else { return }
        time = Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? time
        if fields[4] == "*" {
            frequency = .daily
        } else if let day = Int(fields[4]), (0...6).contains(day) {
            frequency = .weekly
            weekday = day
        }
    }

    private func loadRepos() async {
        guard let projectId, let admin = app.admin else { return }
        repos = (try? await admin.projectRepositories(projectId: projectId)) ?? []
    }

    private func save() async {
        guard let admin = app.admin, let projectId else { return }
        saving = true
        defer { saving = false }
        let trigger: AutomationDraft.Trigger
        if !isSchedule {
            trigger = .event(eventKind)
        } else if frequency == .interval {
            trigger = .schedule(AutomationSchedule(mode: "interval", intervalMs: Double(intervalMinutes) * 60_000))
        } else {
            trigger = .schedule(AutomationSchedule(mode: "cron", expression: expression, timezone: timezone))
        }
        let draft = AutomationDraft(name: name, prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines), enabled: enabled, trigger: trigger, repoFullName: repo, modelId: modelId)
        do {
            if let existing {
                onSaved(try await admin.updateAutomation(projectId: projectId, id: existing.id, draft: draft))
                dismiss()
            } else {
                let result = try await admin.createAutomation(projectId: projectId, draft: draft)
                onSaved(result.automation)
                if result.webhookToken != nil { created = result } else { dismiss() }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

extension AutomationCreateResult: Identifiable {
    var id: String { automation.id }
}
