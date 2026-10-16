//
//  ChatViewControllerTests.swift
//  The UIKit chat (#96): from iOS 15 ChatViewController hosts the SwiftUI
//  ChatView (help centre, home, wait cards, markdown, delight: #56, #81,
//  #84) and keeps its UIKit API: init(), init(enableKnowledgeBase:),
//  ConferBot.present(from:), the navigation bar put back as it was, ✕
//  dismissing or popping. The UIKit-drawn chat (iOS 13 / 14) still loads.
//

import XCTest
import SwiftUI
@testable import Conferbot

final class ChatViewControllerTests: XCTestCase {

    @available(iOS 15.0, *)
    func testHostsTheSwiftUIChatFromIOS15() throws {
        try XCTSkipUnless(ChatViewController.hostsSwiftUI)
        let vc = ChatViewController()
        vc.loadViewIfNeeded()
        let host = try XCTUnwrap(vc.content as? UIHostingController<ChatView>)
        XCTAssertTrue(vc.children.contains(host))
        XCTAssertTrue(host.view.isDescendant(of: vc.view))
        XCTAssertNil(host.rootView.enableKnowledgeBase)
        XCTAssertNotNil(host.rootView.onClose, "the hosted chat draws the ✕")
    }

    @available(iOS 15.0, *)
    func testTheHelpCentreOverrideReachesTheChat() throws {
        try XCTSkipUnless(ChatViewController.hostsSwiftUI)
        let vc = ChatViewController(enableKnowledgeBase: false)
        vc.loadViewIfNeeded()
        let host = try XCTUnwrap(vc.content as? UIHostingController<ChatView>)
        XCTAssertEqual(host.rootView.enableKnowledgeBase, false)
        XCTAssertEqual(vc.enableKnowledgeBase, false)
    }

    func testTheOldInitialisersStillWork() {
        XCTAssertNil(ChatViewController().enableKnowledgeBase)
        XCTAssertNil(ChatViewController(nibName: nil, bundle: nil).enableKnowledgeBase)
    }

    func testTheNavigationBarIsHiddenWhileOnScreenAndPutBackAfter() throws {
        try XCTSkipUnless(ChatViewController.hostsSwiftUI)
        let root = UIViewController()
        let nav = UINavigationController(rootViewController: root)
        let vc = ChatViewController()
        nav.pushViewController(vc, animated: false)
        vc.loadViewIfNeeded()
        XCTAssertFalse(nav.isNavigationBarHidden)

        vc.beginAppearanceTransition(true, animated: false)
        vc.endAppearanceTransition()
        XCTAssertTrue(nav.isNavigationBarHidden)

        vc.beginAppearanceTransition(false, animated: false)
        vc.endAppearanceTransition()
        XCTAssertFalse(nav.isNavigationBarHidden, "the app's bar is back")

        // An app that hides its bar keeps it hidden.
        nav.setNavigationBarHidden(true, animated: false)
        vc.beginAppearanceTransition(true, animated: false)
        vc.endAppearanceTransition()
        vc.beginAppearanceTransition(false, animated: false)
        vc.endAppearanceTransition()
        XCTAssertTrue(nav.isNavigationBarHidden)
    }

    func testCloseGoesBackWhenPushed() {
        let root = UIViewController()
        let nav = UINavigationController(rootViewController: root)
        let vc = ChatViewController()
        nav.pushViewController(vc, animated: false)
        XCTAssertEqual(nav.viewControllers.count, 2)
        vc.close(animated: false)
        XCTAssertEqual(nav.viewControllers.count, 1)
        XCTAssertTrue(nav.topViewController === root)
    }

    func testCloseAsTheRootOfItsOwnNavigationControllerDismisses() {
        // As ConferBot.present(from:) wraps it: nothing to pop, so it
        // dismisses (no presenter here: nothing happens, no crash).
        let vc = ChatViewController()
        let nav = UINavigationController(rootViewController: vc)
        vc.close(animated: false)
        XCTAssertEqual(nav.viewControllers.count, 1)
    }

    func testTheStatusBarReadsOnTheHeader() {
        XCTAssertEqual(ChatViewController.statusBarStyle(onHeader: "#0808EE"), .lightContent)
        XCTAssertEqual(ChatViewController.statusBarStyle(onHeader: "#111111"), .lightContent)
        XCTAssertEqual(ChatViewController.statusBarStyle(onHeader: "#FFFFFF"), .darkContent)
        XCTAssertEqual(ChatViewController.statusBarStyle(onHeader: "#F5F5F5"), .darkContent)
    }

    func testTheUIKitDrawnChatStillLoadsAndFillsItsParentsBar() {
        // iOS 13 / 14's chat, loaded here directly.
        let parent = UIViewController()
        var closed = false
        let legacy = UIKitChatViewController(onClose: { closed = true })
        parent.addChild(legacy)
        parent.view.addSubview(legacy.view)
        legacy.didMove(toParent: parent)
        legacy.loadViewIfNeeded()
        XCTAssertEqual(parent.navigationItem.title, ConferBot.shared.chatHeaderTitle)
        let close = parent.navigationItem.leftBarButtonItem
        XCTAssertNotNil(close)
        if let close = close, let action = close.action {
            _ = (close.target as? NSObject)?.perform(action, with: close)
        }
        XCTAssertTrue(closed)
    }
}
