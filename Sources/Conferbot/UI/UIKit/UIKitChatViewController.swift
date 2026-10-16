//
//  UIKitChatViewController.swift
//  Conferbot
//
//  The UIKit-drawn chat, kept for iOS 13 and 14 only (#96): from iOS 15
//  ChatViewController hosts the SwiftUI ChatView instead. It is
//  ChatViewController's child and fills the navigation item of its parent:
//  the title in the bot's name, the bar in the bot's colours, ✕ and the
//  menu ("Email me this chat", Sound on / off). Plain text bubbles, typing
//  dots, the composer; typed steps are answered from the composer (the
//  step views, the live chat cards, the help centre, the home screen and
//  the wait cards need iOS 15).
//

import UIKit
import Combine

final class UIKitChatViewController: UIViewController {
    private let tableView = UITableView()
    private let chatInputView = ChatInputView()
    private var messages: [any RecordItem] = []
    private var isAgentTyping = false
    private var cancellables = Set<AnyCancellable>()
    /// ChatViewController's close (dismiss, or pop when pushed).
    private let onClose: () -> Void

    /// The table's sections: the messages, the typing dots.
    private enum Section: Int, CaseIterable { case messages, typing }

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The bar is the parent's (ChatViewController's) navigation item.
    private var hostItem: UINavigationItem { parent?.navigationItem ?? navigationItem }

    override func viewDidLoad() {
        super.viewDidLoad()
        ConferBot.shared.setSystemDarkMode(traitCollection.userInterfaceStyle == .dark)
        setupUI()
        setupNavigationBar()
        loadInitialData()
    }

    private func setupUI() {
        view.backgroundColor = .systemBackground

        tableView.delegate = self
        tableView.dataSource = self
        tableView.separatorStyle = .none
        tableView.backgroundColor = .systemBackground
        tableView.contentInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        tableView.register(MessageCell.self, forCellReuseIdentifier: "MessageCell")
        tableView.register(TypingIndicatorCell.self, forCellReuseIdentifier: "TypingCell")
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60
        tableView.keyboardDismissMode = .interactive

        view.addSubview(tableView)
        view.addSubview(chatInputView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        chatInputView.translatesAutoresizingMaskIntoConstraints = false

        // iOS 13 / 14 have no keyboardLayoutGuide: the composer's bottom
        // follows the keyboard's frame.
        let bottom = chatInputView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        composerBottom = bottom
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: chatInputView.topAnchor),
            chatInputView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chatInputView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottom
        ])
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillChange(_:)),
                                               name: UIResponder.keyboardWillChangeFrameNotification, object: nil)

        chatInputView.delegate = self
    }

    private var composerBottom: NSLayoutConstraint?

    @objc private func keyboardWillChange(_ note: Notification) {
        guard let end = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
        let inView = view.convert(end, from: nil)
        let overlap = max(0, view.bounds.maxY - inView.minY - view.safeAreaInsets.bottom)
        composerBottom?.constant = -overlap
        let duration = note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        UIView.animate(withDuration: duration) { self.view.layoutIfNeeded() }
        if overlap > 0 { scrollToBottom(animated: true) }
    }

    private func setupNavigationBar() {
        // The bot's name, from its last settings when these haven't come (#79).
        hostItem.title = ConferBot.shared.chatHeaderTitle
        let close = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(closeTapped))
        close.accessibilityLabel = I18n.t("common.close")
        hostItem.leftBarButtonItem = close
        updateConnectionStatus()
    }

    private func applyLook(_ look: ResolvedCustomizations) {
        hostItem.title = ConferBot.shared.chatHeaderTitle
        guard ConferBot.shared.hasServerLook else { return }
        let bg = UIColor(cbHex: look.headerBg)
        let ink = UIColor(cbHex: look.headerText)
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = bg
        appearance.titleTextAttributes = [.foregroundColor: ink]
        navigationController?.navigationBar.standardAppearance = appearance
        navigationController?.navigationBar.scrollEdgeAppearance = appearance
        navigationController?.navigationBar.compactAppearance = appearance
        navigationController?.navigationBar.tintColor = ink
        // The widget theme's surface behind the messages (the system one without a theme).
        let surface = look.surface.map { UIColor(cbHex: $0) } ?? .systemBackground
        view.backgroundColor = surface
        tableView.backgroundColor = surface
        chatInputView.applyLook(look)
        tableView.reloadData()
    }

    // A theme set to "auto" follows the phone's light / dark setting.
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        ConferBot.shared.setSystemDarkMode(traitCollection.userInterfaceStyle == .dark)
    }

    private func loadInitialData() {
        messages = ConferBot.shared.messages
        if messages.isEmpty {
            Task {
                try? await ConferBot.shared.startSession()
                await MainActor.run {
                    self.messages = ConferBot.shared.messages
                    self.tableView.reloadData()
                }
            }
        } else {
            tableView.reloadData()
            scrollToBottom(animated: false)
        }

        ConferBot.shared.$messages
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.handleNewMessages($0) }
            .store(in: &cancellables)

        // The bot's look (Core/Customization): the bar's colours and title, as on the web.
        ConferBot.shared.$customizations
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.applyLook($0) }
            .store(in: &cancellables)

        // The typing dots: an agent typing, the bot working on a step or an
        // AI reply on its way (as the SwiftUI chat)
        ConferBot.shared.$isAgentTyping
            .combineLatest(ConferBot.shared.$isProcessingNode, ConferBot.shared.$awaitingReply)
            .map { $0 || $1 || $2 }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.handleTypingIndicator($0) }
            .store(in: &cancellables)

        // Replies off while the agent locked the conversation or turned them
        // off, or the chat is closed (blocked, or ended with nothing going on, #40)
        let live = ConferBot.shared.liveChat
        live.$lockedBy.map { _ in () }
            .merge(with: live.$visitorInputEnabled.map { _ in () }, live.$blocked.map { _ in () },
                   ConferBot.shared.$messages.map { _ in () }, ConferBot.shared.$currentUIState.map { _ in () },
                   ConferBot.shared.$isLiveChatMode.map { _ in () }, ConferBot.shared.$isConnected.map { _ in () })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                let state = ComposerState.of(lockedBy: live.lockedBy, visitorInputEnabled: live.visitorInputEnabled,
                                             closed: ConferBot.shared.closedState)
                self?.chatInputView.setRepliesEnabled(state.enabled, reason: state.enabled ? nil : state.placeholder)
                self?.updateConnectionStatus()
            }
            .store(in: &cancellables)
    }

    private func handleNewMessages(_ newMessages: [any RecordItem]) {
        let old = messages
        messages = newMessages
        guard isViewLoaded, tableView.window != nil else {
            tableView.reloadData()
            return
        }
        // Only new messages at the end are animated in; anything else (a
        // reset, an edited or removed message) reloads the list.
        if old.count < newMessages.count, zip(old, newMessages).allSatisfy({ $0.id == $1.id }) {
            let rows = (old.count..<newMessages.count).map { IndexPath(row: $0, section: Section.messages.rawValue) }
            tableView.insertRows(at: rows, with: .automatic)
            scrollToBottom(animated: true)
        } else if old.count != newMessages.count || !zip(old, newMessages).allSatisfy({ $0.id == $1.id }) {
            tableView.reloadData()
            scrollToBottom(animated: false)
        }
    }

    private func handleTypingIndicator(_ isTyping: Bool) {
        guard isTyping != isAgentTyping else { return }
        isAgentTyping = isTyping
        let indexPath = IndexPath(row: 0, section: Section.typing.rawValue)
        if isTyping {
            tableView.insertRows(at: [indexPath], with: .automatic)
            scrollToBottom(animated: true)
        } else {
            tableView.deleteRows(at: [indexPath], with: .automatic)
        }
    }

    /// The menu once connected; a spinner while connecting; nothing for a
    /// closed chat, which isn't connecting to anything (#79).
    private func updateConnectionStatus() {
        switch ConferBot.shared.headerConnection {
        case .connected:
            hostItem.rightBarButtonItem = chatMenuItem()
        case .connecting:
            let indicator = UIActivityIndicatorView(style: .medium)
            indicator.startAnimating()
            hostItem.rightBarButtonItem = UIBarButtonItem(customView: indicator)
        case .none:
            hostItem.rightBarButtonItem = nil
        }
    }

    /// The chat menu (iOS 14): "Email me this chat" while there is a
    /// conversation (#39), Sound on / off when the bot has a sound (#90);
    /// none for a blocked visitor.
    private func chatMenuItem() -> UIBarButtonItem? {
        guard #available(iOS 14.0, *), ConferBot.shared.liveChat.blocked == nil else { return nil }
        var actions: [UIAction] = []
        if ConferBot.shared.currentSession != nil {
            actions.append(UIAction(title: EmailTranscript.Copy.menu, image: UIImage(systemName: "envelope")) { _ in
                ConferBot.shared.openEmailTranscript()
            })
        }
        let sounds = ConferBot.shared.sounds
        if sounds.hasSounds {
            actions.append(UIAction(title: sounds.soundOn ? I18n.t("chat.menu.soundOn") : I18n.t("chat.menu.soundOff"),
                                    image: UIImage(systemName: sounds.soundOn ? "speaker.wave.2" : "speaker.slash")) { [weak self] _ in
                sounds.toggle()
                self?.hostItem.rightBarButtonItem = self?.chatMenuItem()
            })
        }
        guard !actions.isEmpty else { return nil }
        let item = UIBarButtonItem(image: UIImage(systemName: "ellipsis"), menu: UIMenu(children: actions))
        item.accessibilityLabel = ChatText.menu
        return item
    }

    private func scrollToBottom(animated: Bool) {
        DispatchQueue.main.async {
            // The last row there is: the typing dots, or the last message.
            let section = Section.allCases.reversed().first { self.tableView.numberOfRows(inSection: $0.rawValue) > 0 }
            guard let section = section else { return }
            let row = self.tableView.numberOfRows(inSection: section.rawValue) - 1
            self.tableView.scrollToRow(at: IndexPath(row: row, section: section.rawValue), at: .bottom, animated: animated)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        ConferBot.shared.setChatVisible(true)
        // The launcher sound, or the sound pack's open (Core/Sounds)
        ConferBot.shared.chatOpened(true)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        ConferBot.shared.setChatVisible(false)
        ConferBot.shared.chatOpened(false)
    }

    @objc private func closeTapped() {
        onClose()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - UITableViewDataSource
extension UIKitChatViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .messages: return messages.count
        case .typing: return isAgentTyping ? 1 : 0
        case nil: return 0
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == Section.typing.rawValue {
            return tableView.dequeueReusableCell(withIdentifier: "TypingCell", for: indexPath)
        }
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "MessageCell", for: indexPath) as? MessageCell else {
            return UITableViewCell()
        }
        cell.configure(with: messages[indexPath.row], customization: ConferBot.shared.customization)
        return cell
    }
}

// MARK: - UITableViewDelegate
extension UIKitChatViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }
}

// MARK: - ChatInputViewDelegate
extension UIKitChatViewController: ChatInputViewDelegate {
    func chatInputView(_ inputView: ChatInputView, didSendMessage message: String) {
        // A typed question (ask-name, ask-email, OTP, AI, KB...) takes the
        // text as its answer; otherwise it goes as a chat message (#74).
        // A refused answer stays in the box with the reason over it.
        if let error = ConferBot.shared.submitText(message) {
            DispatchQueue.main.async { inputView.restore(message, error: error) }
        } else {
            inputView.restore(nil, error: nil)
        }
    }

    func chatInputViewDidBeginEditing(_ inputView: ChatInputView) {
        ConferBot.shared.sendTypingIndicator(isTyping: true)
    }

    func chatInputViewDidEndEditing(_ inputView: ChatInputView) {
        ConferBot.shared.sendTypingIndicator(isTyping: false)
    }
}
