//
//  ChatViewController.swift
//  Conferbot
//
//  Created by Conferbot SDK
//
//  The UIKit chat. From iOS 15 it hosts the SwiftUI ChatView (a
//  UIHostingController child filling the screen, #96), so UIKit apps get
//  every feature of one implementation: the owner's home screen, the help
//  centre, "Your requests", the step cards, the wait cards and games, the
//  markdown bubbles, the human touches, the owner's font, the typing styles,
//  the live chat cards and the chat menu. ChatView draws the header (the
//  bot's colours, logo, title, status line, menu and ✕), so the navigation
//  bar is hidden while the chat is on screen and put back as it was when it
//  goes. On iOS 13 / 14 the UIKit-drawn chat (UIKitChatViewController) is
//  used, in the navigation bar as before.
//

import UIKit
import SwiftUI
import Combine

/// Main chat view controller for UIKit
public class ChatViewController: UIViewController {

    /// The host app's override for the help centre, as `ChatView`'s:
    /// `nil` (the default) and `true` follow the owner's setting, `false`
    /// hides it. iOS 15+ (the UIKit-drawn chat on iOS 13 / 14 has none).
    public let enableKnowledgeBase: Bool?

    /// The chat on screen: the hosted SwiftUI ChatView (iOS 15+) or the UIKit-drawn one.
    private(set) var content: UIViewController?
    private var cancellables = Set<AnyCancellable>()
    /// The navigation bar's hidden state before the chat hid it.
    private var barWasHidden: Bool?
    private var statusBarStyle: UIStatusBarStyle = .default

    public init(enableKnowledgeBase: Bool? = nil) {
        self.enableKnowledgeBase = enableKnowledgeBase
        super.init(nibName: nil, bundle: nil)
    }

    public override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        self.enableKnowledgeBase = nil
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }

    public required init?(coder: NSCoder) {
        self.enableKnowledgeBase = nil
        super.init(coder: coder)
    }

    /// Whether this screen hosts the SwiftUI chat (iOS 15+).
    static var hostsSwiftUI: Bool {
        if #available(iOS 15.0, *) { return true }
        return false
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = ConferBot.shared.chatHeaderTitle

        let child: UIViewController
        if #available(iOS 15.0, *) {
            child = makeHostedChat()
        } else {
            child = UIKitChatViewController(onClose: { [weak self] in self?.close() })
        }
        addChild(child)
        child.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(child.view)
        NSLayoutConstraint.activate([
            child.view.topAnchor.constraint(equalTo: view.topAnchor),
            child.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            child.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            child.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        child.didMove(toParent: self)
        content = child
    }

    @available(iOS 15.0, *)
    private func makeHostedChat() -> UIViewController {
        let host = UIHostingController(rootView: ChatView(enableKnowledgeBase: enableKnowledgeBase,
                                                          onClose: { [weak self] in self?.close() }))
        // The bot's surface behind the chat (under the home indicator too),
        // the status bar readable on the header's colour, the title kept for
        // the navigation stack (a back button's text, accessibility).
        ConferBot.shared.$customizations
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak host] look in
                guard let self = self else { return }
                let server = ConferBot.shared.hasServerLook
                host?.view.backgroundColor = server ? look.surface.map { UIColor(cbHex: $0) } ?? .systemBackground : .systemBackground
                self.title = ConferBot.shared.chatHeaderTitle
                self.updateStatusBar()
            }
            .store(in: &cancellables)
        // The help centre is drawn on the system background: the status bar follows the view.
        ConferBot.shared.home.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.updateStatusBar() } }
            .store(in: &cancellables)
        return host
    }

    /// The status bar over what is under it: the chat header's colour, the
    /// home screen's page, the help centre's system background.
    private func updateStatusBar() {
        let bot = ConferBot.shared
        let view = bot.home.isOn ? bot.home.view : .chat
        switch (bot.hasServerLook, view) {
        case (false, _), (_, .help):
            statusBarStyle = .default
        case (true, .home):
            statusBarStyle = Self.statusBarStyle(onHeader: Home.palette(bot.customizations.theme.tokens).page)
        case (true, _):
            statusBarStyle = Self.statusBarStyle(onHeader: bot.customizations.headerBg)
        }
        setNeedsStatusBarAppearanceUpdate()
    }

    /// Light status bar text on a dark header, dark on a light one.
    static func statusBarStyle(onHeader hex: String) -> UIStatusBarStyle {
        var white: CGFloat = 0
        var alpha: CGFloat = 0
        let color = UIColor(cbHex: hex)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        if color.getRed(&r, green: &g, blue: &b, alpha: &alpha) {
            white = 0.2126 * r + 0.7152 * g + 0.0722 * b
        } else {
            _ = color.getWhite(&white, alpha: &alpha)
        }
        return white < 0.6 ? .lightContent : .darkContent
    }

    public override var preferredStatusBarStyle: UIStatusBarStyle { statusBarStyle }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // The SwiftUI chat draws its own header: no navigation bar over it.
        guard Self.hostsSwiftUI, let nav = navigationController else { return }
        if barWasHidden == nil { barWasHidden = nav.isNavigationBarHidden }
        nav.setNavigationBarHidden(true, animated: animated)
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Put the app's bar back as it was (a pushed chat going back, or a
        // screen pushed over the chat).
        guard Self.hostsSwiftUI, let nav = navigationController, let was = barWasHidden else { return }
        barWasHidden = nil
        nav.setNavigationBarHidden(was, animated: animated)
    }

    /// ✕: back when pushed on the app's navigation stack, else dismissed
    /// (`ConferBot.shared.present(from:)` presents it in its own navigation
    /// controller).
    func close(animated: Bool = true) {
        if let nav = navigationController, nav.viewControllers.count > 1, nav.topViewController === self {
            nav.popViewController(animated: animated)
        } else {
            dismiss(animated: animated)
        }
    }
}
