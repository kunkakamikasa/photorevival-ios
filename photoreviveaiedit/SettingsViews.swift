import PhotosUI
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
    case creditDetail
    case feedback
    case membership
    case referral

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
    @AppStorage("isSubscribed") private var isSubscribed = false
    @State private var destination: SettingsDestination?
    @State private var notice: SettingsNotice?
    @State private var isRestoring = false

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
                        SettingsRow(title: "Language", value: "English", action: { showNotice("Language", "English is the only language currently available.") })
                        SettingsRow(title: "FAQ", action: { showNotice("FAQ", "Find answers about credits, generations and subscriptions here.") })
                        SettingsRow(title: "Referral Code", action: { destination = .referral })
                        SettingsRow(title: "Feedback", action: { destination = .feedback })
                        SettingsRow(title: "Rate us", action: { showNotice("Rate us", "Thanks for helping Photo Revival grow.") })
                        SettingsRow(title: "Terms of Service", action: { showNotice("Terms of Service", "Terms of Service will open here when the production URL is connected.") })
                        SettingsRow(title: "Privacy Policy", action: { showNotice("Privacy Policy", "Privacy Policy will open here when the production URL is connected.") })
                        SettingsRow(title: "Version", value: "1.8.9", action: nil)
                    }
                    .padding(.top, 20)

                    Button {
                        showNotice("Sign Out", "Sign out is unavailable in this local preview.")
                    } label: {
                        Text("Sign Out")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(AppPalette.accent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 58)
                            .background(SettingsPalette.card.opacity(0.65), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    }
                    .buttonStyle(.plain)
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
        .fullScreenCover(item: $destination) { destination in
            switch destination {
            case .creditDetail:
                CreditDetailView(credits: $credits)
            case .feedback:
                FeedbackView()
            case .membership:
                PaywallOfferFlowView()
            case .referral:
                NavigationStack {
                    InviteFriendsView(credits: $credits)
                }
            }
        }
        .alert(item: $notice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
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
        Button {
            destination = .membership
        } label: {
            HStack(spacing: 13) {
                AccountAvatar()

                VStack(alignment: .leading, spacing: 7) {
                    Text("昆卡卡")
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(AppPalette.ink)

                    HStack(spacing: 9) {
                        HStack(spacing: 3) {
                            Image("RewardsCreditToken")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 25, height: 25)
                            Text("\(credits)")
                                .font(.system(size: 20, weight: .regular))
                                .foregroundStyle(AppPalette.ink)
                        }

                        Text("Join Now")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 15)
                            .frame(height: 32)
                            .background(AppPalette.accent, in: Capsule())
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(AppPalette.ink)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .frame(height: 100)
            .background(SettingsPalette.card, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings-account")
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
    var body: some View {
        ZStack(alignment: .bottom) {
            Circle()
                .fill(AppPalette.ink)
                .frame(width: 61, height: 61)

            Image(systemName: "person.fill")
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(Color(red: 1.00, green: 0.73, blue: 0.39))
                .offset(y: -3)

            Text("FREE")
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
    @State private var showMembership = false
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
        }
        .preferredColorScheme(.light)
        .fullScreenCover(isPresented: $showMembership) {
            PaywallOfferFlowView()
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
                showMembership = true
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
    @State private var feedback = ""
    @State private var email = "kunkamikasa@gmail.com"
    @State private var screenshotItem: PhotosPickerItem?
    @State private var screenshot: UIImage?
    @State private var showFAQ = false
    @State private var showSent = false

    private var canSubmit: Bool {
        !feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && email.contains("@")
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
                        showSent = true
                    } label: {
                        Text("Send Feedback")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(canSubmit ? AppPalette.accent : Color.gray.opacity(0.56), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSubmit)
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
                    Image(uiImage: screenshot)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 28, weight: .regular))
                        .foregroundStyle(SettingsPalette.muted)
                }
            }
            .frame(width: 80, height: 80)
            .background(SettingsPalette.card.opacity(0.76), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(SettingsPalette.fieldBorder, lineWidth: 1))
            .clipped()
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
}

#Preview("Settings") {
    SettingsView(credits: .constant(0))
}
