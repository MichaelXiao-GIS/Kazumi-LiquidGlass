import Flutter
import UIKit

/// Small native bridge: Flutter owns routing/content, UIKit owns glass controls.
final class KazumiGlassPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private let registrar: FlutterPluginRegistrar
    private var probe: KazumiSceneProbe?

    private init(registrar: FlutterPluginRegistrar) { self.registrar = registrar }

    static func register(with registrar: FlutterPluginRegistrar) {
        let plugin = KazumiGlassPlugin(registrar: registrar)
        FlutterEventChannel(name: "com.predidit.kazumi/scene",
                            binaryMessenger: registrar.messenger()).setStreamHandler(plugin)
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        // Listen after Flutter's view has attached to its UIScene, never select
        // an arbitrary UIApplication window (which may belong to another scene).
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let root = self.registrar.viewController?.view else { return }
            self.probe?.removeFromSuperview()
            let probe = KazumiSceneProbe(frame: root.bounds)
            probe.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            probe.isUserInteractionEnabled = false
            probe.isAccessibilityElement = false
            probe.events = events
            root.addSubview(probe)
            self.probe = probe
            probe.publish()
        }
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        probe?.events = nil
        probe?.removeFromSuperview()
        probe = nil
        return nil
    }
}

private final class KazumiSceneProbe: UIView {
    var events: FlutterEventSink?
    private var lastMetrics: NSDictionary?
    private var observers: [NSObjectProtocol] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        for name in [UIAccessibility.reduceTransparencyStatusDidChangeNotification,
                     UIAccessibility.reduceMotionStatusDidChangeNotification,
                     UIAccessibility.darkerSystemColorsStatusDidChangeNotification,
                     UIApplication.didBecomeActiveNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name,
                object: nil, queue: .main) { [weak self] _ in self?.publish() })
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    override func layoutSubviews() { super.layoutSubviews(); publish() }
    override func safeAreaInsetsDidChange() { super.safeAreaInsetsDidChange(); publish() }
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        publish()
    }

    func publish() {
        var occlusions: [[CGFloat]] = []
        var divisions: [[CGFloat]] = []
        if #available(iOS 27.1, *) {
            func frames(_ kind: UIView.ReservedRegion.Kind) -> [[CGFloat]] {
                reservedRegions(kind: kind).filter(\.isActive).map {
                    [$0.frame.minX, $0.frame.minY, $0.frame.width, $0.frame.height]
                }
            }
            occlusions = frames(.occlusion)
            divisions = frames(.division)
        }
        let metrics: NSDictionary = [
            "width": bounds.width, "height": bounds.height,
            "occlusions": occlusions, "divisions": divisions,
            "reduceTransparency": UIAccessibility.isReduceTransparencyEnabled,
            "reduceMotion": UIAccessibility.isReduceMotionEnabled,
            "highContrast": UIAccessibility.isDarkerSystemColorsEnabled
        ]
        guard lastMetrics != metrics else { return }
        lastMetrics = metrics
        // Avoid sending an event in the middle of the engine's metrics update.
        DispatchQueue.main.async { [weak self] in self?.events?(metrics) }
    }
}

final class KazumiSceneDelegate: FlutterSceneDelegate {
    override func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
                        options connectionOptions: UIScene.ConnectionOptions) {
        // Let Flutter register the storyboard's implicit engine with this scene first.
        super.scene(scene, willConnectTo: session, options: connectionOptions)
        guard let window, let flutter = window.rootViewController as? FlutterViewController else { return }
        // Keep URL and foreground/background delivery associated with this scene
        // even while UIKit is transitioning between the tab content views.
        registerSceneLifeCycle(with: flutter.engine)
        window.rootViewController = nil
        let host = KazumiTabBarController(content: flutter)
        window.rootViewController = host
        host.connect(to: flutter.binaryMessenger)
    }
}

// A single Flutter engine owns all four route stacks. Keep its controller alive
// and attach it to the incoming tab before UIKit displays that tab.
private final class KazumiTabPage: UIViewController {
    weak var host: KazumiTabBarController?

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        host?.attachContent(to: self)
    }

    // The tab controller forwards its own appearance transitions to Flutter.
    // Moving between tabs within a single Flutter page must not pause the engine.
    override var shouldAutomaticallyForwardAppearanceMethods: Bool { false }
}

