import PhotosUI
import StoreKit
import SwiftUI
import UIKit

private enum SettingsPalette {
    static let card = Color(red: 1.00, green: 0.965, blue: 0.895)
    static let muted = Color(red: 0.76, green: 0.52, blue: 0.29)
    static let fieldBorder = Color(red: 0.60, green: 0.36, blue: 0.14)
    static let warmGray = Color(red: 0.58, green: 0.58, blue: 0.58)
    static let transactionLine = Color(red: 0.92, green: 0.73, blue: 0.43).opacity(0.28)
}

private enum SettingsDestination: String, Identifiable {
    case account
    case creditDetail
    case feedback
    case membership

    var id: String { rawValue }
}

private struct SettingsNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct SettingsView: View {
    @Binding var credits: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @AppStorage("isSubscribed") private var isSubscribed = false
    @AppStorage("isLoggedIn") private var isLoggedIn = false
    @AppStorage("profileDisplayName") private var storedDisplayName = ""
    @AppStorage("profileAvatarURL") private var storedAvatarURL = ""
    @ObservedObject private var accountStore = AppAccountStore.shared
    @State private var destination: SettingsDestination?
    @State private var legalDocument: LegalDocument?
    @State private var notice: SettingsNotice?
    @State private var isRestoring = false
    @State private var isSigningOut = false
    @State private var showSignOutConfirmation = false
    @State private var storeProductID: String?

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var accountDisplayName: String {
        let normalized = storedDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalized.isEmpty { return normalized }
        if let name = PhotoReviveAuthClient.shared.currentUserDisplayName { return name }
        let localPart = PhotoReviveAuthClient.shared.currentUserEmail?
            .split(separator: "@", maxSplits: 1).first.map(String.init) ?? ""
        return localPart.isEmpty ? "Photo Revival User" : localPart
    }

    private var avatarURL: URL? {
        URL(string: storedAvatarURL) ?? PhotoReviveAuthClient.shared.currentUserAvatarURL
    }

    private var currentProductID: String? {
        accountStore.userStatus?.productID ?? storeProductID
    }

    private var currentPlanLevel: SubscriptionPlanLevel? {
        SubscriptionPlanLevel(productID: currentProductID)
    }

    private var isHighestSubscription: Bool {
        isSubscribed && currentPlanLevel?.isHighest == true
    }

    private var membershipCallToAction: String {
        if !isSubscribed { return "Join Now" }
        return isHighestSubscription ? "PRO+" : "Upgrade"
    }

    private var membershipBadge: String {
        guard isSubscribed else { return "FREE" }
        switch currentPlanLevel {
        case .proPlusWeekly, .proPlusAnnual: return "PRO+"
        default: return "PRO"
        }
    }

