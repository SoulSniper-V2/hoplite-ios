import SwiftUI

struct SearchView: View {
    @Environment(AppModel.self) private var app
    @State private var query = ""
    @State private var results: [AgentThread] = []
    @State private var searching = false

    var body: some View {
        List {
            if query.isEmpty {
                Section {
                    ForEach(app.threads.prefix(6)) { thread in
                        NavigationLink(value: thread.id) { ThreadRow(thread: thread) }.navigationLinkIndicatorVisibility(.hidden).listRowBackground(Color.clear)
                    }
                } header: {
                    Text("Recent").font(.ui(13, weight: .semibold)).foregroundStyle(HP.ink2).textCase(nil)
                }
            } else if results.isEmpty && !searching {
                EmptyState(icon: "magnifyingglass", title: "No matches", message: "Search covers thread titles across active and archived threads.")
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
            } else {
                ForEach(results) { thread in
                    NavigationLink(value: thread.id) { ThreadRow(thread: thread) }.navigationLinkIndicatorVisibility(.hidden).listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(HP.canvas)
        .navigationTitle("Search")
        .searchable(text: $query, prompt: "Threads, PRs, projects")
        .task(id: query) {
            guard !query.isEmpty else { results = []; return }
            searching = true
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let found = await app.search(query)
            withAnimation(.snappy) { results = found; searching = false }
        }
    }
}

struct AccountView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage("appearance") private var appearance = AppearancePreference.system
    @State private var plan: BillingPlan?
    @State private var billing: BillingSummary?
    @State private var usage: OrganizationUsage?
    @State private var confirmSignOut = false
    @State private var path: [WorkspaceRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    HStack(spacing: 14) {
                        AppIconMark(size: 48)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(app.isDemo ? "Acme" : "Your workspace").font(.display(22, weight: .medium)).foregroundStyle(HP.ink)
                            Text(app.credentialLabel).font(.mono(12)).foregroundStyle(HP.ink3)
                        }
                        Spacer()
                        if let plan {
                            Text(plan.plan.uppercased()).font(.mono(11, weight: .semibold)).tracking(1).foregroundStyle(HP.action)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(HP.action.opacity(0.12), in: .capsule)
                        }
                    }
                    .padding(.vertical, 6)
                }

                if let billing {
                    Section("Credits") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline) {
                                Text((billing.remainingCredits ?? 0).formatted(.number.precision(.fractionLength(0...1))))
                                    .font(.display(34, weight: .medium)).foregroundStyle(HP.ink)
                                Text("of \((billing.grantedCredits ?? 0).formatted()) remaining").font(.hpFootnote).foregroundStyle(HP.ink2)
                            }
                            CreditBar(used: billing.usedCredits ?? 0, held: billing.heldCredits ?? 0, total: billing.grantedCredits ?? 1)
                            if let reset = billing.nextResetAt.flatMap(ISO8601.parse) {
                                Text("Resets \(reset.formatted(.dateTime.month().day()))").font(.hpCaption).foregroundStyle(HP.ink3)
                            }
                        }
                        .padding(.vertical, 6)
                        if let usage {
                            LabeledContent("Spend this period", value: Format.dollars(micros: usage.totalCostMicros))
                            LabeledContent("Tokens", value: "\(Format.tokens(usage.inputTokens)) in · \(Format.tokens(usage.outputTokens)) out")
                        }
                        if let plan, let seats = plan.seatCount {
                            LabeledContent("Seats", value: "\(seats)")
                        }
                    }
                }

                if app.admin != nil {
                    Section("Workspace") {
                        ForEach(WorkspaceRoute.allCases, id: \.self) { route in
                            NavigationLink(value: route) { Label(route.title, systemImage: route.icon) }
                        }
                    }
                }

                Section("Appearance") {
                    Picker("Theme", selection: $appearance) {
                        ForEach(AppearancePreference.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                }

                Section("Hoplite") {
                    Button { openURL(URL(string: "https://app.hoplite.sh")!) } label: { Label("Open the web app", systemImage: "macwindow") }
                    Button { openURL(URL(string: "https://hoplite.sh/docs")!) } label: { Label("Documentation", systemImage: "book") }
                    Button { openURL(URL(string: "https://hoplite.sh/docs/api")!) } label: { Label("API reference", systemImage: "curlybraces") }
                }

                Section {
                    Button(app.isDemo ? "Leave demo" : "Sign out", role: .destructive) { confirmSignOut = true }
                } footer: {
                    Text("Hoplite for iPhone \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                        .font(.mono(11)).frame(maxWidth: .infinity).padding(.top, 12)
                }
            }
            .font(.hpCallout)
            .scrollContentBackground(.hidden)
            .background(HP.canvas)
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: WorkspaceRoute.self) { $0.destination }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done", systemImage: "checkmark") { dismiss() } } }
            .confirmationDialog(app.isDemo ? "Leave the demo workspace?" : "Sign out of Hoplite?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button(app.isDemo ? "Leave demo" : "Sign out", role: .destructive) { dismiss(); app.signOut() }
            }
            #if DEBUG
            .onAppear {
                if let value = UserDefaults.standard.string(forKey: "UITestWorkspace"), let route = WorkspaceRoute(rawValue: value), path.isEmpty { path = [route] }
            }
            #endif
            .task {
                guard let service = app.service else { return }
                async let p = try? service.billingPlan()
                async let b = try? service.billingSummary()
                async let u = try? service.organizationUsage()
                (plan, billing, usage) = await (p, b, u)
            }
        }
    }
}

private struct CreditBar: View {
    let used: Double
    let held: Double
    let total: Double

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            HStack(spacing: 2) {
                Capsule().fill(HP.action).frame(width: max(4, width * min(used / max(total, 1), 1)))
                Capsule().fill(HP.waiting).frame(width: held > 0 ? max(3, width * held / max(total, 1)) : 0)
                Capsule().fill(HP.control)
            }
        }
        .frame(height: 8)
        .accessibilityLabel("\(Int(used)) of \(Int(total)) credits used")
    }
}
