import SwiftUI
import UIKit

struct RootView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.scenePhase) private var scenePhase
    @State private var account: Account?
    @State private var lastScenePhase: ScenePhase = .inactive
    @State private var didLoadAccount = false
    @State private var externalRoute: ExternalRoute?
    @State private var accountTransitionTask: Task<Void, Never>?
    @State private var accountTransitionGeneration = 0

    var body: some View {
        Group {
            if didLoadAccount == false {
                ProgressView()
                    .controlSize(.large)
            } else {
                MainTabView(account: account)
            }
        }
        .task {
            let generation = accountTransitionGeneration
            let loadedAccount = try? await environment.accountStore.load()
            guard generation == accountTransitionGeneration else { return }
            await updateAccount(loadedAccount, generation: generation)
            guard generation == accountTransitionGeneration else { return }
            didLoadAccount = true
            await signAutomaticallyIfNeeded()
        }
        .onChange(of: scenePhase) { newPhase in
            let previousPhase = lastScenePhase
            lastScenePhase = newPhase
            // "First open of the day" also covers returning from the
            // background: the store's own per-day stamp keeps it to one run.
            guard previousPhase == .background, newPhase == .active else { return }
            Task { await signAutomaticallyIfNeeded() }
        }
        .onReceive(environment.accountStore.accountDidChange) { newAccount in
            accountTransitionGeneration &+= 1
            let generation = accountTransitionGeneration
            accountTransitionTask?.cancel()
            accountTransitionTask = Task { @MainActor in
                await updateAccount(newAccount, generation: generation)
                guard Task.isCancelled == false,
                      generation == accountTransitionGeneration else { return }
                didLoadAccount = true
                await signAutomaticallyIfNeeded()
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.didReceiveMemoryWarningNotification
        )) { _ in
            InlineContentTextMeasurementCache.drain()
            InlineContentTextViewPool.drain()
            Task {
                await TiebaImagePipeline.shared.releaseDecodedImageCache()
            }
        }
        .onOpenURL { url in
            guard let route = ExternalRoute.parse(url) else { return }
            externalRoute = route
        }
        .fullScreenCover(item: $externalRoute) { route in
            ExternalRouteView(account: account, route: route) {
                externalRoute = nil
            }
        }
    }

    private func signAutomaticallyIfNeeded() async {
        await environment.forumSignCoordinator.signAutomaticallyIfNeeded(account: account)
    }

    @MainActor
    private func updateAccount(_ newAccount: Account?, generation: Int) async {
        let previousAccount = account
        let invalidatedAccountID = AccountTransitionPolicy.invalidatedAccountID(
            previous: previousAccount,
            next: newAccount
        )
        let invalidatedSession = AccountTransitionPolicy.invalidatedSession(
            previous: previousAccount,
            next: newAccount
        )
        if let invalidatedSession {
            environment.socialMutationCoordinator.establishInvalidationBarrier(
                session: invalidatedSession
            )
            environment.forumSignCoordinator.establishInvalidationBarrier(
                session: invalidatedSession
            )
        }
        if let invalidatedAccountID {
            environment.contentSubmissionCoordinator.establishInvalidationBarrier(
                accountID: invalidatedAccountID
            )
        }
        var socialDrain: Task<Void, Never>?
        if let invalidatedSession {
            socialDrain = Task { @MainActor in
                await environment.socialMutationCoordinator.drainInvalidatedOperations(
                    session: invalidatedSession
                )
            }
        }
        var contentDrain: Task<Void, Never>?
        if let invalidatedAccountID {
            contentDrain = Task { @MainActor in
                await environment.contentSubmissionCoordinator.drainInvalidatedOperations(
                    accountID: invalidatedAccountID
                )
            }
        }
        var forumSignDrain: Task<Void, Never>?
        if let invalidatedSession {
            forumSignDrain = Task { @MainActor in
                await environment.forumSignCoordinator.drainInvalidatedOperations(
                    session: invalidatedSession
                )
            }
        }
        if let socialDrain {
            await socialDrain.value
        }
        if let contentDrain {
            await contentDrain.value
        }
        if let forumSignDrain {
            await forumSignDrain.value
        }
        defer {
            if let invalidatedAccountID {
                environment.contentSubmissionCoordinator.endInvalidation(
                    accountID: invalidatedAccountID
                )
            }
            if let invalidatedSession {
                environment.forumSignCoordinator.endInvalidation(
                    session: invalidatedSession
                )
                environment.socialMutationCoordinator.endInvalidation(
                    session: invalidatedSession
                )
            }
        }

        if let previousAccount, invalidatedSession != nil {
            environment.socialRelationshipState.reset(accountID: previousAccount.id)
        }
        guard Task.isCancelled == false,
              generation == accountTransitionGeneration else { return }
        account = newAccount
        if AccountTransitionPolicy.shouldReleaseGlobalInvalidation(
            previous: previousAccount,
            next: newAccount
        ) {
            // A successful logout deliberately leaves the global submission
            // barrier active. Release it only after the replacement account is
            // the session visible to the application.
            environment.contentSubmissionCoordinator.endInvalidation()
            environment.socialMutationCoordinator.endInvalidation()
            environment.forumSignCoordinator.endInvalidation()
        }
    }
}