    var body: some View {
        ZStack {
            PaperTextureBackground()

            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    settingsHeader
                    accountCard
                        .padding(.top, 8)

                    VStack(spacing: 6) {
                        SettingsRow(title: "Credit Detail", action: { destination = .creditDetail })
                        SettingsRow(
                            title: isRestoring ? "Restoring..." : "Restore",
                            action: { restorePurchases() }
                        )
                        SettingsRow(title: "Feedback", action: { destination = .feedback })
                        SettingsRow(title: "Rate us", action: { requestReview() })
                        SettingsRow(title: "Terms of Service", action: { legalDocument = .termsOfService })
                        SettingsRow(title: "Privacy Policy", action: { legalDocument = .privacyPolicy })
                        SettingsRow(title: "Version", value: appVersion, action: nil)
                    }
                    .padding(.top, 20)

                    Button {
                        showSignOutConfirmation = true
                    } label: {
                        Text(isSigningOut ? "Signing Out..." : "Sign Out")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(AppPalette.accent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 58)
                            .background(SettingsPalette.card.opacity(0.65), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSigningOut)
                    .accessibilityIdentifier("settings-sign-out")
                    .padding(.top, 20)
                    .padding(.bottom, 20)
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
            }
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.light)
        .fullScreenCover(item: $destination) { selectedDestination in
            switch selectedDestination {
            case .account:
                AccountView(
                    displayName: $storedDisplayName,
                    avatarURLString: $storedAvatarURL,
                    onAccountDeleted: {
                        destination = nil
                        isLoggedIn = false
                        dismiss()
                    }
                )
            case .creditDetail:
                CreditDetailView(credits: $credits)
            case .feedback:
                FeedbackView()
            case .membership:
                PaywallOfferFlowView(
                    analyticsSource: isSubscribed ? "settings_upgrade" : "settings_membership",
                    upgradingFromProductID: isSubscribed ? currentProductID : nil
                )
            }
        }
        .fullScreenCover(item: $legalDocument) { document in
            InAppBrowserView(url: document.url)
                .ignoresSafeArea()
        }
        .alert(item: $notice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .alert("Sign Out?", isPresented: $showSignOutConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) {
                signOut()
            }
        } message: {
            Text("You will need to sign in again to access your account.")
        }
        .task {
            if storedDisplayName.isEmpty,
               let serverName = PhotoReviveAuthClient.shared.currentUserDisplayName {
                storedDisplayName = serverName
            }
            if storedAvatarURL.isEmpty,
               let serverAvatarURL = PhotoReviveAuthClient.shared.currentUserAvatarURL {
                storedAvatarURL = serverAvatarURL.absoluteString
            }

            await accountStore.refreshCredits()
            if let serverProductID = accountStore.userStatus?.productID {
                storeProductID = serverProductID
            } else {
                storeProductID = await SubscriptionPurchaseService.activeProductID()
            }
        }
    }

    private var settingsHeader: some View {
        ZStack {
            Text("Setting")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(AppPalette.ink)

            HStack {
                CircleBackButton(label: "Close settings") {
                    dismiss()
                }
                Spacer()
            }
        }
        .frame(height: 68)
    }

