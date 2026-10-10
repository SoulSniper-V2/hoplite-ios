import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var showKeySheet = false
    @State private var signingIn = false
    @State private var error: String?
    @State private var appeared = false

    var body: some View {
        ZStack(alignment: .bottom) {
            HP.canvas.ignoresSafeArea()
            GeometryReader { proxy in
                HalftoneArt(opacity: 0.55)
                    .frame(width: proxy.size.width, height: proxy.size.height * 0.72)
                    .offset(x: proxy.size.width * 0.14)
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.45)], startPoint: .leading, endPoint: .trailing))
                    .clipped()
                    .ignoresSafeArea()
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    AppIconMark(size: 34)
                    Text("Hoplite").font(.display(22, weight: .medium)).foregroundStyle(HP.ink)
                    Spacer()
                }
                .padding(.top, 8)

                Spacer()

                YCPill().padding(.bottom, 18)

                headline
                    .padding(.bottom, 16)

                Text("Start, steer and ship cloud coding agents from anywhere. Approve risky steps, review the diff, merge when it's green.")
                    .font(.ui(17))
                    .foregroundStyle(HP.ink2)
                    .lineSpacing(3)
                    .padding(.bottom, 32)

                actions
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 18)
        }
        .onAppear { withAnimation(.smooth(duration: 0.8).delay(0.1)) { appeared = true } }
        .sheet(isPresented: $showKeySheet) { APIKeySheet() }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: -4) {
            Text("Command a")
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("swarm")
                    .font(.pixel(52))
                    .foregroundStyle(LinearGradient(colors: [HP.ink, HP.actionSoft, HP.action], startPoint: .leading, endPoint: .trailing))
                Text("of")
            }
            Text("cloud agents")
        }
        .font(.display(46, weight: .regular))
        .tracking(-1.2)
        .foregroundStyle(HP.ink)
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button {
                Task { await oauth() }
            } label: {
                HStack {
                    Text("Sign in with Hoplite")
                    Spacer()
                    if signingIn { ProgressView().tint(.white) } else { DitherDots() }
                }
                .font(.ui(17, weight: .semibold))
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 34)
            }
            .buttonStyle(.glassProminent)
            .tint(HP.action)
            .controlSize(.large)
            .disabled(signingIn)

            Button {
                showKeySheet = true
            } label: {
                HStack {
                    Image(systemName: "key.horizontal")
                    Text("Use an API key")
                }
                .font(.ui(17, weight: .medium))
                .foregroundStyle(HP.ink)
                .frame(maxWidth: .infinity, minHeight: 34)
            }
            .buttonStyle(.glass)
            .controlSize(.large)

            if let error {
                Text(error).font(.hpFootnote).foregroundStyle(HP.failed).multilineTextAlignment(.center).transition(.opacity)
            }

            Button {
                model.enterDemo()
            } label: {
                HStack(spacing: 6) {
                    Text("Explore the demo workspace")
                    Image(systemName: "arrow.right")
                }
                .font(.ui(15, weight: .medium))
                .foregroundStyle(HP.ink2)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
        }
    }

    private func oauth() async {
        signingIn = true
        error = nil
        defer { signingIn = false }
        do {
            try await model.signInWithHoplite()
        } catch let api as APIError where api.isAuthFailure {
            withAnimation { error = "Signed in, but this workspace's API doesn't accept app sessions yet. Use a personal API key instead." }
        } catch {
            let ns = error as NSError
            if ns.domain == "com.apple.AuthenticationServices.WebAuthenticationSession" && ns.code == 1 { return }
            withAnimation { self.error = error.localizedDescription }
        }
    }
}

/// The 3×3 dot cluster from hoplite.sh's "Start free" button.
struct DitherDots: View {
    var color: Color = .white

    var body: some View {
        Canvas { context, size in
            let points: [CGPoint] = [.init(x: 0.5, y: 0.1), .init(x: 0.1, y: 0.5), .init(x: 0.9, y: 0.5), .init(x: 0.5, y: 0.9), .init(x: 0.5, y: 0.5)]
            for (index, point) in points.enumerated() {
                let r: CGFloat = index == 4 ? 1.2 : 1.6
                context.fill(Path(ellipseIn: CGRect(x: point.x * size.width - r, y: point.y * size.height - r, width: r * 2, height: r * 2)), with: .color(color.opacity(index == 4 ? 0.6 : 1)))
            }
        }
        .frame(width: 16, height: 16)
    }
}

private struct YCPill: View {
    var body: some View {
        HStack(spacing: 6) {
            Text("Backed by").foregroundStyle(HP.ink2)
            Text("Y").font(.system(size: 12, weight: .bold)).foregroundStyle(.white).frame(width: 18, height: 18).background(Color(hex: 0xF26522), in: .rect(cornerRadius: 3))
            Text("Combinator").foregroundStyle(HP.ink)
        }
        .font(.ui(14, weight: .medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .glassEffect(.regular, in: .capsule)
    }
}

struct APIKeySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var connecting = false
    @State private var error: String?
    @FocusState private var focused: Bool

    private var looksValid: Bool { key.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("hop_") && key.count > 12 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow(text: "Personal API key")
                        Text("Connect your workspace").font(.display(28, weight: .medium)).foregroundStyle(HP.ink)
                        Text("Create a key in **Settings → Workspace → API keys** on hoplite.sh. Keys are scoped to one organization and start with `hop_`.")
                            .font(.hpCallout).foregroundStyle(HP.ink2).lineSpacing(2)
                    }

                    HStack(spacing: 10) {
                        Image(systemName: "key.horizontal.fill").foregroundStyle(HP.ink3)
                        SecureField("hop_…", text: $key)
                            .font(.mono(15))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focused)
                            .submitLabel(.go)
                            .onSubmit { Task { await connect() } }
                        Button {
                            if let pasted = UIPasteboard.general.string { key = pasted }
                        } label: {
                            Text("Paste").font(.ui(13, weight: .semibold))
                        }
                        .buttonStyle(.glass)
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, 8)
                    .padding(.vertical, 8)
                    .hpCard(radius: 18)

                    if let error {
                        Label(error, systemImage: "exclamationmark.circle.fill").font(.hpFootnote).foregroundStyle(HP.failed)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        InfoRow(icon: "lock.shield", text: "Stored in the iOS Keychain on this device only and sent solely to api.hoplite.sh.")
                        InfoRow(icon: "slider.horizontal.3", text: "Give the key Read on Projects and Usage, and Write on Threads to start, steer and approve work.")
                        InfoRow(icon: "arrow.triangle.2.circlepath", text: "Revoke it from the same settings page at any time.")
                    }
                    .padding(16)
                    .hpCard(radius: 18, fill: HP.surface)
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(HP.canvas)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await connect() }
                    } label: {
                        if connecting { ProgressView() } else { Text("Connect") }
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(!looksValid || connecting)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.large])
    }

    private func connect() async {
        guard looksValid else { return }
        connecting = true
        error = nil
        defer { connecting = false }
        do {
            try await model.signIn(apiKey: key)
            dismiss()
        } catch {
            withAnimation { self.error = error.localizedDescription }
        }
    }
}

private struct InfoRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 14, weight: .medium)).foregroundStyle(HP.ink2).frame(width: 20)
            Text(text).font(.hpFootnote).foregroundStyle(HP.ink2).fixedSize(horizontal: false, vertical: true)
        }
    }
}
