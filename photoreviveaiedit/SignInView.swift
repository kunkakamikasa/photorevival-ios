import SwiftUI

struct SignInView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("isLoggedIn") private var isLoggedIn = false
    @StateObject private var authStore = PhotoReviveAuthStore()
    let onAuthenticated: () -> Void

    init(onAuthenticated: @escaping () -> Void = {}) {
        self.onAuthenticated = onAuthenticated
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Image("SignInBackground")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()

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

                Text("Welcome to\nPhoto Revive AI")
                    .font(.system(size: 25, weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineSpacing(0)
                    .foregroundStyle(.white)
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
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 19)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .position(x: proxy.size.width / 2, y: proxy.size.height * 0.846)
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
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
    }

    private var agreementText: Text {
        Text("Continue to indicate your agreement to the \(Text("Privacy Policy").underline())\nand \(Text("Terms of Service").underline())")
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
