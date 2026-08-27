#if DEBUG
import SwiftUI
import UIKit

private extension Notification.Name {
    static let debugTestOverlayCanReleaseKeyWindow = Notification.Name("debugTestOverlayCanReleaseKeyWindow")
}

enum DebugPromotionRoute: Identifiable, Equatable {
    case returning(ReturningOfferVariant)
    case subscriberScratch

    var id: String {
        switch self {
        case .returning(let variant):
            "returning-\(variant.rawValue)"
        case .subscriberScratch:
            "subscriber-scratch"
        }
    }
}

private enum DebugUserState: String, CaseIterable, Identifiable {
    case live
    case signedOut
    case signedIn
    case returningUnsubscribed
    case returningSubscribed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .live:
            "真实状态"
        case .signedOut:
            "未登录用户"
        case .signedIn:
            "已登录用户（未订阅）"
        case .returningUnsubscribed:
            "回访 · 未订阅"
        case .returningSubscribed:
            "回访 · 已订阅"
        }
    }

    var systemImage: String {
        switch self {
        case .live:
            "person.crop.circle.badge.checkmark"
        case .signedOut:
            "person.crop.circle.badge.xmark"
        case .signedIn:
            "person.crop.circle.badge.checkmark"
        case .returningUnsubscribed:
            "person.crop.circle.badge.clock"
        case .returningSubscribed:
            "checkmark.seal.fill"
        }
    }
}

struct DebugTestWindowInstaller: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> DebugWindowAnchorView {
        let view = DebugWindowAnchorView()
        view.onWindowChanged = { window in
            context.coordinator.installIfNeeded(in: window?.windowScene)
        }
        return view
    }

    func updateUIView(_ uiView: DebugWindowAnchorView, context: Context) {
        context.coordinator.installIfNeeded(in: uiView.window?.windowScene)
    }

    static func dismantleUIView(_ uiView: DebugWindowAnchorView, coordinator: Coordinator) {
        coordinator.removeWindow()
    }

    final class Coordinator: NSObject {
        private var overlayWindow: DebugPassThroughWindow?

        override init() {
            super.init()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(releaseOverlayKeyWindow),
                name: .debugTestOverlayCanReleaseKeyWindow,
                object: nil
            )
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func installIfNeeded(in windowScene: UIWindowScene?) {
            guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1",
                  let windowScene,
                  overlayWindow?.windowScene !== windowScene else { return }

            removeWindow()

            let window = DebugPassThroughWindow(windowScene: windowScene)
            let controller = DebugOverlayViewController()
            controller.view.backgroundColor = .clear
            controller.view.isOpaque = false
            window.rootViewController = controller
            // Stay above app-owned full-screen covers while remaining below
            // system alerts and permission prompts.
            window.windowLevel = .normal + 1
            window.backgroundColor = .clear
            window.isHidden = false
            overlayWindow = window
        }

        func removeWindow() {
            overlayWindow?.isHidden = true
            overlayWindow?.rootViewController = nil
            overlayWindow = nil
        }

        @objc private func releaseOverlayKeyWindow() {
            guard let overlayWindow,
                  let applicationWindow = overlayWindow.windowScene?.windows.first(where: {
                      $0 !== overlayWindow && !$0.isHidden && $0.windowLevel == .normal
                  }) else { return }
            applicationWindow.makeKey()
        }
    }
}

final class DebugWindowAnchorView: UIView {
    var onWindowChanged: ((UIWindow?) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onWindowChanged?(window)
    }
}

private final class DebugPassThroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitView = super.hitTest(point, with: event)
        guard hitView === rootViewController?.view else { return hitView }
        return nil
    }
}

private final class DebugOverlayViewController: UIViewController, UIAdaptivePresentationControllerDelegate {
    private let bubbleButton = UIButton(type: .custom)

    override func viewDidLoad() {
        super.viewDidLoad()
        configureBubble()
    }

