import UIKit
import XCTest
@testable import Runner

@MainActor
class RunnerTests: XCTestCase {
    func testScrollCompactPreservesTabActionsAndResetsOnHide() throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Native animated title updates require iOS 27") }
        let content = UIViewController()
        let host = KazumiTabBarController(content: content)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        host.update(["selectedIndex": 0, "visible": true])
        window.layoutIfNeeded()
        let items = host.tabs
        let titles = items.map(\.title)
        host.update(["selectedIndex": 0, "visible": true, "compact": true])
        if #available(iOS 27.1, *), host.traitCollection.verticalBarEdge != .unspecified {
            XCTAssertEqual(items.map(\.title), titles)
            XCTAssertTrue(host.tabBar.transform.isIdentity)
            return
        }
        guard host.traitCollection.userInterfaceIdiom == .phone,
              host.traitCollection.horizontalSizeClass == .compact,
              window.bounds.height > window.bounds.width else {
            XCTAssertEqual(items.map(\.title), titles)
            return
        }
        XCTAssertEqual(items.map(\.title), Array(repeating: "", count: 5))
        XCTAssertEqual(items.compactMap(\.accessibilityLabel), titles)
        XCTAssertEqual(host.tabBar.transform.a, 0.88, accuracy: 0.001)
        var selection: Int?
        var searched = false
        host.onSelect = { selection = $0 }
        host.onSearch = { searched = true }
        XCTAssertTrue(host.tabBarController(host, shouldSelectTab: items[2]))
        XCTAssertEqual(selection, 2)
        XCTAssertFalse(host.tabBarController(host, shouldSelectTab: items[4]))
        XCTAssertTrue(searched)
        // Reverse while the animation is still running, then hide the route.
        host.update(["selectedIndex": 0, "visible": true, "compact": false])
        host.update(["selectedIndex": 0, "visible": true, "compact": true])
        host.update(["selectedIndex": 0, "visible": false])
        XCTAssertEqual(items.map(\.title), titles)
        XCTAssertTrue(host.tabBar.transform.isIdentity)
        XCTAssertTrue(host.isTabBarHidden)
        XCTAssertIdentical(content.parent, host.selectedTab?.viewController)
    }

    func testScrollButtonFitsGutterAndAvoidsSystemControls() throws {
        let gutter = CGRect(x: 0, y: 0, width: 96, height: 466)
        let camera = CGRect(x: 0, y: 0, width: 96, height: 60)
        let controls = CGRect(x: 20, y: 170, width: 56, height: 276)
        let frame = try XCTUnwrap(KazumiTabBarController.scrollToTopFrame(in: gutter, centerX: 48, avoiding: [camera, controls]))
        XCTAssertTrue(gutter.contains(frame))
        XCTAssertFalse(frame.intersects(camera))
        XCTAssertFalse(frame.intersects(controls))
        XCTAssertNil(KazumiTabBarController.scrollToTopFrame(in: gutter, centerX: 48, avoiding: [gutter]))
        XCTAssertNil(KazumiTabBarController.scrollToTopFrame(in: .zero, centerX: 0, avoiding: []))
    }

    func testVisibleRailButtonClearsReservedRegionsAndAlignsWithTabs() throws {
        guard #available(iOS 27.1, *) else { throw XCTSkip("Vertical tabs require iOS 27.1") }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let controller = KazumiTabBarController(content: UIViewController())
        let window = UIWindow(windowScene: scene)
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        controller.update(["selectedIndex": 0, "visible": true, "scrollToTop": true])
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))
        guard controller.traitCollection.verticalBarEdge != .unspecified else {
            throw XCTSkip("The current scene uses a horizontal tab bar")
        }
        let button = try XCTUnwrap(controller.view.subviews.first { $0.accessibilityLabel == "返回顶部" })
        let reserved = controller.view.reservedRegions(kind: .occlusion).filter(\.isActive)
        let body = controller.contentLayoutGuide.layoutFrame
        // A short rail may legitimately require a page button. In the tall
        // rail configuration there is room for a full touch target.
        guard window.bounds.height >= 650 else { throw XCTSkip("Short rail") }
        XCTAssertFalse(button.isHidden)
        XCTAssertFalse(button.frame.intersects(body))
        XCTAssertFalse(reserved.contains { $0.frame.intersects(button.frame) })
        if let camera = reserved.min(by: { $0.frame.width < $1.frame.width }) {
            XCTAssertEqual(button.frame.midX, camera.frame.midX, accuracy: 2)
        }
        XCTAssertLessThan(button.frame.maxY, window.bounds.midY)
    }

    func testSystemItemsHaveLabelsAndSymbols() throws {
        guard #available(iOS 18.0, *) else { throw XCTSkip("UITab requires iOS 18") }
        let controller = KazumiTabBarController(content: UIViewController())
        XCTAssertEqual(controller.tabs.prefix(4).map(\.title), ["推荐", "时间表", "追番", "我的"])
        XCTAssertTrue(controller.tabs.prefix(4).allSatisfy { $0.image != nil })
        XCTAssertTrue(controller.tabs.last is UISearchTab)
    }

    func testSearchAndReselectKeepCurrentRoute() throws {
        guard #available(iOS 18.0, *) else { throw XCTSkip("UITab requires iOS 18") }
        let controller = KazumiTabBarController(content: UIViewController())
        var selections: [Int] = []
        var searches = 0
        controller.onSelect = { selections.append($0) }
        controller.onSearch = { searches += 1 }
        controller.update(["selectedIndex": 0])
        XCTAssertTrue(controller.tabBarController(controller, shouldSelectTab: controller.tabs[0]))
        XCTAssertFalse(controller.tabBarController(controller, shouldSelectTab: controller.tabs[4]))
        XCTAssertEqual(selections, [0])
        XCTAssertEqual(searches, 1)
        XCTAssertIdentical(controller.selectedTab, controller.tabs[0])
    }

    func testProgrammaticSwitchMovesSameContentWithoutEchoOrDisappearance() throws {
        guard #available(iOS 18.0, *) else { throw XCTSkip("UITab requires iOS 18") }
        let content = AppearanceRecorder()
        let controller = KazumiTabBarController(content: content)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        controller.onSelect = { _ in XCTFail("A Dart synchronization must not echo a selection") }
        for index in [0, 3, 1, 2] {
            controller.update(["selectedIndex": index, "visible": true])
            window.layoutIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.35))
            XCTAssertIdentical(content.parent, controller.selectedTab?.viewController)
            XCTAssertIdentical(content.view.window, window)
        }
        XCTAssertEqual(content.disappearances, 0)
    }

    func testRouteVisibilityDoesNotLoseSelectedTab() throws {
        guard #available(iOS 18.0, *) else { throw XCTSkip("UITab requires iOS 18") }
        let controller = KazumiTabBarController(content: UIViewController())
        XCTAssertTrue(controller.isTabBarHidden)
        controller.update(["selectedIndex": 2, "visible": true])
        XCTAssertFalse(controller.isTabBarHidden)
        controller.update(["selectedIndex": 2, "visible": false])
        XCTAssertTrue(controller.isTabBarHidden)
        XCTAssertIdentical(controller.selectedTab, controller.tabs[2])
    }
}

private final class AppearanceRecorder: UIViewController {
    var disappearances = 0
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        disappearances += 1
    }
}