final class KazumiTabBarController: UITabBarController, UITabBarControllerDelegate {
    private let content: UIViewController
    private let pages = (0..<4).map { _ in KazumiTabPage() }
    private let searchPage = UIViewController()
    private var channel: FlutterMethodChannel?
    private var requestsScrollToTop = false
    private var lastPlacement: Bool?
    private var resizing = false
    private lazy var scrollToTop: UIButton = {
        let button = UIButton(type: .system)
        if #available(iOS 26.0, *) {
            var style = UIButton.Configuration.glass()
            style.cornerStyle = .capsule
            style.image = UIImage(systemName: "arrow.up")
            button.configuration = style
        }
        button.accessibilityLabel = "返回顶部"
        button.accessibilityHint = "滚动推荐列表到最上方"
        button.isHidden = true
        button.addTarget(self, action: #selector(scrollToTopTapped), for: .touchUpInside)
        return button
    }()
    var onSelect: ((Int) -> Void)?
    var onSearch: (() -> Void)?

    init(content: UIViewController) {
        self.content = content
        super.init(nibName: nil, bundle: nil)
        let destinations = [
            ("recommend", "推荐", "play.rectangle"), ("timeline", "时间表", "calendar"),
            ("following", "追番", "heart"), ("profile", "我的", "person.crop.circle")
        ]
        pages.forEach { $0.host = self }
        delegate = self
        if #available(iOS 18.0, *) {
            let routes = zip(destinations, pages).map { item, page in
                UITab(title: item.1, image: UIImage(systemName: item.2), identifier: item.0) { _ in page }
            }
            let search = UISearchTab { [searchPage] _ in searchPage }
            search.title = "搜索番剧"
            tabs = routes + [search]
            if #available(iOS 27.0, *) { prominentTabIdentifier = search.identifier }
        } else {
            for (index, item) in destinations.enumerated() {
                pages[index].tabBarItem = UITabBarItem(title: item.1, image: UIImage(systemName: item.2), tag: index)
            }
            searchPage.tabBarItem = UITabBarItem(title: "搜索番剧", image: UIImage(systemName: "magnifyingglass"), tag: 4)
            viewControllers = pages + [searchPage]
        }
        view.addSubview(scrollToTop)
        attachContent(to: pages[0])
        setChromeVisible(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func connect(to messenger: FlutterBinaryMessenger) {
        let bridge = FlutterMethodChannel(name: "com.predidit.kazumi/tabs", binaryMessenger: messenger)
        channel = bridge
        onSelect = { bridge.invokeMethod("select", arguments: $0) }
        onSearch = { bridge.invokeMethod("search", arguments: nil) }
        bridge.setMethodCallHandler { [weak self] call, result in
            switch call.method {
            case "update":
                if let config = call.arguments as? [String: Any] { self?.update(config) }
            case "hide":
                self?.setChromeVisible(false)
            default:
                result(FlutterMethodNotImplemented); return
            }
            result(nil)
        }
    }

    deinit { channel?.setMethodCallHandler(nil) }

    fileprivate func attachContent(to page: UIViewController) {
        guard content.parent !== page else { return }
        if content.parent != nil {
            content.willMove(toParent: nil)
            content.view.removeFromSuperview()
            content.removeFromParent()
        }
        page.addChild(content)
        content.view.frame = page.view.bounds
        content.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        page.view.addSubview(content.view)
        content.didMove(toParent: page)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        content.beginAppearanceTransition(true, animated: animated)
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        content.endAppearanceTransition()
        view.setNeedsLayout()
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        content.beginAppearanceTransition(false, animated: animated)
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        content.endAppearanceTransition()
    }

    override var childForStatusBarStyle: UIViewController? { content }
    override var childForStatusBarHidden: UIViewController? { content }
    override var childForHomeIndicatorAutoHidden: UIViewController? { content }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { content.supportedInterfaceOrientations }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        content.preferredInterfaceOrientationForPresentation
    }

