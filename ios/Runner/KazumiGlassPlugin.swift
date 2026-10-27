import Flutter
import UIKit

/// Small native bridge: Flutter owns routing/content, UIKit owns glass controls.
final class KazumiGlassPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private let registrar: FlutterPluginRegistrar
    private var probe: KazumiSceneProbe?

    private init(registrar: FlutterPluginRegistrar) { self.registrar = registrar }

    static func register(with registrar: FlutterPluginRegistrar) {
        let plugin = KazumiGlassPlugin(registrar: registrar)
        registrar.register(KazumiGlassFactory(messenger: registrar.messenger()),
                           withId: "com.predidit.kazumi/glass")
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

private final class KazumiGlassFactory: NSObject, FlutterPlatformViewFactory {
    let messenger: FlutterBinaryMessenger
    init(messenger: FlutterBinaryMessenger) { self.messenger = messenger }
    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol { FlutterStandardMessageCodec.sharedInstance() }
    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        KazumiGlassView(frame: frame, id: viewId,
                        configuration: args as? [String: Any] ?? [:], messenger: messenger)
    }
}

private final class KazumiGlassView: NSObject, FlutterPlatformView {
    private let content: UIView
    private let channel: FlutterMethodChannel
    init(frame: CGRect, id: Int64, configuration: [String: Any], messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(name: "com.predidit.kazumi/glass/\(id)", binaryMessenger: messenger)
        if configuration["kind"] as? String == "navigation" {
            content = KazumiNavigationView(frame: frame)
        } else {
            let material = KazumiMaterialView(frame: frame)
            material.layer.cornerRadius = configuration["radius"] as? CGFloat ?? 0
            material.clipsToBounds = true
            content = material
        }
        super.init()
        apply(configuration)
        if let navigation = content as? KazumiNavigationView {
            navigation.onSelect = { [weak self] index in self?.channel.invokeMethod("select", arguments: index) }
            navigation.onSearch = { [weak self] in self?.channel.invokeMethod("search", arguments: nil) }
        }
        channel.setMethodCallHandler { [weak self] call, result in
            if call.method == "hide" {
                (self?.content as? KazumiNavigationView)?.cancelScrub()
                self?.content.isHidden = true
                self?.content.isUserInteractionEnabled = false
                self?.content.accessibilityElementsHidden = true
                result(nil)
                return
            }
            guard call.method == "update", let config = call.arguments as? [String: Any] else {
                result(FlutterMethodNotImplemented); return
            }
            self?.apply(config)
            result(nil)
        }
    }
    deinit { channel.setMethodCallHandler(nil) }
    func view() -> UIView { content }
    private func apply(_ configuration: [String: Any]) {
        content.overrideUserInterfaceStyle = configuration["dark"] as? Bool == true ? .dark : .light
        (content as? KazumiNavigationView)?.configure(configuration)
    }
}

private final class KazumiMaterialView: UIVisualEffectView {
    private var materialEffect: UIVisualEffect?

    init(frame: CGRect, interactive: Bool = false, clear: Bool = false) {
        // The OS owns optical rendering, the iOS 27 transparency slider and
        // accessibility fallbacks. Do not emulate glass with a blur shader.
        if #available(iOS 26.0, *) {
            let glass = UIGlassEffect(style: clear ? .clear : .regular)
            glass.isInteractive = interactive
            super.init(effect: glass)
        } else {
            super.init(effect: UIBlurEffect(style: .systemMaterial))
        }
        self.frame = frame
        materialEffect = effect
        layer.cornerCurve = .continuous
    }
    func showMaterial(_ visible: Bool) { effect = visible ? materialEffect : nil }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

