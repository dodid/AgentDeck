import SwiftUI

struct OnboardingView: View {
    @State var viewModel: OnboardingViewModel

    var body: some View {
        NavigationStack {
            content(for: viewModel.step)
        }
    }

    @ViewBuilder
    private func content(for step: OnboardingViewModel.Step) -> some View {
        switch step {
        case .welcome:
            OnboardingPageView(
                stepIndex: 0,
                totalSteps: 4,
                primaryLabel: "Get Started",
                primaryAction: { viewModel.advance() }
            ) {
                WelcomePageContent()
            }
        case .howItWorks:
            OnboardingPageView(
                stepIndex: 1,
                totalSteps: 4,
                primaryLabel: "I Have an Account",
                primaryAction: { viewModel.advance() },
                secondaryLabel: "Back",
                secondaryAction: { viewModel.goBack() },
                disclaimer: "AgentDeck is not affiliated with or endorsed by Cloudflare, Inc."
            ) {
                HowItWorksPageContent()
            }
        case .createBucket:
            OnboardingPageView(
                stepIndex: 2,
                totalSteps: 4,
                primaryLabel: "Ready — Next Step",
                primaryAction: { viewModel.advance() },
                secondaryLabel: "Back",
                secondaryAction: { viewModel.goBack() }
            ) {
                CreateBucketPageContent()
            }
        case .connect:
            setupFormView
        }
    }

    private var setupFormView: some View {
        ZStack {
            AppTheme.bg.ignoresSafeArea()

            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Enter your bucket details")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(AppTheme.text)
                        Text("Paste the bucket credentials from Cloudflare, then test the connection.")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(AppTheme.dim)
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(AppTheme.panel)

                ConnectionFormSection(
                    config: Binding(
                        get: { viewModel.draftConfig },
                        set: { viewModel.updateConfig($0) }
                    ),
                    fontSize: .medium,
                    errorMessage: viewModel.actualErrorMessage
                )

                ConnectionFileTransferSection(
                    config: Binding(
                        get: { viewModel.draftConfig },
                        set: { viewModel.updateConfig($0) }
                    ),
                    importErrorMessage: Binding(
                        get: { viewModel.importErrorMessage },
                        set: { viewModel.importErrorMessage = $0 }
                    ),
                    fontSize: .medium
                )

                Section {
                    Button {
                        Task { await viewModel.verifyAndSave() }
                    } label: {
                        HStack {
                            Spacer()
                            if viewModel.isWorking {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("Test Connection & Continue")
                                    .font(.system(size: 17, weight: .semibold))
                            }
                            Spacer()
                        }
                    }
                    .disabled(!viewModel.draftConfig.isComplete || viewModel.isWorking)
                }
                .listRowBackground(AppTheme.panel)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .navigationTitle("Connect")
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Back") { viewModel.goBack() }
            }
        }
    }
}

private struct OnboardingPageView<Content: View>: View {
    let stepIndex: Int
    let totalSteps: Int
    let primaryLabel: LocalizedStringKey
    let primaryAction: () -> Void
    var secondaryLabel: LocalizedStringKey? = nil
    var secondaryAction: (() -> Void)? = nil
    var disclaimer: LocalizedStringKey? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack(alignment: .bottom) {
            AppTheme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                StepProgressDots(current: stepIndex, total: totalSteps)
                    .padding(.top, 20)
                    .padding(.bottom, 4)

                ScrollView(showsIndicators: false) {
                    content()
                        .padding(.horizontal, 22)
                        .padding(.top, 8)
                        .padding(.bottom, 164)
                }
            }

