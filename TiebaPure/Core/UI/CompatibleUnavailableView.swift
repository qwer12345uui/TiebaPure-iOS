import SwiftUI
import UIKit

struct CompatibleUnavailableView: View {
    let title: LocalizedStringKey
    let systemImage: String
    let description: Text?

    init(
        _ title: LocalizedStringKey,
        systemImage: String,
        description: Text? = nil
    ) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
    }

    @ViewBuilder
    var body: some View {
        if #available(iOS 17.0, *) {
            ContentUnavailableView(
                title,
                systemImage: systemImage,
                description: description
            )
        } else {
            VStack(spacing: TiebaPureTheme.Spacing.sm) {
                Image(systemName: systemImage)
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(.secondary)

                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.center)

                if let description {
                    description
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(TiebaPureTheme.Spacing.lg)
        }
    }
}


/// A navigation container that retains `NavigationStack` behavior on iOS 16
/// and later while falling back to the iOS 15 `NavigationView` implementation.
struct CompatibleNavigationContainer<Content: View>: View {
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    @ViewBuilder
    var body: some View {
        if #available(iOS 16.0, *) {
            NavigationStack {
                content()
            }
        } else {
            NavigationView {
                content()
            }
            .navigationViewStyle(.stack)
        }
    }
}

/// A path-backed navigation container. iOS 15 cannot represent a typed
/// `NavigationPath`, so the latest route is exposed through an ordinary
/// binding-based `NavigationLink`. The source of truth remains the same route
/// array used by iOS 16 and newer.
struct CompatiblePathNavigationContainer<Route: Hashable, Content: View, Destination: View>: View {
    @Binding private var path: [Route]
    private let destination: (Route) -> Destination
    private let content: () -> Content

    init(
        path: Binding<[Route]>,
        @ViewBuilder destination: @escaping (Route) -> Destination,
        @ViewBuilder content: @escaping () -> Content
    ) {
        _path = path
        self.destination = destination
        self.content = content
    }

    @ViewBuilder
    var body: some View {
        if #available(iOS 16.0, *) {
            NavigationStack(path: $path) {
                content()
                    .navigationDestination(for: Route.self, destination: destination)
            }
        } else {
            NavigationView {
                ZStack {
                    content()
                    legacyDestinationLink
                }
            }
            .navigationViewStyle(.stack)
        }
    }

    @ViewBuilder
    private var legacyDestinationLink: some View {
        if let route = path.last {
            NavigationLink(isActive: legacyRouteIsPresented) {
                destination(route)
            } label: {
                EmptyView()
            }
            .hidden()
            .accessibilityHidden(true)
        }
    }

    private var legacyRouteIsPresented: Binding<Bool> {
        Binding(
            get: { path.isEmpty == false },
            set: { isPresented in
                if isPresented == false {
                    path = []
                }
            }
        )
    }
}

private struct CompatibleBooleanNavigationDestination<Destination: View>: View {
    @Binding var isPresented: Bool
    let destination: () -> Destination

    @ViewBuilder
    var body: some View {
        if #available(iOS 16.0, *) {
            Color.clear
                .navigationDestination(isPresented: $isPresented, destination: destination)
        } else {
            NavigationLink(isActive: $isPresented, destination: destination) {
                EmptyView()
            }
            .hidden()
            .accessibilityHidden(true)
        }
    }
}

extension View {
    /// Cross-version replacement for the iOS 16 Boolean navigation-destination
    /// API. iOS 15 uses a hidden binding-based `NavigationLink` instead.
    func compatibleNavigationDestination<Destination: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        background(
            CompatibleBooleanNavigationDestination(
                isPresented: isPresented,
                destination: destination
            )
        )
    }

    /// Adds a typed destination only where `NavigationStack` is available.
    /// iOS 15 path navigation is supplied by `CompatiblePathNavigationContainer`.
    @ViewBuilder
    func compatibleNavigationDestination<Route: Hashable, Destination: View>(
        for routeType: Route.Type,
        @ViewBuilder destination: @escaping (Route) -> Destination
    ) -> some View {
        if #available(iOS 16.0, *) {
            navigationDestination(for: routeType, destination: destination)
        } else {
            self
        }
    }

    /// Keeps the tab bar explicitly visible on iOS 16 and later. On iOS 15
    /// the standard tab-bar behavior already remains visible.
    @ViewBuilder
    func compatibleTabBarVisibility() -> some View {
        if #available(iOS 16.0, *) {
            toolbar(.visible, for: .tabBar)
        } else {
            self
        }
    }

    /// Hides a scroll surface background only on systems that expose the API.
    @ViewBuilder
    func compatibleScrollContentBackgroundHidden() -> some View {
        if #available(iOS 16.0, *) {
            scrollContentBackground(.hidden)
        } else {
            self
        }
    }

    /// Requests interactive keyboard dismissal where supported without
    /// preventing scrolling on iOS 15.
    @ViewBuilder
    func compatibleInteractiveKeyboardDismissal() -> some View {
        if #available(iOS 16.0, *) {
            scrollDismissesKeyboard(.interactively)
        } else {
            self
        }
    }
}