enum AccountTransitionPolicy {
    static func invalidatedSession(
        previous: Account?,
        next: Account?
    ) -> AccountSessionIdentity? {
        guard let previous else { return nil }
        guard next?.sessionIdentity == previous.sessionIdentity else {
            return previous.sessionIdentity
        }
        return nil
    }

    static func invalidatedAccountID(previous: Account?, next: Account?) -> String? {
        invalidatedSession(previous: previous, next: next)?.accountID
    }

    static func shouldReleaseGlobalInvalidation(previous: Account?, next: Account?) -> Bool {
        previous == nil && next != nil
    }
}

/// Container for externally opened destinations. A cover with its own stack
/// keeps deep links independent of whichever tab and stack the user was in.
private struct ExternalRouteView: View {
    let account: Account?
    let route: ExternalRoute
    let onClose: () -> Void

    var body: some View {
        CompatibleNavigationStack {
            Group {
                switch route {
                case let .thread(id, postID):
                    ThreadDetailView(account: account, threadID: id, initialPostID: postID)
                case let .forum(name):
                    ForumThreadsView(account: account, forum: Forum(
                        id: 0,
                        name: name,
                        displayName: name.hasSuffix("吧") ? name : "\(name)吧",
                        avatarURL: nil,
                        memberCount: 0,
                        threadCount: 0
                    ))
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭", action: onClose)
                        .accessibilityIdentifier("external-route-close")
                }
            }
        }
    }
}

private struct MainTabView: View {
    let account: Account?
    @State private var selectedTab: RootTab = .home
    @State private var homeRefreshToken = 0
    @State private var hidesFloatingTabBar = false

    var body: some View {
        Group {
            if #available(iOS 18.0, *) {
                modernTabView
            } else {
                legacyTabView
            }
        }
        .compatibleTabBarVisibility(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if hidesFloatingTabBar == false {
                GlassTabBar(selectedTab: selectedTab, onSelect: selectTab)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
            }
        }
        .onPreferenceChange(FloatingTabBarVisibilityPreferenceKey.self) { requestedVisibility in
            // Source stacks change visibility while UIKit is laying out a push
            // or pop. Apply the state without an implicit SwiftUI transition so
            // the glass bar never briefly pops over forum or post content.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                hidesFloatingTabBar = requestedVisibility
            }
        }
        .background(
            TabSelectionObserver {
                homeRefreshToken += 1
            }
        )
    }

    @available(iOS 18.0, *)
    private var modernTabView: some View {
        TabView(selection: tabSelection) {
            Tab("首页", systemImage: "house", value: RootTab.home) {
                HomeView(account: account, refreshToken: homeRefreshToken)
            }

            Tab("进吧", systemImage: "square.grid.2x2", value: RootTab.forums) {
                ForumHubView(account: account)
            }

            Tab("我的", systemImage: "person.circle", value: RootTab.me) {
                MeView(account: account)
            }
        }
    }

    private var legacyTabView: some View {
        TabView(selection: tabSelection) {
            HomeView(account: account, refreshToken: homeRefreshToken)
                .tabItem {
                    Label("首页", systemImage: "house")
                }
                .tag(RootTab.home)

            ForumHubView(account: account)
                .tabItem {
                    Label("进吧", systemImage: "square.grid.2x2")
                }
                .tag(RootTab.forums)

            MeView(account: account)
                .tabItem {
                    Label("我的", systemImage: "person.circle")
                }
                .tag(RootTab.me)
        }
    }

    private var tabSelection: Binding<RootTab> {
        Binding(
            get: { selectedTab },
            set: applyTabSelection
        )
    }

    private func selectTab(_ tab: RootTab) {
        applyTabSelection(tab)
    }

    private func applyTabSelection(_ tab: RootTab) {
        guard tab != selectedTab else {
            // Keep the established home reselect refresh behavior, but do not
            // re-render the full glass bar for redundant forum/profile taps.
            if tab == .home { homeRefreshToken &+= 1 }
            return
        }

        // TabView and the material background can otherwise inherit an ambient
        // push/pop animation during a tap. A single disabled-animation
        // transaction keeps the content and selection indicator in lockstep.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selectedTab = tab
        }
    }
}

