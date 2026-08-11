import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// iOS 15 compatibility shims for APIs introduced in iOS 16 or later.
///
/// Every shim forwards to the real system API when the app runs on a system
/// version that provides it, so behavior on modern iOS is unchanged; only
/// iOS 15 receives a degraded-but-functional fallback. Call sites are
/// rewritten to these equivalents by `scripts/apply_ios15_fixes.py` — keep
/// the two in sync.

// MARK: - URL

extension URL {
    /// Backport of `appending(path:directoryHint:)`.
    func compatAppending(path: String) -> URL {
        if #available(iOS 16.0, *) {
            return appending(path: path)
        }
        return appendingPathComponent(path)
    }

    /// Backport of `appending(queryItems:)`.
    func compatAppending(queryItems: [URLQueryItem]) -> URL {
        if #available(iOS 16.0, *) {
            return appending(queryItems: queryItems)
        }
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return self
        }
        var items = components.queryItems ?? []
        items.append(contentsOf: queryItems)
        components.queryItems = items
        return components.url ?? self
    }
}

// MARK: - Task sleep

extension Task where Success == Never, Failure == Never {
    /// Backport of `Task.sleep(for:)` taking plain seconds instead of
    /// `Duration` (which requires iOS 16).
    static func compatSleep(seconds: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    }
}

// MARK: - Font

extension Font {
    /// Backport of the text-style based `Font.system(_:design:weight:)`.
    static func compatSystem(
        _ style: Font.TextStyle,
        design: Font.Design? = nil,
        weight: Font.Weight? = nil
    ) -> Font {
        if #available(iOS 16.0, *) {
            return .system(style, design: design, weight: weight)
        }
        let uiStyle: UIFont.TextStyle
        switch style {
        case .largeTitle: uiStyle = .largeTitle
        case .title: uiStyle = .title1
        case .title2: uiStyle = .title2
        case .title3: uiStyle = .title3
        case .headline: uiStyle = .headline
        case .subheadline: uiStyle = .subheadline
        case .body: uiStyle = .body
        case .callout: uiStyle = .callout
        case .footnote: uiStyle = .footnote
        case .caption: uiStyle = .caption1
        case .caption2: uiStyle = .caption2
        default: uiStyle = .body
        }
        let pointSize = UIFont.preferredFont(forTextStyle: uiStyle).pointSize
        return .system(size: pointSize, weight: weight ?? .regular, design: design ?? .default)
    }
}

// MARK: - NavigationStack

/// Registry of destination builders backing the iOS 15 path-navigation
/// emulation inside `CompatiblePathNavigationStack`. Builders registered by
/// `.compatibleNavigationDestination(for:)` are looked up when a path entry
/// is pushed.
final class CompatibleNavigationDestinations: ObservableObject {
    private var builders: [ObjectIdentifier: (Any) -> AnyView] = [:]

    /// The legacy `NavigationLink` can ask for its destination before SwiftUI
    /// has evaluated the source view's destination modifier. Publishing the
    /// first registration lets a deferred destination re-evaluate instead of
    /// permanently caching an `EmptyView` on iOS 15.
    @Published private(set) var registrationGeneration = 0

    func register<Route: Hashable, Destination: View>(
        _ type: Route.Type,
        builder: @escaping (Route) -> Destination
    ) {
        let identifier = ObjectIdentifier(type)
        let isNewRegistration = builders[identifier] == nil
        builders[identifier] = { value in
            AnyView(builder(value as! Route))
        }
        if isNewRegistration {
            registrationGeneration &+= 1
        }
    }

    func destination<Route: Hashable>(for route: Route) -> AnyView? {
        builders[ObjectIdentifier(Route.self)]?(route)
    }
}

private struct CompatibleNavigationDestinationsKey: EnvironmentKey {
    static let defaultValue: CompatibleNavigationDestinations? = nil
}

extension EnvironmentValues {
    var compatibleNavigationDestinations: CompatibleNavigationDestinations? {
        get { self[CompatibleNavigationDestinationsKey.self] }
        set { self[CompatibleNavigationDestinationsKey.self] = newValue }
    }
}

private struct CompatibleDestinationRegistration<Route: Hashable, Destination: View>: ViewModifier {
    let type: Route.Type
    let builder: (Route) -> Destination

    @Environment(\.compatibleNavigationDestinations) private var destinations

