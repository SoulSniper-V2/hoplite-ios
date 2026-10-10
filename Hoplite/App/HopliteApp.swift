import SwiftUI

@main
struct HopliteApp: App {
    @State private var model = AppModel()
    @AppStorage("appearance") private var appearance = AppearancePreference.system

    init() {
        Appearance.configure()
        #if DEBUG
        if UserDefaults.standard.string(forKey: "UITestWorkspace") != nil { UserDefaults.standard.register(defaults: ["UITestAccount": true]) }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(HP.ink)
                .preferredColorScheme(appearance.colorScheme)
                .task { if model.phase == .launching { model.bootstrap() } }
        }
    }
}

enum AppearancePreference: String, CaseIterable, Identifiable {
    case system, dark, light
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .dark: .dark
        case .light: .light
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            HP.canvas.ignoresSafeArea()
            switch model.phase {
            case .launching:
                AppIconMark(size: 64)
            case .signedOut:
                OnboardingView().transition(.opacity)
            case .signedIn:
                MainTabs().transition(.opacity.combined(with: .scale(scale: 1.02)))
            }
        }
    }
}

enum AppTab: Hashable { case threads, inbox, automations, search }

struct MainTabs: View {
    @Environment(AppModel.self) private var model
    @State private var tab = AppTab.threads
    @State private var threadsPath: [String] = []
    @State private var inboxPath: [String] = []

    var body: some View {
        @Bindable var model = model
        TabView(selection: $tab) {
            Tab("Threads", systemImage: "square.stack.3d.up", value: AppTab.threads) {
                NavigationStack(path: $threadsPath) {
                    ThreadsView()
                        .navigationDestination(for: String.self) { ThreadView(threadId: $0) }
                }
            }
            Tab("Inbox", systemImage: "tray", value: AppTab.inbox) {
                NavigationStack(path: $inboxPath) {
                    InboxView()
                        .navigationDestination(for: String.self) { ThreadView(threadId: $0) }
                }
            }
            .badge(model.attentionCount)
            Tab("Automations", systemImage: "bolt.horizontal", value: AppTab.automations) {
                NavigationStack {
                    AutomationsView()
                        .navigationDestination(for: String.self) { ThreadView(threadId: $0) }
                }
            }
            Tab(value: AppTab.search, role: .search) {
                NavigationStack {
                    SearchView()
                        .navigationDestination(for: String.self) { ThreadView(threadId: $0) }
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory(isEnabled: !model.liveThreads.isEmpty && model.openThreadId == nil) {
            LiveRunsAccessory { id in
                tab = .threads
                threadsPath = [id]
            }
        }
        #if DEBUG
        .task {
            let defaults = UserDefaults.standard
            if let value = defaults.string(forKey: "UITestTab") {
                tab = ["inbox": .inbox, "automations": .automations, "search": .search][value] ?? .threads
            }
            if let thread = defaults.string(forKey: "UITestThread") {
                while model.threads.isEmpty { try? await Task.sleep(for: .milliseconds(100)) }
                try? await Task.sleep(for: .milliseconds(700))
                for _ in 0..<5 where model.openThreadId != thread {
                    threadsPath = []
                    threadsPath = [thread]
                    try? await Task.sleep(for: .seconds(1))
                }
            }
            if defaults.bool(forKey: "UITestCompose") {
                while model.projects.isEmpty { try? await Task.sleep(for: .milliseconds(100)) }
                try? await Task.sleep(for: .milliseconds(700))
                model.composingNewThread = true
            }
        }
        #endif
        .onOpenURL { url in
            guard url.scheme == "hoplite-ios", url.host() == "thread", let id = url.pathComponents.dropFirst().first else { return }
            tab = .threads
            threadsPath = [id]
        }
        .sheet(isPresented: $model.composingNewThread) {
            NewThreadSheet { thread in
                tab = .threads
                threadsPath = [thread.id]
            }
        }
    }
}

/// The "now playing" bar for agents: what's running right now, one tap away from any tab.
struct LiveRunsAccessory: View {
    @Environment(AppModel.self) private var model
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    let open: (String) -> Void

    var body: some View {
        let live = model.liveThreads
        if let first = live.first {
            Button { open(first.id) } label: {
                HStack(spacing: 10) {
                    StatusGlyph(status: first.status, size: 16)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(first.displayTitle).font(.ui(14, weight: .medium)).foregroundStyle(HP.ink).lineLimit(1)
                        if placement != .inline {
                            Text(live.count > 1 ? "\(live.count) agents working" : (first.isPreparing ? "Preparing workspace" : "Working · \(Format.elapsed(since: first.runStartedAt.flatMap(ISO8601.parse)))"))
                                .font(.ui(11.5)).foregroundStyle(HP.ink2).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up").font(.system(size: 12, weight: .semibold)).foregroundStyle(HP.ink3)
                }
                .padding(.horizontal, 16)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(live.count) running. Open \(first.displayTitle)")
        }
    }
}