private struct GlassTabBar: View {
    @Environment(\.colorScheme) private var colorScheme

    let selectedTab: RootTab
    let onSelect: (RootTab) -> Void

    var body: some View {
        HStack(spacing: 4) {
            tabButton(.home, title: "首页", symbol: "house")
            tabButton(.forums, title: "进吧", symbol: "square.grid.2x2")
            tabButton(.me, title: "我的", symbol: "person.circle")
        }
        .padding(6)
        .background(glassFrame)
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
        .accessibilityIdentifier("root-glass-tab-bar")
    }

    private var glassFrame: some View {
        RoundedRectangle(cornerRadius: 31, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                if colorScheme == .dark {
                    RoundedRectangle(cornerRadius: 31, style: .continuous)
                        .fill(Color(red: 0.055, green: 0.075, blue: 0.11).opacity(0.58))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 31, style: .continuous)
                    .stroke(
                        colorScheme == .dark
                            ? Color.white.opacity(0.24)
                            : Color.white.opacity(0.72),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.42 : 0.14),
                radius: colorScheme == .dark ? 20 : 16,
                y: 8
            )
    }

    private func tabButton(_ tab: RootTab, title: String, symbol: String) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            onSelect(tab)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 21, weight: .semibold))
                    .frame(height: 22)
                Text(title)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundColor(tabForegroundColor(isSelected: isSelected))
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(
                Capsule()
                    .fill(selectionFillColor(isSelected: isSelected))
                    .padding(.vertical, 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(symbol)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "已选中" : "")
    }

    private func tabForegroundColor(isSelected: Bool) -> Color {
        if isSelected {
            return colorScheme == .dark
                ? Color(red: 0.33, green: 0.72, blue: 1)
                : .accentColor
        }
        return colorScheme == .dark ? Color.white.opacity(0.86) : .primary
    }

    private func selectionFillColor(isSelected: Bool) -> Color {
        guard isSelected else { return .clear }
        return colorScheme == .dark
            ? Color(red: 0.18, green: 0.36, blue: 0.52).opacity(0.72)
            : Color.white.opacity(0.48)
    }
}

enum RootTab: Hashable {
    case home
    case forums
    case me
}