    func body(content: Content) -> some View {
        // Register after the source view enters the hierarchy. Publishing from
        // `body` is undefined in SwiftUI and can itself destabilize legacy
        // NavigationView updates on iOS 15.
        content.onAppear {
            destinations?.register(type, builder: builder)
        }
    }
}

/// `NavigationStack` without a path binding. On iOS 15 this renders a plain
/// stack-style `NavigationView`.
struct CompatibleNavigationStack<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        if #available(iOS 16.0, *) {
            NavigationStack { content }
        } else {
            NavigationView { content }
                .navigationViewStyle(.stack)
        }
    }
}

/// `NavigationStack(path:)` deployable to iOS 15: a stack-style
/// `NavigationView` whose pushed levels mirror the bound path array through
/// a chain of hidden legacy `NavigationLink`s.
struct CompatiblePathNavigationStack<Route: Hashable, Content: View>: View {
    @Binding private var path: [Route]
    private let content: Content
    @State private var destinations = CompatibleNavigationDestinations()

    init(path: Binding<[Route]>, @ViewBuilder content: () -> Content) {
        _path = path
        self.content = content()
    }

    var body: some View {
        if #available(iOS 16.0, *) {
            NavigationStack(path: $path) { content }
        } else {
            NavigationView {
                content
                    .environment(\.compatibleNavigationDestinations, destinations)
                    .background(
                        CompatibleNavigationChain(path: $path, destinations: destinations)
                    )
            }
            .navigationViewStyle(.stack)
        }
    }
}

/// One hidden `NavigationLink` per path entry. Popping a level truncates the
/// path; appending to the path activates the matching link. Everything is
/// type-erased through `AnyView` so the recursive chain compiles.
private struct CompatibleNavigationChain<Route: Hashable>: View {
    @Binding var path: [Route]
    let destinations: CompatibleNavigationDestinations

    var body: some View {
        if path.isEmpty == false {
            link(at: 0)
        }
    }

    private func link(at index: Int) -> AnyView {
        AnyView(
            NavigationLink(
                isActive: Binding(
                    get: { path.count > index },
                    set: { isActive in
                        if isActive == false, path.count > index {
                            path = Array(path.prefix(index))
                        }
                    }
                ),
                destination: { destination(at: index) },
                label: { EmptyView() }
            )
        )
    }

    private func destination(at index: Int) -> AnyView {
        guard path.count > index else {
            return AnyView(EmptyView())
        }
        // Do not resolve the builder in the NavigationLink closure. On iOS 15
        // that closure may run before the source modifier registers its
        // builder, and the resulting EmptyView is then retained by UIKit for
        // the life of the pushed controller.
        return AnyView(
            CompatibleDeferredNavigationDestination(
                route: path[index],
                destinations: destinations
            )
            .background(nextLink(after: index))
        )
    }

    private func nextLink(after index: Int) -> AnyView {
        guard path.count > index + 1 else {
            return AnyView(EmptyView())
        }
        return link(at: index + 1)
    }
}

/// Resolves a legacy path-navigation destination only after it becomes visible.
/// This avoids the iOS 15 NavigationLink eager-destination behavior that would
/// otherwise turn a valid route into a permanently blank pushed page.
private struct CompatibleDeferredNavigationDestination<Route: Hashable>: View {
    let route: Route
    @ObservedObject var destinations: CompatibleNavigationDestinations

    var body: some View {
        // Establish an observation dependency before requesting the builder.
        // A first registration performed during the source view's evaluation
        // then invalidates this view and supplies the real destination.
        _ = destinations.registrationGeneration
        if let view = destinations.destination(for: route) {
            view
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("正在打开页面")
        }
    }
}

extension View {
    /// `navigationDestination(for:destination:)` deployable to iOS 15.
    @ViewBuilder
    func compatibleNavigationDestination<Route: Hashable, Destination: View>(
        for type: Route.Type,
        @ViewBuilder destination: @escaping (Route) -> Destination
    ) -> some View {
        if #available(iOS 16.0, *) {
            navigationDestination(for: type, destination: destination)
        } else {
            modifier(CompatibleDestinationRegistration(type: type, builder: destination))
        }
    }

    /// `navigationDestination(isPresented:destination:)` deployable to iOS 15.
    @ViewBuilder
    func compatibleNavigationDestination<Destination: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        if #available(iOS 16.0, *) {
            navigationDestination(isPresented: isPresented, destination: destination)
        } else {
            background(
                NavigationLink(isActive: isPresented, destination: destination) {
                    EmptyView()
                }
            )
        }
    }
}