final class KazumiNavigationView: UIView, UIGestureRecognizerDelegate {
    private let material = KazumiMaterialView(frame: .zero, interactive: true)
    private let searchMaterial = KazumiMaterialView(frame: .zero, interactive: true)
    private let selection = UIView()
    // Glass samples the backdrop only. Icons and labels stay above the lens so
    // dragging never blurs the controls the user is trying to select.
    private let lens = KazumiMaterialView(frame: .zero, interactive: true, clear: true)
    private let tabContent = UIView()
    private let feedback = UISelectionFeedbackGenerator()
    private lazy var scrub = UIPanGestureRecognizer(target: self, action: #selector(scrubTabs(_:)))
    private var dragging = false
    private var preview: Int?
    private var dragPoint = CGPoint.zero
    private var dragSpeed: CGFloat = 0
    private var lastSize = CGSize.zero
    private var scrubRevision = 0
    private var pendingReset: DispatchWorkItem?
    private let search = UIButton(type: .system)
    private var buttons: [KazumiTabControl] = []
    private var vertical = false
    private var selected = 0
    var onSelect: ((Int) -> Void)?
    var onSearch: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        addSubview(material)
        addSubview(searchMaterial)
        selection.backgroundColor = UIColor.secondaryLabel.withAlphaComponent(0.12)
        selection.layer.cornerCurve = .continuous
        material.contentView.addSubview(selection)
        let labels = ["推荐", "时间表", "追番", "我的"]
        let symbols = ["play.rectangle", "calendar", "heart", "person.crop.circle"]
        for index in labels.indices {
            let button = KazumiTabControl(title: labels[index], symbol: symbols[index])
            button.tag = index
            button.addTarget(self, action: #selector(selectTab(_:)), for: .touchUpInside)
            buttons.append(button)
            tabContent.addSubview(button)
        }
        search.setImage(UIImage(systemName: "magnifyingglass", withConfiguration:
            UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)), for: .normal)
        search.accessibilityLabel = "搜索番剧"
        search.addTarget(self, action: #selector(searchTapped), for: .touchUpInside)
        searchMaterial.contentView.addSubview(search)
        lens.isUserInteractionEnabled = false
        lens.accessibilityIdentifier = "Kazumi.tabScrubLens"
        lens.accessibilityElementsHidden = true
        lens.clipsToBounds = true
        lens.isHidden = true
        addSubview(lens)
        tabContent.accessibilityIdentifier = "Kazumi.tabContent"
        addSubview(tabContent)
        scrub.delegate = self
        scrub.maximumNumberOfTouches = 1
        scrub.cancelsTouchesInView = true
        tabContent.addGestureRecognizer(scrub)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(_ config: [String: Any]) {
        let previousSelection = selected
        layoutIfNeeded()
        let nextVertical = config["vertical"] as? Bool ?? false
        if nextVertical != vertical { cancelScrub() }
        vertical = nextVertical
        selected = min(3, max(0, config["selectedIndex"] as? Int ?? 0))
        if !dragging {
            pendingReset?.cancel()
            preview = nil
        } else if selected != previousSelection {
            cancelScrub()
        }
        if let argb = config["tint"] as? NSNumber {
            let value = argb.uint32Value
            tintColor = UIColor(red: CGFloat((value >> 16) & 255) / 255,
                                green: CGFloat((value >> 8) & 255) / 255,
                                blue: CGFloat(value & 255) / 255, alpha: 1)
        }
        updateSelection()
        setNeedsLayout()
        if previousSelection != selected && !UIAccessibility.isReduceMotionEnabled {
            UIView.animate(withDuration: 0.28, delay: 0, usingSpringWithDamping: 0.9,
                           initialSpringVelocity: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.layoutIfNeeded()
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if lastSize != bounds.size {
            lastSize = bounds.size
            cancelScrub()
        }
        let gap: CGFloat = 10
        let searchExtent: CGFloat = min(56, vertical ? bounds.width : bounds.height)
        if vertical {
            material.frame = CGRect(x: 0, y: 0, width: bounds.width,
                                    height: max(0, bounds.height - searchExtent - gap))
            searchMaterial.frame = CGRect(x: (bounds.width - searchExtent) / 2,
                y: bounds.height - searchExtent, width: searchExtent, height: searchExtent)
        } else {
            material.frame = CGRect(x: 0, y: 0, width: max(0, bounds.width - searchExtent - gap), height: bounds.height)
            searchMaterial.frame = CGRect(x: bounds.width - searchExtent,
                y: (bounds.height - searchExtent) / 2, width: searchExtent, height: searchExtent)
        }
        material.layer.cornerRadius = min(material.bounds.width, material.bounds.height) / 2
        searchMaterial.layer.cornerRadius = searchExtent / 2
        material.clipsToBounds = true
        searchMaterial.clipsToBounds = true
        tabContent.frame = material.frame
        search.frame = searchMaterial.bounds
        for (index, button) in buttons.enumerated() {
            let tile = tabFrame(at: index)
            // Bounds and center remain stable while the preview is magnified.
            button.bounds.size = tile.size
            button.center = CGPoint(x: tile.midX, y: tile.midY)
        }
        selection.frame = tabFrame(at: preview ?? selected)
        selection.layer.cornerRadius = min(selection.bounds.width, selection.bounds.height) / 2
        if dragging { positionLens() }
    }

    private func tabFrame(at index: Int) -> CGRect {
        let inner = material.bounds.insetBy(dx: 5, dy: 5)
        return vertical
            ? CGRect(x: inner.minX, y: inner.minY + CGFloat(index) * inner.height / 4,
                     width: inner.width, height: inner.height / 4)
            : CGRect(x: inner.minX + CGFloat(index) * inner.width / 4, y: inner.minY,
                     width: inner.width / 4, height: inner.height)
    }

    private func updateSelection() {
        for (index, button) in buttons.enumerated() {
            button.isSelected = index == selected
            button.tintColor = index == (preview ?? selected) ? tintColor : .secondaryLabel
            button.transform = dragging && index == preview && !UIAccessibility.isReduceMotionEnabled
                ? CGAffineTransform(scaleX: 1.08, y: 1.08) : .identity
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { cancelScrub() }
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === scrub, !UIAccessibility.isVoiceOverRunning else { return false }
        let movement = scrub.translation(in: material)
        return vertical ? abs(movement.y) > abs(movement.x) : abs(movement.x) > abs(movement.y)
    }

    @objc private func scrubTabs(_ gesture: UIPanGestureRecognizer) {
        handleScrub(state: gesture.state, at: gesture.location(in: material),
                    velocity: gesture.velocity(in: material))
    }

    // Kept separate from UIKit's recognizer so cancellation, layout changes and
    // route confirmation can also be exercised by native regression tests.
    func handleScrub(state: UIGestureRecognizer.State, at point: CGPoint, velocity: CGPoint = .zero) {
        switch state {
        case .began:
            pendingReset?.cancel()
            scrubRevision += 1
            lens.layer.removeAllAnimations()
            selection.layer.removeAllAnimations()
            dragging = true
            selection.alpha = 0
            lens.isHidden = false
            lens.showMaterial(true)
            feedback.prepare()
            moveScrub(to: point, velocity: velocity)
        case .changed:
            moveScrub(to: point, velocity: velocity)
        case .ended:
            finishScrub(commit: material.bounds.contains(point) ? preview : nil)
        case .cancelled, .failed:
            finishScrub(commit: nil)
        default: break
        }
    }

    private func moveScrub(to point: CGPoint, velocity: CGPoint) {
        guard dragging else { return }
        dragPoint = point
        dragSpeed = vertical ? abs(velocity.y) : abs(velocity.x)
        let nearest = buttons.indices.min {
            let a = buttons[$0].center, b = buttons[$1].center
            return vertical ? abs(a.y - point.y) < abs(b.y - point.y)
                            : abs(a.x - point.x) < abs(b.x - point.x)
        } ?? selected
        if preview != nearest {
            preview = nearest
            feedback.selectionChanged()
            feedback.prepare()
        }
        updateSelection()
        positionLens()
    }

    private func positionLens() {
        let tile = selection.bounds.size
        let stretch = UIAccessibility.isReduceMotionEnabled ? 0 : min(12, dragSpeed / 160)
        let width = min(material.bounds.width - 2, tile.width + (vertical ? 6 : 8 + stretch))
        let height = min(material.bounds.height - 2, tile.height + (vertical ? 8 + stretch : 6))
        guard width > 0, height > 0 else { return }
        let center = CGPoint(
            x: vertical ? material.bounds.midX : min(material.bounds.width - width / 2, max(width / 2, dragPoint.x)),
            y: vertical ? min(material.bounds.height - height / 2, max(height / 2, dragPoint.y)) : material.bounds.midY)
        lens.frame = material.convert(CGRect(x: center.x - width / 2, y: center.y - height / 2,
                                             width: width, height: height), to: self)
        lens.layer.cornerRadius = min(width, height) / 2
    }

    private func finishScrub(commit target: Int?) {
        guard dragging else { return }
        dragging = false
        preview = target
        let revision = scrubRevision
        let destination = material.convert(tabFrame(at: target ?? selected), to: self)
        updateSelection()
        setNeedsLayout()
        let settle = {
            self.layoutIfNeeded()
            self.selection.alpha = 1
            self.lens.frame = destination
            self.lens.layer.cornerRadius = min(destination.width, destination.height) / 2
            self.lens.showMaterial(false)
        }
        if UIAccessibility.isReduceMotionEnabled {
            settle()
            lens.isHidden = true
        } else {
            UIView.animate(withDuration: 0.32, delay: 0, usingSpringWithDamping: 0.78,
                           initialSpringVelocity: 0, options: [.beginFromCurrentState, .allowUserInteraction],
                           animations: settle) { [weak self] _ in
                guard let self, self.scrubRevision == revision else { return }
                self.lens.isHidden = true
            }
        }
        if let target, target != selected {
            // Flutter remains the routing authority. Roll back if the route
            // cannot confirm selection, rather than leaving a false highlight.
            let reset = DispatchWorkItem { [weak self] in
                guard let self, self.scrubRevision == revision, !self.dragging else { return }
                self.preview = nil
                self.updateSelection()
                self.setNeedsLayout()
            }
            pendingReset = reset
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: reset)
            onSelect?(target)
        } else {
            preview = nil
        }
    }

    func cancelScrub() {
        pendingReset?.cancel()
        pendingReset = nil
        scrubRevision += 1
        dragging = false
        preview = nil
        lens.layer.removeAllAnimations()
        selection.layer.removeAllAnimations()
        lens.isHidden = true
        lens.showMaterial(false)
        selection.alpha = 1
        updateSelection()
        setNeedsLayout()
    }
    @objc private func selectTab(_ sender: KazumiTabControl) {
        onSelect?(sender.tag) // Flutter confirms selection after routing succeeds.
    }
    @objc private func searchTapped() { onSearch?() }
}

private final class KazumiTabControl: UIControl {
    private let image = UIImageView()
    private let label = UILabel()
    private let symbol: String
    init(title: String, symbol: String) {
        self.symbol = symbol
        super.init(frame: .zero)
        isAccessibilityElement = true
        accessibilityLabel = title
        label.text = title
        label.textAlignment = .center
        label.font = UIFontMetrics(forTextStyle: .caption2).scaledFont(for: .systemFont(ofSize: 10, weight: .semibold))
        label.adjustsFontForContentSizeCategory = true
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.85
        image.contentMode = .scaleAspectFit
        addSubview(image)
        addSubview(label)
        updateAppearance()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var isSelected: Bool { didSet { updateAppearance() } }
    override var isHighlighted: Bool { didSet { alpha = isHighlighted ? 0.55 : 1 } }
    override func tintColorDidChange() { super.tintColorDidChange(); label.textColor = tintColor }
    private func updateAppearance() {
        let filled = ["play.rectangle": "play.rectangle.fill", "heart": "heart.fill",
                      "person.crop.circle": "person.crop.circle.fill"]
        let name = isSelected ? (filled[symbol] ?? symbol) : symbol
        image.image = UIImage(systemName: name, withConfiguration:
            UIImage.SymbolConfiguration(pointSize: 22, weight: .medium))
        accessibilityTraits = isSelected ? [.button, .selected] : [.button]
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        let textHeight = min(22, label.font.lineHeight)
        let total: CGFloat = 24 + 3 + textHeight
        let top = (bounds.height - total) / 2
        image.frame = CGRect(x: 0, y: top, width: bounds.width, height: 24)
        label.frame = CGRect(x: 1, y: top + 27, width: bounds.width - 2, height: textHeight)
    }
}