    func update(_ config: [String: Any]) {
        overrideUserInterfaceStyle = config["dark"] as? Bool == true ? .dark : .light
        if let argb = config["tint"] as? NSNumber {
            let rgb = argb.uint32Value
            view.tintColor = UIColor(red: CGFloat((rgb >> 16) & 255) / 255,
                                       green: CGFloat((rgb >> 8) & 255) / 255,
                                       blue: CGFloat(rgb & 255) / 255, alpha: 1)
            tabBar.tintColor = view.tintColor
        }
        if let index = config["selectedIndex"] as? Int, pages.indices.contains(index) {
            if #available(iOS 18.0, *) {
                if selectedTab !== tabs[index] { selectedTab = tabs[index] }
            } else if selectedIndex != index {
                selectedIndex = index
            }
        }
        requestsScrollToTop = config["scrollToTop"] as? Bool == true && config["selectedIndex"] as? Int == 0
        lastPlacement = nil
        setChromeVisible(config["visible"] as? Bool ?? true)
        view.setNeedsLayout()
    }

    @objc private func scrollToTopTapped() {
        channel?.invokeMethod("scrollToTop", arguments: nil)
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        resizing = true
        publishScrollToTop(frame: nil)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            self?.resizing = false
            self?.view.setNeedsLayout()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard #available(iOS 27.1, *), requestsScrollToTop, !resizing, !isTabBarHidden,
              view.window != nil else {
            publishScrollToTop(frame: nil)
            return
        }

        let bounds = view.bounds
        let guide = contentLayoutGuide.layoutFrame
        let safe = content.view.convert(content.view.safeAreaLayoutGuide.layoutFrame, to: view)
        let body = guide.intersection(safe)
        guard !body.isNull, body.width > bounds.width / 2 else {
            publishScrollToTop(frame: nil)
            return
        }
        let edge = traitCollection.verticalBarEdge
        guard edge == .leading || edge == .trailing else {
            publishScrollToTop(frame: nil)
            return
        }
        let onLeft = (edge == .leading) == (view.effectiveUserInterfaceLayoutDirection == .leftToRight)
        let width = onLeft ? body.minX - bounds.minX : bounds.maxX - body.maxX
        guard width >= 52 else {
            publishScrollToTop(frame: nil)
            return
        }
        let x = onLeft ? bounds.minX : bounds.maxX - width
        let gutter = CGRect(x: x, y: bounds.minY, width: width, height: bounds.height)
        let reserved = (view.reservedRegions(kind: .occlusion) + view.reservedRegions(kind: .division))
            .filter(\.isActive).map(\.frame)
        // UIKit can host all five controls in a window-sized toolbar. The
        // public tab items have no accessibilityFrame in that presentation.
        // Collect visible subview bounds wholly inside the gutter, skipping
        // the page and our button. No private class or hierarchy is assumed.
        var occupied = [CGRect]()
        func collect(_ node: UIView) {
            guard node !== content.parent?.view, node !== scrollToTop, node !== tabBar,
                  !node.isHidden, node.alpha > 0.01 else { return }
            let box = node.convert(node.bounds, to: view)
            if !box.isEmpty, gutter.contains(box), box.height < gutter.height {
                occupied.append(box)
            } else {
                node.subviews.forEach(collect)
            }
        }
        view.subviews.forEach(collect)
        // Align with the visible system controls when their geometry is ready.
        // Each actual group must have been laid out before placing our control.
        // The legacy tabBar proxy can already have geometry one pass earlier.
        guard let anchor = occupied.filter({ $0.height > $0.width && $0.width >= 32 })
            .max(by: { $0.height < $1.height }) else {
            publishScrollToTop(frame: nil)
            return
        }
        let frame = Self.scrollToTopFrame(in: gutter, centerX: anchor.midX, avoiding: reserved + occupied)
        publishScrollToTop(frame: frame)
    }

    static func scrollToTopFrame(in gutter: CGRect, centerX: CGFloat, avoiding occupied: [CGRect]) -> CGRect? {
        let size: CGFloat = 48
        let top = gutter.minY + 12
        let bottom = gutter.maxY - size - 12
        guard gutter.width >= size + 4, bottom >= top else { return nil }
        for y in stride(from: top, through: bottom, by: 4) {
            let frame = CGRect(x: centerX - size / 2, y: y, width: size, height: size)
            if gutter.contains(frame), !occupied.contains(where: { $0.intersects(frame.insetBy(dx: -4, dy: -8)) }) {
                return frame
            }
        }
        return nil
    }

    private func publishScrollToTop(frame: CGRect?) {
        if let frame {
            scrollToTop.frame = frame
            if view.subviews.last !== scrollToTop { view.bringSubviewToFront(scrollToTop) }
        }
        scrollToTop.isHidden = frame == nil
        let placed = frame != nil
        if lastPlacement != placed {
            lastPlacement = placed
            channel?.invokeMethod("scrollToTopPlacement", arguments: placed)
        }
    }

    private func setChromeVisible(_ visible: Bool) {
        if !visible { publishScrollToTop(frame: nil) }
        if #available(iOS 18.0, *) {
            if isTabBarHidden == visible { setTabBarHidden(!visible, animated: false) }
        } else {
            tabBar.isHidden = !visible
        }
    }

    @available(iOS 18.0, *)
    func tabBarController(_ tabBarController: UITabBarController, shouldSelectTab tab: UITab) -> Bool {
        if tab is UISearchTab { onSearch?(); return false }
        // UIKit may omit didSelect for a reselect. Emit once at the selection decision.
        guard let index = tabs.firstIndex(of: tab), pages.indices.contains(index) else { return false }
        onSelect?(index)
        return true
    }

    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        // Modern tabs use the UITab delegate method above.
        if #available(iOS 18.0, *) { return true }
        if viewController === searchPage { onSearch?(); return false }
        guard let index = pages.firstIndex(where: { $0 === viewController }) else { return false }
        onSelect?(index)
        return true
    }
}