// MARK: - Tab bar visibility

enum CompatibleTabBarVisibility {
    case visible
    case hidden
}

extension View {
    /// `toolbar(_:for: .tabBar)` deployable to iOS 15. iOS 15 has no SwiftUI
    /// tab-bar visibility API, so it degrades to a no-op there.
    @ViewBuilder
    func compatibleTabBarVisibility(_ visibility: CompatibleTabBarVisibility) -> some View {
        if #available(iOS 16.0, *) {
            toolbar(visibility == .hidden ? .hidden : .visible, for: .tabBar)
        } else {
            self
        }
    }
}

// MARK: - Scroll views and text

extension View {
    /// `scrollContentBackground(.hidden)` deployable to iOS 15.
    @ViewBuilder
    func compatibleScrollContentBackgroundHidden() -> some View {
        if #available(iOS 16.0, *) {
            scrollContentBackground(.hidden)
        } else {
            onAppear {
                // Form/List/TextEditor backgrounds are UIKit-backed on iOS 15.
                UITableView.appearance().backgroundColor = .clear
                UITextView.appearance().backgroundColor = .clear
            }
        }
    }

    /// `scrollDismissesKeyboard(.interactively)`. No equivalent exists on
    /// iOS 15, so it degrades to a no-op there.
    @ViewBuilder
    func compatibleScrollDismissesKeyboardInteractively() -> some View {
        if #available(iOS 16.0, *) {
            scrollDismissesKeyboard(.interactively)
        } else {
            self
        }
    }

    /// `scrollBounceBehavior(.always, axes: .vertical)` (iOS 16.4+).
    @ViewBuilder
    func compatibleScrollBounceBehaviorAlwaysVertical() -> some View {
        if #available(iOS 16.4, *) {
            scrollBounceBehavior(.always, axes: .vertical)
        } else {
            self
        }
    }

    /// `scrollIndicators(.hidden)`. iOS 15 keeps the default indicators.
    @ViewBuilder
    func compatibleScrollIndicatorsHidden() -> some View {
        if #available(iOS 16.0, *) {
            scrollIndicators(.hidden)
        } else {
            self
        }
    }

    /// `fontDesign(_:)` (iOS 16.1+).
    @ViewBuilder
    func compatibleFontDesign(_ design: Font.Design?) -> some View {
        if #available(iOS 16.1, *) {
            fontDesign(design)
        } else {
            self
        }
    }
}

// MARK: - ViewThatFits

/// Two-candidate horizontal `ViewThatFits` deployable to iOS 15.
struct CompatibleViewThatFits<First: View, Second: View>: View {
    private let axis: Axis.Set
    private let first: First
    private let second: Second

    init(in axis: Axis.Set = .horizontal, @ViewBuilder content: () -> TupleView<(First, Second)>) {
        self.axis = axis
        let pair = content()
        first = pair.value.0
        second = pair.value.1
    }

    var body: some View {
        if #available(iOS 16.0, *) {
            ViewThatFits(in: axis) {
                first
                second
            }
        } else {
            CompatibleViewThatFitsFallback(first: first, second: second)
        }
    }
}

/// Approximates `ViewThatFits` on iOS 15: measures the first candidate's
/// ideal width and swaps to the second when the available width would clip
/// it.
private struct CompatibleViewThatFitsFallback<First: View, Second: View>: View {
    let first: First
    let second: Second

    @State private var availableWidth: CGFloat = .infinity
    @State private var firstIdealWidth: CGFloat = 0

    private var showsFirst: Bool {
        firstIdealWidth == 0 || firstIdealWidth <= availableWidth
    }

    var body: some View {
        Group {
            if showsFirst {
                first
            } else {
                second
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { availableWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { availableWidth = $0 }
            }
        )
        .background(
            first
                .fixedSize(horizontal: true, vertical: false)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: CompatibleFirstIdealWidthKey.self,
                            value: proxy.size.width
                        )
                    }
                )
                .hidden()
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        )
        .onPreferenceChange(CompatibleFirstIdealWidthKey.self) { firstIdealWidth = $0 }
    }
}

private struct CompatibleFirstIdealWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - LabeledContent

