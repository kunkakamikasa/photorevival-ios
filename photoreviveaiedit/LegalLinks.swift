import SafariServices
import SwiftUI

enum LegalDocument: String, CaseIterable, Identifiable {
    case privacyPolicy
    case termsOfService

    var id: String { rawValue }

    var url: URL {
        switch self {
        case .privacyPolicy:
            URL(string: "https://www.alihantakaz.site/PhotoRevival-Privacy-policy.html")!
        case .termsOfService:
            URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
        }
    }

    static func matching(_ url: URL) -> Self? {
        allCases.first { $0.url == url }
    }
}

/// A single flowing sentence whose legal links remain independently tappable.
/// Keeping the copy in one `Text` lets SwiftUI wrap it naturally at any width.
struct FlowingLegalAgreementText: View {
    let leadingText: String
    var connectingText = " and\u{00A0}"
    let onOpen: (LegalDocument) -> Void

    var body: some View {
        Text(attributedText)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.openURL, OpenURLAction { url in
                guard let document = LegalDocument.matching(url) else {
                    return .systemAction
                }
                onOpen(document)
                return .handled
            })
    }

    private var attributedText: AttributedString {
        var privacy = AttributedString("Privacy\u{00A0}Policy")
        privacy.link = LegalDocument.privacyPolicy.url
        privacy.underlineStyle = Text.LineStyle(pattern: .solid)

        var terms = AttributedString("Terms\u{00A0}of\u{00A0}Use")
        terms.link = LegalDocument.termsOfService.url
        terms.underlineStyle = Text.LineStyle(pattern: .solid)

        return AttributedString(leadingText)
            + privacy
            + AttributedString(connectingText)
            + terms
    }
}

/// Compact legal links shared by purchase surfaces.
struct LegalLinksView: View {
    var privacyLabel = "Privacy Policy"
    var termsLabel = "Terms of Use"
    var spacing: CGFloat = 10
    let onOpen: (LegalDocument) -> Void

    var body: some View {
        HStack(spacing: spacing) {
            Button(privacyLabel) { onOpen(.privacyPolicy) }
                .accessibilityIdentifier("legal-privacy-policy")
            Text("|")
                .accessibilityHidden(true)
            Button(termsLabel) { onOpen(.termsOfService) }
                .accessibilityIdentifier("legal-terms-of-service")
        }
        .buttonStyle(.plain)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        .allowsTightening(true)
    }
}

/// Presents legal pages without leaving Photo Revival.
struct InAppBrowserView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false

        let controller = SFSafariViewController(url: url, configuration: configuration)
        controller.dismissButtonStyle = .close
        controller.preferredControlTintColor = UIColor(AppPalette.accent)
        return controller
    }

    func updateUIViewController(
        _ uiViewController: SFSafariViewController,
        context: Context
    ) {}
}
