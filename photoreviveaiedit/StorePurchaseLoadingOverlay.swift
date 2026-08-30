import SwiftUI

/// Shared visual feedback while StoreKit is presenting or processing a purchase.
struct StorePurchaseLoadingOverlay: View {
    let accessibilityLabel: String

    init(accessibilityLabel: String = "Processing App Store purchase") {
        self.accessibilityLabel = accessibilityLabel
    }

    var body: some View {
        ProgressView()
            .controlSize(.large)
            .tint(.white)
            .frame(width: 104, height: 104)
            .background(
                Color.black.opacity(0.72),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityIdentifier("store-purchase-loading")
    }
}
