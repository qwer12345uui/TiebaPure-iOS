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
        NavigationStack {
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedTab: RootTab = .home
    @State private var homeRefreshToken = 0

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                tabContent(.home)
                    .offset(
                        x: RootTabTransitionPolicy.pageOffset(
                            content: .home,
                            selected: selectedTab,
                            pageWidth: proxy.size.width
                        )
                    )
                    .allowsHitTesting(selectedTab == .home)

                tabContent(.forums)
                    .offset(
                        x: RootTabTransitionPolicy.pageOffset(
                            content: .forums,
                            selected: selectedTab,
                            pageWidth: proxy.size.width
                        )
                    )
                    .allowsHitTesting(selectedTab == .forums)

                tabContent(.me)
                    .offset(
                        x: RootTabTransitionPolicy.pageOffset(
                            content: .me,
                            selected: selectedTab,
                            pageWidth: proxy.size.width
                        )
                    )
                    .allowsHitTesting(selectedTab == .me)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .animation(tabAnimation, value: selectedTab)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            RootTabBar(
                selection: $selectedTab,
                onReselectHome: {
                    homeRefreshToken += 1
                },
                selectionAnimation: tabAnimation,
                reduceMotion: reduceMotion
            )
        }
    }

    @ViewBuilder
    private func tabContent(_ tab: RootTab) -> some View {
        switch tab {
        case .home:
            HomeView(account: account, refreshToken: homeRefreshToken)
        case .forums:
            ForumHubView(account: account)
        case .me:
            MeView(account: account)
        }
    }

    private var tabAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: RootTabTransitionPolicy.duration)
    }
}

private struct RootTabBar: View {
    @Binding var selection: RootTab
    let onReselectHome: () -> Void
    let selectionAnimation: Animation?
    let reduceMotion: Bool
    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: 8) {
            ForEach(RootTab.allCases, id: \.self) { tab in
                tabButton(for: tab)
            }
        }
        .frame(maxWidth: 420)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private func tabButton(for tab: RootTab) -> some View {
        let isSelected = selection == tab
        return Button {
            guard tab != selection else {
                if RootTabTransitionPolicy.shouldRefreshHome(
                    current: selection,
                    requested: tab
                ) {
                    onReselectHome()
                }
                return
            }

            withAnimation(selectionAnimation) {
                selection = tab
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: isSelected ? tab.selectedSystemImage : tab.systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(height: 20)
                Text(tab.title)
                    .font(.caption2.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(
                isSelected ? TiebaPureTheme.ColorToken.primaryAccent : Color.secondary
            )
            .frame(maxWidth: .infinity, minHeight: 49)
            .contentShape(Capsule())
            .background {
                if isSelected {
                    Capsule()
                        .fill(TiebaPureTheme.ColorToken.primaryAccent.opacity(0.16))
                        .matchedGeometryEffect(id: "root-tab-selection", in: selectionNamespace)
                }
            }
        }
        .buttonStyle(RootTabButtonStyle(reduceMotion: reduceMotion))
        .accessibilityIdentifier(tab.systemImage)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct RootTabButtonStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.74 : 1)
            .scaleEffect(configuration.isPressed && reduceMotion == false ? 0.96 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
    }
}

enum RootTab: Int, CaseIterable, Hashable {
    case home
    case forums
    case me

    var index: Int { rawValue }

    var title: String {
        switch self {
        case .home:
            "首页"
        case .forums:
            "进吧"
        case .me:
            "我的"
        }
    }

    var systemImage: String {
        switch self {
        case .home:
            "house"
        case .forums:
            "square.grid.2x2"
        case .me:
            "person.circle"
        }
    }

    var selectedSystemImage: String {
        switch self {
        case .home:
            "house.fill"
        case .forums:
            "square.grid.2x2.fill"
        case .me:
            "person.circle.fill"
        }
    }
}

enum RootTabTransitionPolicy {
    static let duration = 0.30

    static func pageOffset(
        content: RootTab,
        selected: RootTab,
        pageWidth: CGFloat
    ) -> CGFloat {
        CGFloat(content.index - selected.index) * pageWidth
    }

    static func shouldRefreshHome(current: RootTab, requested: RootTab) -> Bool {
        current == .home && requested == .home
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