            VStack(spacing: 10) {
                Button(action: primaryAction) {
                    Text(primaryLabel)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(AppTheme.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                if let secondaryLabel, let secondaryAction {
                    Button(action: secondaryAction) {
                        Text(secondaryLabel)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(AppTheme.dim)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 36)
            .padding(.top, 28)
            .background(
                LinearGradient(
                    stops: [
                        .init(color: AppTheme.bg.opacity(0), location: 0),
                        .init(color: AppTheme.bg, location: 0.38)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            if let disclaimer {
                Text(disclaimer)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(AppTheme.dim.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 6)
                    .frame(maxWidth: .infinity)
                    .ignoresSafeArea(edges: .bottom)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct StepProgressDots: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i <= current ? AppTheme.blue : AppTheme.border)
                    .frame(width: i == current ? 24 : 6, height: 6)
                    .animation(.spring(response: 0.35, dampingFraction: 0.75), value: current)
            }
        }
    }
}

private struct WelcomePageContent: View {
    var body: some View {
        VStack(spacing: 26) {
            VStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(AppTheme.blue.opacity(0.15))
                        .frame(width: 88, height: 88)
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(AppTheme.blue)
                }
                .shadow(color: .black.opacity(0.13), radius: 20, x: 0, y: 8)
                .padding(.top, 20)

                VStack(spacing: 10) {
                    Text("Your AI assistant, wherever you are.")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(AppTheme.text)
                        .multilineTextAlignment(.center)

                    Text("A private, direct line to your agent platforms — at home, at work, or on the go.")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(AppTheme.dim)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                OnboardingFeatureRow(icon: "shield.fill", color: AppTheme.blue, title: "No ports open", detail: "Your server stays safely behind its firewall. AgentDeck never exposes it to the internet.")
                Divider().padding(.leading, 52)
                OnboardingFeatureRow(icon: "bolt.fill", color: AppTheme.green, title: "Instant setup", detail: "No bots, no webhooks, no API juggling. Connect once and start chatting.")
                Divider().padding(.leading, 52)
                OnboardingFeatureRow(icon: "checkmark.shield.fill", color: AppTheme.yellow, title: "You own your data", detail: "Conversations live in your own Cloudflare R2 bucket — not on anyone else's servers.")
                Divider().padding(.leading, 52)
                OnboardingFeatureRow(icon: "bubble.left.and.bubble.right.fill", color: AppTheme.blue, title: "Chat your way", detail: "A friendly bubble UI or a terminal-style interface for power users.")
            }
            .background(AppTheme.panel)
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(AppTheme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }
}

private struct HowItWorksPageContent: View {
    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 10) {
                Image(systemName: "cloud.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(AppTheme.blue)
                    .padding(.top, 20)

                Text("Powered by\nCloudflare R2")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(AppTheme.text)
                    .multilineTextAlignment(.center)

                Text("AgentDeck uses an R2 bucket as a private relay — a secure shared inbox between your phone and your agent platform server. No exposed ports.")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(AppTheme.dim)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            R2RelayDiagram()

            VStack(alignment: .leading, spacing: 0) {
                Text("What you'll need")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.dim)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                Divider()

                OnboardingRequirementRow(icon: "person.crop.circle.badge.checkmark", title: "A free Cloudflare account", detail: "No credit card required to sign up.", linkURL: URL(string: "https://dash.cloudflare.com/sign-up"), linkLabel: "Sign up")
                Divider().padding(.leading, 52)
                OnboardingRequirementRow(icon: "externaldrive.fill", title: "An R2 bucket", detail: "Cloudflare includes 10 GB of R2 free — more than enough for AgentDeck.")
            }
            .background(AppTheme.panel)
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(AppTheme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }
}

private struct R2RelayDiagram: View {
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            diagramItem(icon: "iphone", label: "AgentDeck", isAccent: false)
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.dim)
                .frame(maxWidth: 28)
                .padding(.top, 18)
            diagramItem(icon: "tray.2.fill", label: "R2 Bucket", isAccent: true)
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.dim)
                .frame(maxWidth: 28)
                .padding(.top, 18)
            diagramItem(icon: "server.rack", label: "Agent platform", isAccent: false)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .background(AppTheme.panelAlt)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private func diagramItem(icon: String, label: String, isAccent: Bool) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(isAccent ? AppTheme.blue : AppTheme.panel)
                    .frame(width: 48, height: 48)
                    .shadow(color: isAccent ? AppTheme.blue.opacity(0.28) : Color.black.opacity(0.06), radius: isAccent ? 8 : 4, x: 0, y: 2)
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(isAccent ? Color.white : AppTheme.text)
            }
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isAccent ? AppTheme.blue : AppTheme.dim)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct CreateBucketPageContent: View {
    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 10) {
                Image(systemName: "externaldrive.badge.plus")
                    .font(.system(size: 48))
                    .foregroundStyle(AppTheme.blue)
                    .padding(.top, 20)

                Text("Create your bucket")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(AppTheme.text)
                    .multilineTextAlignment(.center)

                Text("You'll need a Cloudflare R2 bucket and a set of API credentials. Here's how to get both.")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(AppTheme.dim)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            VStack(alignment: .leading, spacing: 0) {
                OnboardingNumberedStepRow(number: 1, text: "Sign in to Cloudflare and open **Storage and databases** / **R2 Object Storage**.")
                Divider().padding(.leading, 34)
                OnboardingNumberedStepRow(number: 2, text: "Create a new bucket — name it anything you like, e.g. **agentdeck**.")
                Divider().padding(.leading, 34)
                OnboardingNumberedStepRow(number: 3, text: "Find **Account Details** / **API Tokens** / **Manage** and generate a token with **Object Read & Write** access for your bucket.")
                Divider().padding(.leading, 34)
                OnboardingNumberedStepRow(number: 4, text: "Keep your **Endpoint URL**, **Access Key ID**, and **Secret Key** handy — you'll paste them in the next step.")
            }
            .background(AppTheme.panel)
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(AppTheme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 20))

            Link(destination: URL(string: "https://dash.cloudflare.com/")!) {
                HStack(spacing: 6) {
                    Text("Open Cloudflare Dashboard")
                        .font(.system(size: 16, weight: .semibold))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundStyle(AppTheme.blue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppTheme.blue.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }
}

private struct OnboardingFeatureRow: View {
    let icon: String
    let color: Color
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.13))
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.text)
                Text(detail)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(AppTheme.dim)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

private struct OnboardingRequirementRow: View {
    let icon: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    var linkURL: URL? = nil
    var linkLabel: LocalizedStringKey? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AppTheme.blue)
                .frame(width: 24)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.text)
                    if let linkURL, let linkLabel {
                        Link(destination: linkURL) {
                            HStack(spacing: 3) {
                                Text(linkLabel)
                                    .font(.system(size: 13, weight: .semibold))
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .foregroundStyle(AppTheme.blue)
                        }
                    }
                }
                Text(detail)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(AppTheme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

private struct OnboardingNumberedStepRow: View {
    let number: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(AppTheme.blue, in: Circle())
            Text(text)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(AppTheme.dim)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

#Preview {
    OnboardingView(viewModel: OnboardingViewModel(environment: .makeDefault()))
}
