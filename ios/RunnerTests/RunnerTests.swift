import UIKit
import XCTest
@testable import Runner

@MainActor
class RunnerTests: XCTestCase {
    func testScrollButtonFitsGutterAndAvoidsSystemControls() throws {
        let gutter = CGRect(x: 0, y: 0, width: 96, height: 466)
        let camera = CGRect(x: 0, y: 0, width: 96, height: 60)
        let controls = CGRect(x: 20, y: 170, width: 56, height: 276)
        let frame = try XCTUnwrap(KazumiTabBarController.scrollToTopFrame(in: gutter, avoiding: [camera]) {
            !controls.contains($0)
        })
        XCTAssertTrue(gutter.contains(frame))
        XCTAssertFalse(frame.intersects(camera))
        XCTAssertFalse(frame.intersects(controls))
        XCTAssertNil(KazumiTabBarController.scrollToTopFrame(in: gutter, avoiding: [gutter]) { _ in true })
        XCTAssertNil(KazumiTabBarController.scrollToTopFrame(in: .zero, avoiding: []) { _ in true })
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