/// `LabeledContent` deployable to iOS 15 (renders label — Spacer — value).
struct CompatibleLabeledContent<Label: View, Content: View>: View {
    private let label: Label
    private let content: Content

    private init(label: Label, content: Content) {
        self.label = label
        self.content = content
    }

    var body: some View {
        if #available(iOS 16.0, *) {
            LabeledContent(content: { content }, label: { label })
        } else {
            HStack(spacing: 12) {
                label
                Spacer(minLength: 8)
                content
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}

extension CompatibleLabeledContent where Label == Text {
    init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.init(label: Text(titleKey), content: content())
    }

    init(_ titleKey: LocalizedStringKey, value: String) where Content == Text {
        self.init(label: Text(titleKey), content: Text(value))
    }
}

// MARK: - ShareLink

/// `ShareLink` deployable to iOS 15 (presents a UIActivityViewController).
struct CompatibleShareLink<Label: View>: View {
    private let item: URL
    private let label: Label

    init(item: URL, @ViewBuilder label: () -> Label) {
        self.item = item
        self.label = label()
    }

    var body: some View {
        if #available(iOS 16.0, *) {
            ShareLink(item: item) { label }
        } else {
            Button {
                CompatibleSharePresenter.present(item)
            } label: {
                label
            }
        }
    }
}

private enum CompatibleSharePresenter {
    static func present(_ item: URL) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            ?? (UIApplication.shared.connectedScenes.first as? UIWindowScene)
        else { return }
        guard let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController
            ?? scene.windows.first?.rootViewController
        else { return }
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        let controller = UIActivityViewController(activityItems: [item], applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(
                x: top.view.bounds.midX,
                y: top.view.bounds.midY,
                width: 0,
                height: 0
            )
            popover.permittedArrowDirections = []
        }
        top.present(controller, animated: true)
    }
}

// MARK: - Vertical TextField

/// `TextField(_:text:axis: .vertical)` deployable to iOS 15. iOS 15 renders a
/// plain single-line field instead.
struct CompatibleVerticalTextField: View {
    private let titleKey: LocalizedStringKey
    @Binding private var text: String
    private let lineLimit: ClosedRange<Int>

    init(_ titleKey: LocalizedStringKey, text: Binding<String>, lineLimit: ClosedRange<Int>) {
        self.titleKey = titleKey
        _text = text
        self.lineLimit = lineLimit
    }

    var body: some View {
        if #available(iOS 16.0, *) {
            TextField(titleKey, text: $text, axis: .vertical)
                .lineLimit(lineLimit)
        } else {
            TextField(titleKey, text: $text)
                .lineLimit(1)
        }
    }
}

// MARK: - PhotosPicker

/// A picked photo that can load its image data on any supported iOS version,
/// hiding the iOS 16+ `PhotosPickerItem` type from call sites.
struct CompatiblePhotoItem: Equatable {
    private let id = UUID()
    private let loader: () async throws -> Data?

    fileprivate init(loader: @escaping () async throws -> Data?) {
        self.loader = loader
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }

    /// Equivalent of `PhotosPickerItem.loadTransferable(type: Data.self)`.
    func loadImageData() async throws -> Data? {
        try await loader()
    }
}

/// `PhotosPicker` deployable to iOS 15 (a button presenting a
/// `PHPickerViewController` in a sheet).
struct CompatiblePhotosPicker<Label: View>: View {
    @Binding private var selection: [CompatiblePhotoItem]
    private let maxSelectionCount: Int
    private let label: Label

    init(
        selection: Binding<[CompatiblePhotoItem]>,
        maxSelectionCount: Int,
        @ViewBuilder label: () -> Label
    ) {
        _selection = selection
        self.maxSelectionCount = maxSelectionCount
        self.label = label()
    }

    var body: some View {
        if #available(iOS 16.0, *) {
            CompatibleModernPhotosPicker(
                selection: $selection,
                maxSelectionCount: maxSelectionCount,
                label: label
            )
        } else {
            CompatibleLegacyPhotosPicker(
                selection: $selection,
                maxSelectionCount: maxSelectionCount,
                label: label
            )
        }
    }
}

@available(iOS 16.0, *)
private struct CompatibleModernPhotosPicker<Label: View>: View {
    @Binding var selection: [CompatiblePhotoItem]
    let maxSelectionCount: Int
    let label: Label
    @State private var items: [PhotosPickerItem] = []