private struct TabSelectionObserver: UIViewControllerRepresentable {
    let onReselectHome: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onReselectHome: onReselectHome)
    }

    func makeUIViewController(context: Context) -> Controller {
        Controller(coordinator: context.coordinator)
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        context.coordinator.onReselectHome = onReselectHome
        controller.coordinator = context.coordinator
        controller.isObservationActive = true
        controller.attachToTabBarController()
    }

    static func dismantleUIViewController(_ controller: Controller, coordinator: Coordinator) {
        controller.isObservationActive = false
        coordinator.detach()
    }

    final class Controller: UIViewController {
        var coordinator: Coordinator
        var isObservationActive = true

        init(coordinator: Coordinator) {
            self.coordinator = coordinator
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            attachToTabBarController()
        }

        func attachToTabBarController() {
            guard isObservationActive else { return }
            var visited = Set<ObjectIdentifier>()
            guard let tabBarController = tabBarController ?? findTabBarController(
                from: view.window?.rootViewController,
                visited: &visited
            ) else {
                return
            }
            coordinator.attach(to: tabBarController)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isObservationActive else { return }
                var currentVisited = Set<ObjectIdentifier>()
                guard let currentController = self.tabBarController ?? self.findTabBarController(
                    from: self.view.window?.rootViewController,
                    visited: &currentVisited
                ) else {
                    return
                }
                self.coordinator.attach(to: currentController)
            }
        }

        private func findTabBarController(
            from controller: UIViewController?,
            visited: inout Set<ObjectIdentifier>
        ) -> UITabBarController? {
            guard let controller else { return nil }

            let identifier = ObjectIdentifier(controller)
            guard visited.insert(identifier).inserted else { return nil }

            if let tabBarController = controller as? UITabBarController {
                return tabBarController
            }

            if let found = findTabBarController(from: controller.presentedViewController, visited: &visited) {
                return found
            }

            for child in controller.children {
                if let found = findTabBarController(from: child, visited: &visited) {
                    return found
                }
            }

            return nil
        }
    }

    final class Coordinator: NSObject, UITabBarControllerDelegate {
        var onReselectHome: () -> Void
        private weak var observedController: UITabBarController?
        private weak var previousDelegate: UITabBarControllerDelegate?

        init(onReselectHome: @escaping () -> Void) {
            self.onReselectHome = onReselectHome
        }

        func attach(to tabBarController: UITabBarController) {
            guard observedController !== tabBarController || tabBarController.delegate !== self else {
                tabBarController.tabBar.isHidden = true
                return
            }
            detach()
            if tabBarController.delegate !== self {
                previousDelegate = tabBarController.delegate
            }
            observedController = tabBarController
            tabBarController.delegate = self
            // iOS 15 has no SwiftUI API for hiding a tab bar. The floating
            // glass control owns tab interaction, so remove UIKit's bar from
            // both the visual and hit-test hierarchies on every deployment
            // target; iOS 16+ also receives the SwiftUI toolbar modifier.
            tabBarController.tabBar.isHidden = true
        }

        func detach() {
            if let observedController, observedController.delegate === self {
                observedController.delegate = previousDelegate
            }
            observedController?.tabBar.isHidden = false
            observedController = nil
            previousDelegate = nil
        }

        func tabBarController(
            _ tabBarController: UITabBarController,
            shouldSelect viewController: UIViewController
        ) -> Bool {
            let permitsSelection = previousDelegate?.tabBarController?(
                tabBarController,
                shouldSelect: viewController
            ) ?? true
            guard permitsSelection else { return false }

            if tabBarController.selectedViewController === viewController,
               tabBarController.viewControllers?.first === viewController {
                let callback = onReselectHome
                DispatchQueue.main.async {
                    callback()
                }
            }
            return true
        }

        func tabBarController(
            _ tabBarController: UITabBarController,
            didSelect viewController: UIViewController
        ) {
            previousDelegate?.tabBarController?(tabBarController, didSelect: viewController)
        }

        override func responds(to aSelector: Selector!) -> Bool {
            super.responds(to: aSelector) || previousDelegate?.responds(to: aSelector) == true
        }

        override func forwardingTarget(for aSelector: Selector!) -> Any? {
            if previousDelegate?.responds(to: aSelector) == true {
                return previousDelegate
            }
            return super.forwardingTarget(for: aSelector)
        }
    }
}

enum RootTabHitTester {
    static func tab(at point: CGPoint, itemFrames: [CGRect]) -> RootTab? {
        guard let index = itemFrames.firstIndex(where: { $0.contains(point) }) else { return nil }
        return RootTab(tabIndex: index)
    }
}

extension RootTab {
    init?(tabIndex: Int) {
        switch tabIndex {
        case 0:
            self = .home
        case 1:
            self = .forums
        case 2:
            self = .me
        default:
            return nil
        }
    }
}
