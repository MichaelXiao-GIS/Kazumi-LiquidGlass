import Flutter
import UIKit
import XCTest
@testable import Runner

@MainActor
class RunnerTests: XCTestCase {
  private func navigation() -> KazumiNavigationView {
    let view = KazumiNavigationView(frame: CGRect(x: 0, y: 0, width: 390, height: 64))
    view.configure(["selectedIndex": 0, "vertical": false])
    view.layoutIfNeeded()
    return view
  }

  func testScrubPreviewsThenCommitsExactlyOneDestination() {
    let view = navigation()
    var selections: [Int] = []
    view.onSelect = { selections.append($0) }
    let lens = view.subviews.first { $0.accessibilityIdentifier == "Kazumi.tabScrubLens" }!
    let foreground = view.subviews.first { $0.accessibilityIdentifier == "Kazumi.tabContent" }!
    XCTAssertGreaterThan(view.subviews.firstIndex(of: foreground)!, view.subviews.firstIndex(of: lens)!,
                         "Icons and labels must be above the glass to stay sharp")
    XCTAssertEqual(foreground.subviews.compactMap { $0 as? UIControl }.count, 4)
    view.handleScrub(state: .began, at: CGPoint(x: 44, y: 32))
    let originalCenter = lens.center.x
    view.handleScrub(state: .changed, at: CGPoint(x: 210, y: 32), velocity: CGPoint(x: 800, y: 0))
    XCTAssertFalse(lens.isHidden)
    XCTAssertGreaterThan(lens.center.x, originalCenter)
    XCTAssertTrue(selections.isEmpty, "Previewing must not load intermediate pages")
    view.handleScrub(state: .ended, at: CGPoint(x: 210, y: 32))
    XCTAssertEqual(selections, [2])
    view.configure(["selectedIndex": 2, "vertical": false])
    view.handleScrub(state: .ended, at: CGPoint(x: 210, y: 32))
    XCTAssertEqual(selections, [2], "Ending a completed gesture cannot select twice")
    view.cancelScrub()
  }

  func testCancelledOrOutsideReleaseDoesNotSelect() {
    let view = navigation()
    var selections: [Int] = []
    view.onSelect = { selections.append($0) }
    for endState in [UIGestureRecognizer.State.cancelled, .ended] {
      view.handleScrub(state: .began, at: CGPoint(x: 44, y: 32))
      view.handleScrub(state: .changed, at: CGPoint(x: 210, y: 32))
      view.handleScrub(state: endState, at: CGPoint(x: 210, y: -80))
    }
    XCTAssertTrue(selections.isEmpty)
    view.cancelScrub()
  }

  func testRotationAndRouteHidingCancelAnActiveScrub() {
    let view = navigation()
    var selections: [Int] = []
    view.onSelect = { selections.append($0) }
    view.handleScrub(state: .began, at: CGPoint(x: 44, y: 32))
    view.handleScrub(state: .changed, at: CGPoint(x: 210, y: 32))
    view.configure(["selectedIndex": 0, "vertical": true])
    view.frame.size = CGSize(width: 64, height: 320)
    view.layoutIfNeeded()
    view.handleScrub(state: .ended, at: CGPoint(x: 32, y: 210))
    XCTAssertTrue(selections.isEmpty)
    view.handleScrub(state: .began, at: CGPoint(x: 32, y: 34))
    view.handleScrub(state: .changed, at: CGPoint(x: 32, y: 150))
    view.cancelScrub() // Same path used by the platform-channel hide command.
    view.handleScrub(state: .ended, at: CGPoint(x: 32, y: 150))
    XCTAssertTrue(selections.isEmpty)
    XCTAssertTrue(view.subviews.first { $0.accessibilityIdentifier == "Kazumi.tabScrubLens" }!.isHidden)
  }

  func testVerticalScrubAndIndependentSearch() {
    let view = navigation()
    view.configure(["selectedIndex": 0, "vertical": true])
    view.frame.size = CGSize(width: 64, height: 320)
    view.layoutIfNeeded()
    var selections: [Int] = []
    var searches = 0
    view.onSelect = { selections.append($0) }
    view.onSearch = { searches += 1 }
    view.handleScrub(state: .began, at: CGPoint(x: 32, y: 34))
    view.handleScrub(state: .changed, at: CGPoint(x: 32, y: 220))
    view.handleScrub(state: .ended, at: CGPoint(x: 32, y: 220))
    XCTAssertEqual(selections, [3])
    XCTAssertEqual(searches, 0)
    func controls(_ root: UIView) -> [UIControl] {
      (root as? UIControl).map { [$0] } ?? root.subviews.flatMap(controls)
    }
    controls(view).first { $0.accessibilityLabel == "搜索番剧" }!.sendActions(for: .touchUpInside)
    XCTAssertEqual(searches, 1)
    XCTAssertEqual(selections, [3])
    view.cancelScrub()
  }
}