    var body: some View {
        PhotosPicker(
            selection: $items,
            maxSelectionCount: maxSelectionCount,
            matching: .images,
            preferredItemEncoding: .current
        ) {
            label
        }
        .onChange(of: items) { newItems in
            guard newItems.isEmpty == false else { return }
            selection = newItems.map { item in
                CompatiblePhotoItem(loader: {
                    try await item.loadTransferable(type: Data.self)
                })
            }
            items = []
        }
    }
}

private struct CompatibleLegacyPhotosPicker<Label: View>: View {
    @Binding var selection: [CompatiblePhotoItem]
    let maxSelectionCount: Int
    let label: Label
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            label
        }
        .sheet(isPresented: $isPresented) {
            CompatiblePHPickerView(selectionLimit: max(1, maxSelectionCount)) { providers in
                selection = providers.map { provider in
                    CompatiblePhotoItem(loader: {
                        try await provider.loadCompatibleImageData()
                    })
                }
                isPresented = false
            }
        }
    }
}

private struct CompatiblePHPickerView: UIViewControllerRepresentable {
    let selectionLimit: Int
    let onPick: ([NSItemProvider]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.selectionLimit = selectionLimit
        configuration.filter = .images
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onPick: ([NSItemProvider]) -> Void

        init(onPick: @escaping ([NSItemProvider]) -> Void) {
            self.onPick = onPick
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            onPick(results.map(\.itemProvider))
        }
    }
}

private enum CompatiblePhotoPickerError: Error {
    case loadFailed
}

private extension NSItemProvider {
    func loadCompatibleImageData() async throws -> Data? {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data?, Error>) in
            loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: error ?? CompatiblePhotoPickerError.loadFailed)
                }
            }
        }
    }
}

// MARK: - UnevenRoundedRectangle

/// `UnevenRoundedRectangle` deployable to iOS 15. Draws the same per-corner
/// rounded shape directly; corner-style differences are imperceptible at the
/// radii used by the subpost sheet.
struct CompatibleUnevenRoundedRectangle: Shape {
    var topLeadingRadius: CGFloat = 0
    var bottomLeadingRadius: CGFloat = 0
    var bottomTrailingRadius: CGFloat = 0
    var topTrailingRadius: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let maxRadius = max(0, min(rect.width, rect.height) / 2)
        let topLeading = max(0, min(topLeadingRadius, maxRadius))
        let topTrailing = max(0, min(topTrailingRadius, maxRadius))
        let bottomTrailing = max(0, min(bottomTrailingRadius, maxRadius))
        let bottomLeading = max(0, min(bottomLeadingRadius, maxRadius))

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + topLeading, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - topTrailing, y: rect.minY))
        if topTrailing > 0 {
            path.addArc(
                center: CGPoint(x: rect.maxX - topTrailing, y: rect.minY + topTrailing),
                radius: topTrailing,
                startAngle: .degrees(-90),
                endAngle: .degrees(0),
                clockwise: false
            )
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomTrailing))
        if bottomTrailing > 0 {
            path.addArc(
                center: CGPoint(x: rect.maxX - bottomTrailing, y: rect.maxY - bottomTrailing),
                radius: bottomTrailing,
                startAngle: .degrees(0),
                endAngle: .degrees(90),
                clockwise: false
            )
        }
        path.addLine(to: CGPoint(x: rect.minX + bottomLeading, y: rect.maxY))
        if bottomLeading > 0 {
            path.addArc(
                center: CGPoint(x: rect.minX + bottomLeading, y: rect.maxY - bottomLeading),
                radius: bottomLeading,
                startAngle: .degrees(90),
                endAngle: .degrees(180),
                clockwise: false
            )
        }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topLeading))
        if topLeading > 0 {
            path.addArc(
                center: CGPoint(x: rect.minX + topLeading, y: rect.minY + topLeading),
                radius: topLeading,
                startAngle: .degrees(180),
                endAngle: .degrees(270),
                clockwise: false
            )
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Split-layout capability

enum ReaderSplitCapability {
    /// `NavigationSplitView` requires iOS 16; on iOS 15 the reader always
    /// uses the compact single-column navigation stack.
    static var supportsSplitColumns: Bool {
        if #available(iOS 16.0, *) {
            return true
        }
        return false
    }
}