    private func configureBubble() {
        var configuration = UIButton.Configuration.filled()
        configuration.baseBackgroundColor = .systemOrange
        configuration.baseForegroundColor = .white
        configuration.image = UIImage(systemName: "wrench.and.screwdriver.fill")
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
            pointSize: 18,
            weight: .bold
        )
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        bubbleButton.configuration = configuration
        bubbleButton.layer.borderColor = UIColor.white.withAlphaComponent(0.92).cgColor
        bubbleButton.layer.borderWidth = 2
        bubbleButton.layer.cornerRadius = 23
        bubbleButton.layer.shadowColor = UIColor.black.cgColor
        bubbleButton.layer.shadowOpacity = 0.24
        bubbleButton.layer.shadowRadius = 8
        bubbleButton.layer.shadowOffset = CGSize(width: 0, height: 3)
        bubbleButton.accessibilityLabel = "Open debug test controls"
        bubbleButton.accessibilityIdentifier = "debug-test-bubble"
        bubbleButton.addTarget(self, action: #selector(openPanel), for: .touchUpInside)
        bubbleButton.translatesAutoresizingMaskIntoConstraints = false

        let badge = UILabel()
        badge.text = "D"
        badge.textColor = .white
        badge.font = .systemFont(ofSize: 9, weight: .black)
        badge.textAlignment = .center
        badge.backgroundColor = .black
        badge.layer.cornerRadius = 8.5
        badge.layer.masksToBounds = true
        badge.layer.borderColor = UIColor.white.cgColor
        badge.layer.borderWidth = 1.5
        badge.isAccessibilityElement = false
        badge.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(bubbleButton)
        bubbleButton.addSubview(badge)
        NSLayoutConstraint.activate([
            bubbleButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            bubbleButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            bubbleButton.widthAnchor.constraint(equalToConstant: 46),
            bubbleButton.heightAnchor.constraint(equalToConstant: 46),
            badge.widthAnchor.constraint(equalToConstant: 17),
            badge.heightAnchor.constraint(equalToConstant: 17),
            badge.trailingAnchor.constraint(equalTo: bubbleButton.trailingAnchor, constant: 2),
            badge.bottomAnchor.constraint(equalTo: bubbleButton.bottomAnchor, constant: 2)
        ])
    }

    @objc private func openPanel() {
        guard presentedViewController == nil else { return }
        view.window?.makeKey()

        let controller = UIHostingController(
            rootView: DebugTestPanel(
                onClose: { [weak self] in self?.closePanel() },
                onPresentPromotion: { [weak self] route in self?.openPromotion(route) }
            )
        )
        controller.modalPresentationStyle = .pageSheet
        controller.presentationController?.delegate = self
        if let sheet = controller.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.selectedDetentIdentifier = .large
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 28
        }
        present(controller, animated: true)
    }

    private func closePanel() {
        presentedViewController?.dismiss(animated: true) {
            NotificationCenter.default.post(name: .debugTestOverlayCanReleaseKeyWindow, object: nil)
        }
    }

    private func openPromotion(_ route: DebugPromotionRoute) {
        presentedViewController?.dismiss(animated: true) { [weak self] in
            guard let self else { return }
            self.view.window?.makeKey()
            let controller = UIHostingController(rootView: DebugPromotionPreview(route: route))
            controller.modalPresentationStyle = .fullScreen
            controller.presentationController?.delegate = self
            self.present(controller, animated: true)
        }
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        NotificationCenter.default.post(name: .debugTestOverlayCanReleaseKeyWindow, object: nil)
    }
}

private struct DebugTestPanel: View {
    @AppStorage("debugTestUserState") private var selectedStateRawValue = DebugUserState.live.rawValue
    @AppStorage("debugTestUserStateOverrideEnabled") private var isStateOverrideEnabled = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("isLoggedIn") private var isLoggedIn = false
    @AppStorage("isSubscribed") private var isSubscribed = false
    @AppStorage("returningOfferLastPresentedDay") private var returningOfferLastPresentedDay = 0.0
    @AppStorage("limitedOfferLastPresentedDay") private var limitedOfferLastPresentedDay = 0.0
    @AppStorage("subscriberScratchCompletedCampaignVersion") private var scratchCompletedVersion = 0

    let onClose: () -> Void
    let onPresentPromotion: (DebugPromotionRoute) -> Void