extension View {
    /// Uses size-based scroll bounce only where the API is available; iOS 15
    /// keeps UIKit's default scroll behavior.
    @ViewBuilder
    func compatibleScrollBounceBehaviorBasedOnSize() -> some View {
        if #available(iOS 16.4, *) {
            scrollBounceBehavior(.basedOnSize)
        } else {
            self
        }
    }
}


extension View {
    /// Keeps the preferred vertical bounce behavior on iOS 16.4 and later.
    /// Earlier releases use their native scroll-view defaults.
    @ViewBuilder
    func compatibleAlwaysVerticalScrollBounce() -> some View {
        if #available(iOS 16.4, *) {
            scrollBounceBehavior(.always, axes: .vertical)
        } else {
            self
        }
    }
}


/// Preserves `ViewThatFits` selection on iOS 16 and later. On iOS 15 the
/// caller-provided primary layout remains visible, while the fallback layout is
/// intentionally omitted instead of rendering two conflicting control groups.
struct CompatibleViewThatFits<Primary: View, Fallback: View>: View {
    private let primary: () -> Primary
    private let fallback: () -> Fallback

    init(
        @ViewBuilder primary: @escaping () -> Primary,
        @ViewBuilder fallback: @escaping () -> Fallback
    ) {
        self.primary = primary
        self.fallback = fallback
    }

    @ViewBuilder
    var body: some View {
        if #available(iOS 16.0, *) {
            ViewThatFits(in: .horizontal) {
                primary()
                fallback()
            }
        } else {
            primary()
        }
    }
}


/// A cross-version sharing control. `ShareLink` remains in use where it is
/// available; iOS 15 presents the equivalent UIKit activity sheet.
struct CompatibleShareLink<Label: View>: View {
    let item: URL
    private let label: () -> Label
    @State private var isPresentingActivitySheet = false

    init(item: URL, @ViewBuilder label: @escaping () -> Label) {
        self.item = item
        self.label = label
    }

    @ViewBuilder
    var body: some View {
        if #available(iOS 16.0, *) {
            ShareLink(item: item, label: label)
        } else {
            Button {
                isPresentingActivitySheet = true
            } label: {
                label()
            }
            .sheet(isPresented: $isPresentingActivitySheet) {
                CompatibleActivitySheet(items: [item])
            }
        }
    }
}

private struct CompatibleActivitySheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}


/// Lets screens that hide the system tab bar also hide the root's iOS 15
/// floating tab chrome. Preferences flow through both NavigationView and
/// NavigationStack without adding recognizers or overlay hit targets.
struct FloatingTabBarHiddenPreferenceKey: PreferenceKey {
    static var defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

extension View {
    /// Hides the tab bar where SwiftUI exposes the per-bar toolbar API and
    /// communicates the same intent to the iOS 15-compatible floating shell.
    @ViewBuilder
    func compatibleTabBarHidden() -> some View {
        if #available(iOS 16.0, *) {
            toolbar(.hidden, for: .tabBar)
                .preference(key: FloatingTabBarHiddenPreferenceKey.self, value: true)
        } else {
            preference(key: FloatingTabBarHiddenPreferenceKey.self, value: true)
        }
    }
}


extension View {
    /// Applies SwiftUI scroll indicator visibility only on systems that expose
    /// the API; iOS 15 retains the platform default indicator behavior.
    @ViewBuilder
    func compatibleScrollIndicatorsHidden() -> some View {
        if #available(iOS 16.0, *) {
            scrollIndicators(.hidden)
        } else {
            self
        }
    }
}