    private var accountCard: some View {
        HStack(spacing: 10) {
            Button {
                destination = .account
            } label: {
                HStack(spacing: 11) {
                    AccountAvatar(avatarURL: avatarURL, badge: membershipBadge)

                    VStack(alignment: .leading, spacing: 7) {
                        Text(accountDisplayName)
                            .font(.system(size: 21, weight: .bold))
                            .foregroundStyle(AppPalette.ink)
                            .lineLimit(1)

                        HStack(spacing: 3) {
                            Image("RewardsCreditToken")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 25, height: 25)
                            Text("\(credits)")
                                .font(.system(size: 20, weight: .regular))
                                .foregroundStyle(AppPalette.ink)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("settings-account")

            if isHighestSubscription {
                Text(membershipCallToAction)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 13)
                    .frame(height: 32)
                    .background(AppPalette.accent.opacity(0.72), in: Capsule())
            } else {
                Button {
                    destination = .membership
                } label: {
                    Text(membershipCallToAction)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 13)
                        .frame(height: 32)
                        .background(AppPalette.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings-membership-action")
            }

            Button {
                destination = .account
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(AppPalette.ink)
                    .frame(width: 24, height: 54)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open account")
        }
        .padding(.horizontal, 13)
        .frame(maxWidth: .infinity)
        .frame(height: 100)
        .background(SettingsPalette.card, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }

    private func showNotice(_ title: String, _ message: String) {
        notice = SettingsNotice(title: title, message: message)
    }

    private func restorePurchases() {
        guard !isRestoring else { return }
        isRestoring = true

        Task {
            let outcome = await SubscriptionPurchaseService.restore()
            isRestoring = false
            switch outcome {
            case .purchased:
                isSubscribed = true
                await accountStore.refreshCredits()
                if let serverProductID = accountStore.userStatus?.productID {
                    storeProductID = serverProductID
                } else {
                    storeProductID = await SubscriptionPurchaseService.activeProductID()
                }
                showNotice("Restore Complete", "Your active subscription has been restored.")
            case .unavailable:
                showNotice("No Purchases Found", "No active subscription was found for this Apple ID.")
            case .failed(let message):
                showNotice("Restore Unavailable", message)
            case .cancelled, .pending:
                break
            }
        }
    }

    private func signOut() {
        guard !isSigningOut else { return }
        isSigningOut = true

        Task {
            await PhotoReviveAuthClient.shared.signOut()
            AppAccountStore.shared.resetForSignedOutUser()
            isLoggedIn = false
            isSigningOut = false
            dismiss()
        }
    }
}

private struct SettingsRow: View {
    let title: String
    var value: String?
    let action: (() -> Void)?

    init(title: String, value: String? = nil, action: (() -> Void)?) {
        self.title = title
        self.value = value
        self.action = action
    }

    var body: some View {
        Group {
            if let action {
                Button(action: action) { rowContent }
                    .buttonStyle(.plain)
            } else {
                rowContent
            }
        }
        .accessibilityIdentifier("settings-row-\(title.lowercased().replacingOccurrences(of: " ", with: "-"))")
    }

    private var rowContent: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(AppPalette.ink)
                .lineLimit(1)

            Spacer(minLength: 6)

            if let value {
                Text(value)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(SettingsPalette.muted)
            }

            if action != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(AppPalette.ink)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .frame(height: 58)
        .background(SettingsPalette.card, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

private struct AccountAvatar: View {
    let avatarURL: URL?
    let badge: String

    var body: some View {
        ZStack(alignment: .bottom) {
            ProfileAvatarImage(url: avatarURL, size: 61)

            Text(badge)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .frame(height: 20)
                .background(Color.gray.opacity(0.86), in: Capsule())
                .offset(y: 9)
        }
        .frame(width: 72, height: 72)
    }
}

private struct ProfileAvatarImage: View {
    let url: URL?
    var localImage: UIImage? = nil
    let size: CGFloat

    var body: some View {
        Group {
            if let localImage {
                Image(uiImage: localImage)
                    .resizable()
                    .scaledToFill()
            } else if let url {
                CachedRemoteImage(url: url) { image in
                    Image(uiImage: image).resizable().scaledToFill()
                } placeholder: {
                    avatarPlaceholder
                } failure: {
                    avatarPlaceholder
                }
            } else {
                avatarPlaceholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.72), lineWidth: 1))
    }

    private var avatarPlaceholder: some View {
        ZStack(alignment: .bottom) {
            Circle().fill(AppPalette.ink)
            Image(systemName: "person.fill")
                .font(.system(size: size * 0.66, weight: .regular))
                .foregroundStyle(Color(red: 1.00, green: 0.73, blue: 0.39))
                .offset(y: -size * 0.05)
        }
    }
}

private struct AccountView: View {
    @Binding var displayName: String
    @Binding var avatarURLString: String
    let onAccountDeleted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage("isLoggedIn") private var isLoggedIn = false
    @AppStorage("isSubscribed") private var isSubscribed = false
    @State private var avatarItem: PhotosPickerItem?
    @State private var localAvatar: UIImage?
    @State private var editedName = ""
    @State private var showNameEditor = false
    @State private var showDeleteConfirmation = false
    @State private var showFeedback = false
    @State private var isSavingName = false
    @State private var isSavingAvatar = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    private let api = PhotoReviveAPIClient.shared
    private let authClient = PhotoReviveAuthClient.shared

    private var resolvedDisplayName: String {
        let normalized = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalized.isEmpty { return normalized }
        if let serverName = authClient.currentUserDisplayName { return serverName }
        let emailName = authClient.currentUserEmail?
            .split(separator: "@", maxSplits: 1).first.map(String.init) ?? ""
        return emailName.isEmpty ? "Photo Revival User" : emailName
    }

    private var avatarURL: URL? {
        URL(string: avatarURLString) ?? authClient.currentUserAvatarURL
    }

    private var email: String {
        authClient.currentUserEmail ?? "—"
    }

    private var userID: String {
        authClient.currentUserID ?? "—"
    }

    var body: some View {
        ZStack {
            PaperTextureBackground()

            VStack(spacing: 0) {
                accountHeader

                PhotosPicker(selection: $avatarItem, matching: .images) {
                    ZStack(alignment: .bottomTrailing) {
                        ProfileAvatarImage(
                            url: avatarURL,
                            localImage: localAvatar,
                            size: 112
                        )

                        ZStack {
                            Circle().fill(AppPalette.accent)
                            if isSavingAvatar {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "pencil")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(width: 34, height: 34)
                        .overlay(Circle().stroke(Color.white.opacity(0.85), lineWidth: 2))
                    }
                }
                .buttonStyle(.plain)
                .disabled(isSavingAvatar || isDeleting)
                .accessibilityLabel("Change profile photo")
                .padding(.top, 22)

                VStack(spacing: 6) {
                    Button {
                        editedName = resolvedDisplayName
                        showNameEditor = true
                    } label: {
                        accountInfoRow(
                            title: "Name",
                            value: isSavingName ? "Saving…" : resolvedDisplayName,
                            showsChevron: true
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isSavingName || isDeleting)
                    .accessibilityIdentifier("account-edit-name")

                    accountInfoRow(title: "Email", value: email)
                    accountInfoRow(title: "User ID", value: userID)
                }
                .padding(.top, 42)

                Spacer(minLength: 32)

                Button {
                    showDeleteConfirmation = true
                } label: {
                    Text("Delete Account")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.gray.opacity(0.50))
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .background(
                            SettingsPalette.card.opacity(0.42),
                            in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .disabled(isDeleting)
                .accessibilityIdentifier("account-delete")
                .padding(.bottom, 34)
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)

            if showDeleteConfirmation {
                deleteConfirmationOverlay
                    .transition(.opacity)
                    .zIndex(20)
            }
        }
        .preferredColorScheme(.light)
        .onChange(of: avatarItem) { _, item in
            loadAvatar(from: item)
        }
        .fullScreenCover(isPresented: $showFeedback) {
            FeedbackView()
        }
        .alert("Edit Name", isPresented: $showNameEditor) {
            TextField("Name", text: $editedName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { saveName() }
                .disabled(editedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Enter the name shown on your Photo Revival account.")
        }
        .alert(
            "Unable to update account",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    private var accountHeader: some View {
        ZStack {
            Text("Account")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(AppPalette.ink)

            HStack {
                CircleBackButton(label: "Close account") { dismiss() }
                Spacer()
            }
        }
        .frame(height: 68)
    }

    private func accountInfoRow(
        title: String,
        value: String,
        showsChevron: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(SettingsPalette.muted)
                .frame(width: 78, alignment: .leading)

            Text(value)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppPalette.ink)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .trailing)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(AppPalette.ink)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .frame(height: 62)
        .background(SettingsPalette.card, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private var deleteConfirmationOverlay: some View {
        ZStack {
            Color.black.opacity(0.66)
                .ignoresSafeArea()
                .onTapGesture {
                    guard !isDeleting else { return }
                    showDeleteConfirmation = false
                }

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button {
                        showDeleteConfirmation = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 25, weight: .regular))
                            .foregroundStyle(AppPalette.brownInk)
                            .frame(width: 42, height: 42)
                    }
                    .buttonStyle(.plain)
                    .disabled(isDeleting)
                }

                Text("Delete Account")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(AppPalette.ink)
                    .padding(.top, -28)

                Text("Are you sure you want to delete\nyour account?")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(AppPalette.brownInk)
                    .multilineTextAlignment(.center)
                    .padding(.top, 22)

                Text("This action is permanent and cannot be undone.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppPalette.brownInk.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .padding(.top, 9)

                Button {
                    showFeedback = true
                } label: {
                    Text("Feedback")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .background(AppPalette.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isDeleting)
                .padding(.top, 24)

                Button {
                    deleteAccount()
                } label: {
                    HStack(spacing: 8) {
                        if isDeleting { ProgressView().tint(.gray) }
                        Text(isDeleting ? "Deleting…" : "Confirm")
                            .font(.system(size: 22, weight: .bold))
                    }
                    .foregroundStyle(Color.gray.opacity(0.72))
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                }
                .buttonStyle(.plain)
                .disabled(isDeleting)
                .accessibilityIdentifier("account-delete-confirm")
                .padding(.top, 7)
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 15)
            .frame(maxWidth: 382)
            .background(SettingsPalette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 24)
        }
    }

    private func saveName() {
        let normalized = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, !isSavingName else { return }
        isSavingName = true

        Task {
            defer { isSavingName = false }
            do {
                try await authClient.updateProfile(displayName: normalized)
                displayName = String(normalized.prefix(50))
            } catch {
                errorMessage = error.userFacingEnglishMessage()
            }
        }
    }

    private func loadAvatar(from item: PhotosPickerItem?) {
        guard let item, !isSavingAvatar else { return }
        isSavingAvatar = true

        Task {
            defer {
                isSavingAvatar = false
                avatarItem = nil
            }
            do {
                guard let sourceData = try await item.loadTransferable(type: Data.self),
                      let sourceImage = UIImage(data: sourceData) else {
                    throw PhotoReviveAPIError.invalidResponse
                }
                let image = resizedAvatar(sourceImage)
                guard let uploadData = image.jpegData(compressionQuality: 0.86) else {
                    throw PhotoReviveAPIError.invalidResponse
                }
                localAvatar = image
                let uploadedURL = try await api.uploadProfileAvatar(uploadData)
                try await authClient.updateProfile(avatarURL: uploadedURL)
                avatarURLString = uploadedURL
            } catch {
                localAvatar = nil
                errorMessage = error.userFacingEnglishMessage()
            }
        }
    }

    private func resizedAvatar(_ image: UIImage, maxDimension: CGFloat = 1_024) -> UIImage {
        let longestSide = max(image.size.width, image.size.height)
        guard longestSide > maxDimension else { return image }
        let scale = maxDimension / longestSide
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return UIGraphicsImageRenderer(size: targetSize).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private func deleteAccount() {
        guard !isDeleting else { return }
        isDeleting = true

        Task {
            do {
                let result = try await api.deleteAccount()
                guard result.success else {
                    throw PhotoReviveAPIError.requestFailed(
                        statusCode: 500,
                        message: result.message ?? "Unable to delete this account."
                    )
                }

                await authClient.signOut()
                AppAccountStore.shared.resetForSignedOutUser()
                displayName = ""
                avatarURLString = ""
                isSubscribed = false
                isLoggedIn = false
                isDeleting = false
                showDeleteConfirmation = false
                dismiss()
                onAccountDeleted()
            } catch {
                isDeleting = false
                showDeleteConfirmation = false
                errorMessage = error.userFacingEnglishMessage()
            }
        }
    }
}

private struct CircleBackButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.left")
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(AppPalette.ink)
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.54), in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.82), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private enum CreditFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case spent = "Spent"
    case earned = "Earned"

    var id: String { rawValue }
}

struct CreditDetailView: View {
    @Binding var credits: Int
    @ObservedObject var accountStore: AppAccountStore
    @Environment(\.dismiss) private var dismiss
    @State private var filter: CreditFilter = .all
    @State private var showCreditStore = false
    @State private var showExitOfferAfterStoreDismisses = false
    @State private var showExitOffer = false
    @State private var showFAQ = false

    init(credits: Binding<Int>, accountStore: AppAccountStore? = nil) {
        _credits = credits
        self.accountStore = accountStore ?? .shared
    }

    private var visibleTransactions: [CreditTransactionRecord] {
        switch filter {
        case .all: accountStore.creditTransactions
        case .spent: accountStore.creditTransactions.filter(\.isSpent)
        case .earned: accountStore.creditTransactions.filter { !$0.isSpent }
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            PaperTextureBackground()

            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    creditHeader
                    creditSummary
                        .padding(.top, 17)
                    filterControl
                        .padding(.top, 24)
                    transactionList
                        .padding(.top, 20)
                    Text("No more content~")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(SettingsPalette.warmGray)
                        .padding(.top, 17)
                        .padding(.bottom, 138)
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
            }
            .scrollIndicators(.hidden)

            moreCreditsBar

            if showExitOffer {
                CreditExitOfferView(
                    onClose: {
                        withAnimation(.easeInOut(duration: 0.20)) {
                            showExitOffer = false
                        }
                    },
                    onPurchased: { _ in
                        Task {
                            await accountStore.refreshCreditTransactions()
                            credits = accountStore.creditsBalance
                        }
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(20)
            }
        }
        .preferredColorScheme(.light)
        .fullScreenCover(isPresented: $showCreditStore, onDismiss: {
            guard showExitOfferAfterStoreDismisses else { return }
            showExitOfferAfterStoreDismisses = false
            withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                showExitOffer = true
            }
        }) {
            CreditStoreView(
                onClose: {
                    showExitOfferAfterStoreDismisses = true
                    showCreditStore = false
                },
                onPurchased: { _ in
                    showExitOfferAfterStoreDismisses = false
                    showCreditStore = false
                    Task {
                        await accountStore.refreshCreditTransactions()
                        credits = accountStore.creditsBalance
                    }
                }
            )
        }
        .alert("FAQ", isPresented: $showFAQ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Credits are consumed when you generate images or videos and added by rewards.")
        }
        .task {
            await accountStore.refreshCreditTransactions()
            credits = accountStore.creditsBalance
        }
    }

    private var creditHeader: some View {
        ZStack {
            Text("Credit Detail")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(AppPalette.ink)

            HStack {
                CircleBackButton(label: "Close credit detail") { dismiss() }
                Spacer()
                Button("FAQ") { showFAQ = true }
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(AppPalette.accent)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .overlay(Capsule().stroke(AppPalette.accent, lineWidth: 1.2))
                .buttonStyle(.plain)
            }
        }
        .frame(height: 68)
    }

    private var creditSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image("RewardsCreditToken")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 29, height: 29)
                Text("\(accountStore.creditWallet?.total ?? credits)")
                    .font(.system(size: 31, weight: .heavy))
                    .foregroundStyle(AppPalette.ink)
                Button {
                    Task {
                        await accountStore.refreshCreditTransactions()
                        credits = accountStore.creditsBalance
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 28, weight: .regular))
                        .foregroundStyle(Color.gray.opacity(0.52))
                }
                .buttonStyle(.plain)
            }

            Text("Recurring Credit \(accountStore.creditWallet?.recurringBalance ?? 0) | Lifetime Credit \(accountStore.creditWallet?.lifetimeBalance ?? 0)")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(SettingsPalette.muted)
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(Color.white.opacity(0.55), in: Capsule())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var filterControl: some View {
        HStack(spacing: 0) {
            ForEach(CreditFilter.allCases) { option in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { filter = option }
                } label: {
                    Text(option.rawValue)
                        .font(.system(size: 18, weight: filter == option ? .medium : .regular))
                        .foregroundStyle(filter == option ? .white : Color.gray.opacity(0.55))
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(filter == option ? AppPalette.orange : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(filter == option ? .isSelected : [])
            }
        }
        .padding(1)
        .background(AppPalette.orange.opacity(0.15), in: Capsule())
        .accessibilityIdentifier("credit-filter")
    }

    private var transactionList: some View {
        VStack(spacing: 0) {
            if visibleTransactions.isEmpty {
                Text("No credit activity yet")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(SettingsPalette.warmGray)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 42)
            } else {
                ForEach(visibleTransactions) { transaction in
                    CreditTransactionRow(transaction: transaction)
                    if transaction.id != visibleTransactions.last?.id {
                        Rectangle()
                            .fill(SettingsPalette.transactionLine)
                            .frame(height: 1)
                    }
                }
            }
        }
    }

    private var moreCreditsBar: some View {
        VStack(spacing: 9) {
            Button {
                showCreditStore = true
            } label: {
                HStack {
                    Spacer()
                    Text("More Credits")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.trailing, 20)
                }
                .frame(height: 55)
                .background(
                    LinearGradient(colors: [AppPalette.orange, AppPalette.accent], startPoint: .leading, endPoint: .trailing),
                    in: Capsule()
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("more-credits-button")

            Text("History for the past 3 months")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.66))
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 22)
    }
}

private struct CreditTransactionRow: View {
    let transaction: CreditTransactionRecord

    var body: some View {
        HStack(spacing: 11) {
            transactionIcon

            VStack(alignment: .leading, spacing: 3) {
                Text(transaction.description ?? transaction.source.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(AppPalette.ink)
                    .lineLimit(1)
                Text(transaction.createdAt.photoReviveDisplayDate)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.gray.opacity(0.56))
            }

            Spacer(minLength: 4)

            HStack(spacing: 5) {
                Text(transaction.amount > 0 ? "+\(transaction.amount)" : "\(transaction.amount)")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(transaction.amount > 0 ? AppPalette.ink : AppPalette.accent)
                Image("RewardsCreditToken")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
            }
        }
        .frame(height: 65)
    }

    private var transactionIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.88))
            if transaction.isSpent {
                Image(systemName: "rectangle.fill")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(Color.orange.opacity(0.70))
                    .overlay {
                        Circle()
                            .fill(.white)
                            .frame(width: 7, height: 7)
                            .offset(x: 4)
                    }
            } else {
                Image(systemName: "gift.fill")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(Color(red: 1.00, green: 0.42, blue: 0.35))
            }
        }
        .frame(width: 42, height: 42)
    }
}

struct FeedbackView: View {
    @Environment(\.dismiss) private var dismiss
    private let api = PhotoReviveAPIClient.shared
    @State private var feedback = ""
    @State private var email = ""
    @State private var screenshotItem: PhotosPickerItem?
    @State private var screenshot: UIImage?
    @State private var showFAQ = false
    @State private var showSent = false
    @State private var isSubmitting = false
    @State private var submissionError: String?
    @State private var didPrefillEmail = false

