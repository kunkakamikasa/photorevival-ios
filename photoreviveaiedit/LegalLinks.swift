import SafariServices
import SwiftUI

enum LegalDocument: String, Identifiable {
    case termsOfService

    var id: String { rawValue }

    var url: URL {
        switch self {
        case .termsOfService:
            URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
        }
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
