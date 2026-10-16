//
//  RequestsViewController.swift
//  Conferbot
//
//  "Your requests" for UIKit apps: the SwiftUI screens
//  (UI/SwiftUI/RequestsPortalView.swift) in a hosting controller. It opens
//  the list (or one request) when it appears and dismisses itself when the
//  portal closes (Back from the list, or a request that is the chat on
//  screen). ChatViewController's menu presents it.
//

import UIKit
import SwiftUI
#if canImport(Combine)
import Combine
#endif

@available(iOS 15.0, *)
public final class RequestsViewController: UIHostingController<RequestsPortalView> {
    private let requestId: String?
    private var sub: AnyCancellable?
    private var opened = false

    /// The list, or one request straight away (Back then leaves).
    public init(requestId: String? = nil) {
        self.requestId = requestId
        super.init(rootView: RequestsPortalView())
        modalPresentationStyle = .fullScreen
    }

    @available(*, unavailable)
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let requests = ConferBot.shared.requests
        sub = requests.$isOpen.dropFirst().removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] open in
            guard let self = self, !open, self.opened else { return }
            self.presentingViewController?.dismiss(animated: true)
        }
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard !opened else { return }
        opened = true
        let portal = ConferBot.shared.requests.portal!
        let id = requestId
        Task { [weak self] in
            if let id = id { await portal.openRequest(id) } else { await portal.openList() }
            // The request is the chat on screen: nothing to show here.
            if !portal.isOpen { self?.presentingViewController?.dismiss(animated: true) }
        }
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Gone some other way (the app dismissed it): the portal closes too.
        if isBeingDismissed || presentingViewController == nil, ConferBot.shared.requests.isOpen {
            ConferBot.shared.requests.close()
        }
    }
}
