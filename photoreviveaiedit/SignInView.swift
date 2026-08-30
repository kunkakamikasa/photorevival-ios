import SwiftUI

struct SignInView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("isLoggedIn") private var isLoggedIn = false
    @StateObject private var authStore = PhotoReviveAuthStore()
    @State private var legalDocument: LegalDocument?
    @State private var titleTapCount = 0
    @State private var lastTitleTapAt = Date.distantPast
    @State private var showsCompactSignIn = false
    @State private var compactEmail = ""
    @State private var compactPassword = ""
    let onAuthenticated: () -> Void

    init(onAuthenticated: @escaping () -> Void = {}) {
        self.onAuthenticated = onAuthenticated
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // Do not restore a static poster: it flashes before the video
                // player's first current frame becomes ready.
                Color.black

                LoopingVideoView(resourceName: "SignInBackgroundVideo")
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Color.black.opacity(0.15))
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .black, location: 0.18),
                                .init(color: .black, location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: proxy.size.height * 0.55)
                    .frame(maxHeight: .infinity, alignment: .bottom)

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.35),
                        .init(color: .black.opacity(0.70), location: 0.61),
                        .init(color: .black, location: 0.98)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 23, weight: .light))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(.black.opacity(0.12), in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.78), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close sign in")
                .position(x: 35, y: proxy.size.height * 0.088)

                Text("Welcome to\nPhoto Revival")
                    .font(.system(size: 25, weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineSpacing(0)
                    .foregroundStyle(.white)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: registerTitleTap)
                    .accessibilityIdentifier("sign-in-title")
                    .position(x: proxy.size.width / 2, y: proxy.size.height * 0.565)

                SignInProviderButton(
                    title: "Sign in with Apple",
                    style: .apple,
                    isLoading: authStore.activeProvider == .apple,
                    action: { authStore.signIn(with: .apple) }
                )
                .padding(.horizontal, 19)
                .position(x: proxy.size.width / 2, y: proxy.size.height * 0.646)

                SignInProviderButton(
                    title: "Sign in with Google",
                    style: .google,
                    isLoading: authStore.activeProvider == .google,
                    action: { authStore.signIn(with: .google) }
                )
                .padding(.horizontal, 19)
                .position(x: proxy.size.width / 2, y: proxy.size.height * 0.724)

                agreementText
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundStyle(.white)
                    .tint(.white)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 19)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .position(x: proxy.size.width / 2, y: proxy.size.height * 0.846)
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .onAppear {
            AppAnalytics.screen("sign_in", className: "SignInView")
        }
        .onChange(of: authStore.didAuthenticate) { _, didAuthenticate in
            guard didAuthenticate else { return }
            isLoggedIn = true
            onAuthenticated()
            dismiss()
        }
        .alert("Sign-in failed", isPresented: Binding(
            get: { authStore.errorMessage != nil },
            set: { if !$0 { authStore.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { authStore.errorMessage = nil }
        } message: {
            Text(authStore.errorMessage ?? "Please try again.")
        }
        .sheet(isPresented: $showsCompactSignIn) {
            CompactSignInSheet(
                email: $compactEmail,
                password: $compactPassword,
                isLoading: authStore.isCredentialSignInBusy,
                onCancel: { showsCompactSignIn = false },
                onSignIn: {
                    authStore.signIn(email: compactEmail, password: compactPassword)
                }
            )
            .presentationDetents([.height(365)])
            .presentationDragIndicator(.visible)
            .interactiveDismissDisabled(authStore.isCredentialSignInBusy)
        }
        .fullScreenCover(item: $legalDocument) { document in
            InAppBrowserView(url: document.url)
                .ignoresSafeArea()
        }
    }

    private var agreementText: some View {
        FlowingLegalAgreementText(
            leadingText: "By continuing, you agree to the ",
            onOpen: { legalDocument = $0 }
        )
        .accessibilityIdentifier("sign-in-legal-agreement")
    }

    private func registerTitleTap() {
        let now = Date()
        if now.timeIntervalSince(lastTitleTapAt) > 2.5 {
            titleTapCount = 0
        }
        lastTitleTapAt = now
        titleTapCount += 1

        guard titleTapCount >= 10 else { return }
        titleTapCount = 0
        compactEmail = ""
        compactPassword = ""
        showsCompactSignIn = true
    }
}

private struct CompactSignInSheet: View {
    @Binding var email: String
    @Binding var password: String
    let isLoading: Bool
    let onCancel: () -> Void
    let onSignIn: () -> Void

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
            && !isLoading
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TextField("Account", text: $email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .accessibilityIdentifier("compact-login-email")

                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .submitLabel(.go)
                    .onSubmit {
                        guard canSubmit else { return }
                        onSignIn()
                    }
                    .accessibilityIdentifier("compact-login-password")

                Button(action: onSignIn) {
                    HStack(spacing: 10) {
                        if isLoading {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(isLoading ? "Signing In..." : "Sign In")
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(AppPalette.accent, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
                .opacity(canSubmit || isLoading ? 1 : 0.45)
                .accessibilityIdentifier("compact-login-submit")

                Spacer(minLength: 0)
            }
            .textFieldStyle(.roundedBorder)
            .padding(20)
            .navigationTitle("Account Sign In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .disabled(isLoading)
                }
            }
        }
        .accessibilityIdentifier("compact-login-sheet")
    }
}

private struct SignInProviderButton: View {
    enum Style {
        case apple
        case google
    }

    let title: String
    let style: Style
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(isLoading ? "Connecting..." : title)
                    .font(.system(size: 19, weight: .medium))

                HStack {
                    providerIcon
                    Spacer()
                }
                .padding(.horizontal, 25)
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(.white, in: Capsule())
        }
        .buttonStyle(TemplatePressStyle())
        .disabled(isLoading)
        .accessibilityIdentifier("sign-in-\(accessibilitySuffix)")
    }

    @ViewBuilder
    private var providerIcon: some View {
        switch style {
        case .apple:
            Image(systemName: "apple.logo")
                .font(.system(size: 23, weight: .medium))
        case .google:
            Image("GoogleSignInIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 23, height: 23)
        }
    }

    private var accessibilitySuffix: String {
        switch style {
        case .apple: "apple"
        case .google: "google"
        }
    }
}