    private var canSubmit: Bool {
        let trimmedFeedback = feedback.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let emailParts = trimmedEmail.split(separator: "@", omittingEmptySubsequences: false)
        return !trimmedFeedback.isEmpty
            && feedback.count <= 1_000
            && emailParts.count == 2
            && !emailParts[0].isEmpty
            && emailParts[1].contains(".")
    }

    var body: some View {
        ZStack {
            PaperTextureBackground()

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    feedbackHeader

                    Text("Tell us how we can improve. Your suggestions\nmean a lot!")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(AppPalette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 7)

                    Text("Your Feedback")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(AppPalette.brownInk)
                        .overlay(alignment: .trailing) {
                            Text("*")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(AppPalette.accent)
                                .offset(x: 11)
                        }
                        .padding(.top, 25)

                    feedbackEditor
                        .padding(.top, 12)

                    requiredLabel("Your Email")
                        .padding(.top, 22)
                    emailField
                        .padding(.top, 12)

                    Text("Screenshot")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(AppPalette.brownInk)
                        .padding(.top, 23)
                    screenshotPicker
                        .padding(.top, 20)

                    Button {
                        submitFeedback()
                    } label: {
                        HStack(spacing: 10) {
                            if isSubmitting {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(isSubmitting ? "Sending…" : "Send Feedback")
                                .font(.system(size: 20, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(canSubmit ? AppPalette.accent : Color.gray.opacity(0.56), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSubmit || isSubmitting)
                    .accessibilityIdentifier("feedback-submit")
                    .padding(.top, 42)
                    .padding(.bottom, 35)
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
            }
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.light)
        .onChange(of: screenshotItem) { _, item in
            loadScreenshot(item)
        }
        .onChange(of: feedback) { _, newValue in
            if newValue.count > 1_000 {
                feedback = String(newValue.prefix(1_000))
            }
        }
        .task {
            guard !didPrefillEmail else { return }
            didPrefillEmail = true
            if let accountEmail = PhotoReviveAuthClient.shared.currentUserEmail {
                email = accountEmail
            }
        }
        .alert("FAQ", isPresented: $showFAQ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Tell us what you would like to see improved. A screenshot is optional.")
        }
        .alert("Feedback sent", isPresented: $showSent) {
            Button("Done") { dismiss() }
        } message: {
            Text("Thanks for helping us improve Photo Revival.")
        }
        .alert(
            "Unable to send feedback",
            isPresented: Binding(
                get: { submissionError != nil },
                set: { if !$0 { submissionError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(submissionError ?? "Please try again.")
        }
    }

    private var feedbackHeader: some View {
        ZStack {
            Text("Feedback")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(AppPalette.ink)

            HStack {
                CircleBackButton(label: "Close feedback") { dismiss() }
                Spacer()
                Button("FAQ") { showFAQ = true }
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppPalette.accent)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .overlay(Capsule().stroke(AppPalette.accent, lineWidth: 1.2))
                    .buttonStyle(.plain)
            }
        }
        .frame(height: 68)
    }

    private var feedbackEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $feedback)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(SettingsPalette.muted)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .accessibilityIdentifier("feedback-content")

            if feedback.isEmpty {
                Text("Please enter your feedback (up to 1000\ncharacters)")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(SettingsPalette.muted)
                    .padding(.horizontal, 15)
                    .padding(.top, 19)
                    .allowsHitTesting(false)
            }

            clearButton {
                feedback = ""
            }
            .padding(.trailing, 13)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .frame(height: 188)
        .background(SettingsPalette.card.opacity(0.76), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(SettingsPalette.fieldBorder, lineWidth: 1))
    }

    private func requiredLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(AppPalette.brownInk)
            .overlay(alignment: .trailing) {
                Text("*")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(AppPalette.accent)
                    .offset(x: 11)
            }
    }

    private var emailField: some View {
        HStack(spacing: 8) {
            TextField("", text: $email)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(AppPalette.ink)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("feedback-email")

            clearButton {
                email = ""
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
        .background(SettingsPalette.card.opacity(0.76), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(SettingsPalette.fieldBorder, lineWidth: 1))
    }

    private var screenshotPicker: some View {
        PhotosPicker(selection: $screenshotItem, matching: .images) {
            Group {
                if let screenshot {
                    FrostedUploadedPhoto(image: screenshot)
                } else {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 28, weight: .regular))
                        .foregroundStyle(SettingsPalette.muted)
                }
            }
            .frame(width: 80, height: 80)
            .background(SettingsPalette.card.opacity(0.76), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(SettingsPalette.fieldBorder, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add screenshot")
    }

    private func clearButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white.opacity(0.78))
                .frame(width: 22, height: 22)
                .background(SettingsPalette.muted.opacity(0.38), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear")
    }

    private func loadScreenshot(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { return }
            await MainActor.run { screenshot = image }
        }
    }

    private func submitFeedback() {
        let trimmedFeedback = feedback.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSubmit, !isSubmitting else { return }

        isSubmitting = true
        submissionError = nil

        Task {
            defer { isSubmitting = false }
            do {
                let screenshotData = screenshot?.jpegData(compressionQuality: 0.82)
                _ = try await api.submitFeedback(
                    content: trimmedFeedback,
                    contactEmail: trimmedEmail,
                    screenshotData: screenshotData
                )
                showSent = true
            } catch {
                submissionError = error.userFacingEnglishMessage(
                    fallback: "Your feedback could not be sent. Please try again."
                )
            }
        }
    }
}

#Preview("Settings") {
    SettingsView(credits: .constant(0))
}