    private var selectedState: DebugUserState {
        DebugUserState(rawValue: selectedStateRawValue) ?? .live
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("用户状态", selection: stateBinding) {
                        ForEach(DebugUserState.allCases) { state in
                            Label(state.title, systemImage: state.systemImage)
                                .tag(state)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    .accessibilityIdentifier("debug-user-state-picker")

                    LabeledContent("当前登录态", value: isLoggedIn ? "已登录（模拟）" : "未登录")
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("debug-current-login-state")
                        .accessibilityValue(isLoggedIn ? "signed-in" : "signed-out")
                    LabeledContent("当前订阅态", value: isSubscribed ? "已订阅（模拟）" : "未订阅")
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("debug-current-subscription-state")
                        .accessibilityValue(isSubscribed ? "subscribed" : "unsubscribed")
                } header: {
                    Text("界面状态")
                } footer: {
                    Text("模拟状态只影响本机 Debug 界面和促销资格，不会创建服务器账号，也不会伪造 App Store 购买。切回真实状态会重新读取登录与订阅。")
                }

                Section("回访未订阅用户") {
                    promotionButton(
                        "家庭专享订阅促销",
                        systemImage: "person.3.fill",
                        state: .returningUnsubscribed,
                        route: .returning(.familyExclusive)
                    )
                    promotionButton(
                        "超级奖品订阅促销",
                        systemImage: "gift.fill",
                        state: .returningUnsubscribed,
                        route: .returning(.superPrize)
                    )
                    promotionButton(
                        "限时订阅促销",
                        systemImage: "timer",
                        state: .returningUnsubscribed,
                        route: .returning(.limitedTime)
                    )
                }

                Section("回访已订阅用户") {
                    promotionButton(
                        "积分刮刮卡促销",
                        systemImage: "ticket.fill",
                        state: .returningSubscribed,
                        route: .subscriberScratch
                    )
                }

                Section("促销资格") {
                    Button {
                        resetPromotionEligibility()
                    } label: {
                        Label("重置全部促销资格", systemImage: "arrow.counterclockwise")
                    }

                    LabeledContent(
                        "积分刮刮卡",
                        value: scratchCompletedVersion < SubscriberScratchCampaign.version ? "可触发" : "已完成"
                    )
                }
            }
            .navigationTitle("Debug 测试")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成", action: onClose)
                }
            }
        }
        .preferredColorScheme(.light)
        .accessibilityIdentifier("debug-test-panel")
    }

    private var stateBinding: Binding<DebugUserState> {
        Binding(
            get: { selectedState },
            set: { apply($0) }
        )
    }

    private func promotionButton(
        _ title: String,
        systemImage: String,
        state: DebugUserState,
        route: DebugPromotionRoute
    ) -> some View {
        Button {
            resetPresentationCooldown(for: route)
            apply(state)
            onPresentPromotion(route)
        } label: {
            Label(title, systemImage: systemImage)
        }
    }

    private func apply(_ state: DebugUserState) {
        selectedStateRawValue = state.rawValue

        switch state {
        case .live:
            isStateOverrideEnabled = false
            isLoggedIn = PhotoReviveAuthClient.shared.currentUserID != nil
            Task {
                let hasEntitlement = await SubscriptionPurchaseService.hasActiveStoreEntitlement()
                guard !isStateOverrideEnabled else { return }
                isSubscribed = hasEntitlement
                AppAnalytics.updateSubscription(isSubscribed: hasEntitlement)
            }
        case .signedOut:
            isStateOverrideEnabled = true
            isLoggedIn = false
            isSubscribed = false
        case .signedIn:
            isStateOverrideEnabled = true
            hasCompletedOnboarding = true
            isLoggedIn = true
            isSubscribed = false
        case .returningUnsubscribed:
            isStateOverrideEnabled = true
            hasCompletedOnboarding = true
            isLoggedIn = true
            isSubscribed = false
        case .returningSubscribed:
            isStateOverrideEnabled = true
            hasCompletedOnboarding = true
            isLoggedIn = true
            isSubscribed = true
        }
    }

    private func resetPresentationCooldown(for route: DebugPromotionRoute) {
        switch route {
        case .returning:
            returningOfferLastPresentedDay = 0
            limitedOfferLastPresentedDay = 0
        case .subscriberScratch:
            scratchCompletedVersion = 0
        }
    }

    private func resetPromotionEligibility() {
        returningOfferLastPresentedDay = 0
        limitedOfferLastPresentedDay = 0
        scratchCompletedVersion = 0
    }
}

struct DebugPromotionPreview: View {
    let route: DebugPromotionRoute

    @AppStorage("subscriberScratchCompletedCampaignVersion") private var scratchCompletedVersion = 0

    var body: some View {
        switch route {
        case .returning(let variant):
            ReturningPromotionFlowView(variant: variant)
        case .subscriberScratch:
            SubscriberScratchOfferView(
                onRewardClaimed: {
                    scratchCompletedVersion = SubscriberScratchCampaign.version
                },
                claimOverride: {
                    // The Debug preview exercises the complete reward animation
                    // without issuing a claim against the production API.
                }
            )
        }
    }
}
#endif
