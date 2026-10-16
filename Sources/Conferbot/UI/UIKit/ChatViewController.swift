//
//  ChatViewController.swift
//  Conferbot
//
//  Created by Conferbot SDK
//

import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// Main chat view controller for UIKit
public class ChatViewController: UIViewController {
    private let tableView = UITableView()
    private let chatInputView = ChatInputView()
    /// Live chat: the queue, the cards (leave a message, a file asked for, the
    /// lead card, the rating), locked / connection lines and quick actions,
    /// drawn with the SwiftUI pieces (LiveChatCards.swift).
    private lazy var liveStrip: UIViewController = {
        if #available(iOS 15.0, *) {
            let host = UIHostingController(rootView: LiveChatStrip(onUpload: { [weak self] in self?.pickFile() }))
            host.view.backgroundColor = .clear
            return host
        }
        return UIViewController()
    }()
    private var messages: [any RecordItem] = []
    private var isAgentTyping = false
    /// The step waiting for the visitor, drawn under the messages with the
    /// SwiftUI step views (FlowStepView): choice pills, rating, scale,
    /// slider, date, calendar, file, check options, ranking, cards, matrix,
    /// consent, payment and the OTP / address / signature extras. Typed
    /// steps are answered in the composer (submitText).
    private var stepState: NodeUIState?

    /// The table's sections: the messages, the waiting step, the typing dots.
    private enum Section: Int, CaseIterable { case messages, step, typing }

    public override func viewDidLoad() {
        super.viewDidLoad()
        ConferBot.shared.setSystemDarkMode(traitCollection.userInterfaceStyle == .dark)

        setupUI()
        setupNavigationBar()
        setupObservers()
        loadInitialData()
    }

    private func setupUI() {
        view.backgroundColor = .systemBackground

        // Setup table view
        tableView.delegate = self
        tableView.dataSource = self
        tableView.separatorStyle = .none
        tableView.backgroundColor = .systemBackground
        tableView.contentInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        tableView.register(MessageCell.self, forCellReuseIdentifier: "MessageCell")
        tableView.register(TypingIndicatorCell.self, forCellReuseIdentifier: "TypingCell")
        tableView.register(StepHostCell.self, forCellReuseIdentifier: "StepCell")
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60
        tableView.keyboardDismissMode = .interactive

        view.addSubview(tableView)
        addChild(liveStrip)
        view.addSubview(liveStrip.view)
        liveStrip.didMove(toParent: self)
        view.addSubview(chatInputView)

        // Layout
        tableView.translatesAutoresizingMaskIntoConstraints = false
        liveStrip.view.translatesAutoresizingMaskIntoConstraints = false
        chatInputView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: liveStrip.view.topAnchor),

            liveStrip.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            liveStrip.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            liveStrip.view.bottomAnchor.constraint(equalTo: chatInputView.topAnchor),

            chatInputView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chatInputView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        // Use keyboardLayoutGuide for iOS 15+ or fallback to safeAreaLayoutGuide
        if #available(iOS 15.0, *) {
            chatInputView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor).isActive = true
        } else {
            chatInputView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor).isActive = true
        }

        // Input view delegate
        chatInputView.delegate = self
    }

    private func setupNavigationBar() {
        title = ConferBot.shared.customization?.headerTitle ?? "Support Chat"

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(closeTapped)
        )

        // Connection status indicator
        updateConnectionStatus()
    }

    private func applyLook(_ look: ResolvedCustomizations) {
        guard ConferBot.shared.hasServerLook else { return }
        // The bot's name, also once an agent joins (web headerPresence.ts).
        title = look.title
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
    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        ConferBot.shared.setSystemDarkMode(traitCollection.userInterfaceStyle == .dark)
    }

    private func setupObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    private func loadInitialData() {
        // Load existing messages
        messages = ConferBot.shared.messages

        if messages.isEmpty {
            // Start new session
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

        // Subscribe to message updates
        ConferBot.shared.$messages
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newMessages in
                self?.handleNewMessages(newMessages)
            }
            .store(in: &cancellables)

        // The bot's look (Core/Customization): the bar's colours and title, as on the web.
        ConferBot.shared.$customizations
            .receive(on: DispatchQueue.main)
            .sink { [weak self] look in
                self?.applyLook(look)
            }
            .store(in: &cancellables)

        // The typing dots: an agent typing, the bot working on a step or an
        // AI reply on its way (as the SwiftUI chat)
        ConferBot.shared.$isAgentTyping
            .combineLatest(ConferBot.shared.$isProcessingNode, ConferBot.shared.$awaitingReply)
            .map { $0 || $1 || $2 }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isTyping in
                self?.handleTypingIndicator(isTyping)
            }
            .store(in: &cancellables)

        // The step waiting for the visitor (#74)
        ConferBot.shared.$currentUIState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.handleStep(state)
            }
            .store(in: &cancellables)

        // Replies off while the agent locked the conversation or turned them
        // off, or the chat is closed (blocked, or ended with nothing going on, #40)
        let live = ConferBot.shared.liveChat
        live.$lockedBy.map { _ in () }
            .merge(with: live.$visitorInputEnabled.map { _ in () }, live.$blocked.map { _ in () },
                   ConferBot.shared.$messages.map { _ in () }, ConferBot.shared.$currentUIState.map { _ in () },
                   ConferBot.shared.$isLiveChatMode.map { _ in () })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                let closed = ConferBot.shared.closedState
                self?.chatInputView.setRepliesEnabled(live.lockedBy == nil && live.visitorInputEnabled && closed?.inputOff != true,
                                                      reason: closed?.inputOff == true ? closed?.text : nil)
                self?.updateConnectionStatus()
            }
            .store(in: &cancellables)

        // The menu's "Your requests" (and its "New reply") follows the list (#38).
        let requests = ConferBot.shared.requests
        requests.$requests.map { _ in () }
            .merge(with: requests.$seen.map { _ in () })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateConnectionStatus() }
            .store(in: &cancellables)

        // Subscribe to connection status
        ConferBot.shared.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateConnectionStatus()
            }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

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
            let newIndexPaths = (old.count..<newMessages.count).map {
                IndexPath(row: $0, section: Section.messages.rawValue)
            }
            tableView.insertRows(at: newIndexPaths, with: .automatic)
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

    /// Draws the waiting step under the messages, or takes it away. The same
    /// step updated in place (an OTP moving to its code) keeps its view's state.
    private func handleStep(_ state: NodeUIState?) {
        let next = drawsStep(state) ? state : nil
        let had = stepState != nil
        let sameStep = had && next != nil && stepState?.stepNodeId == next?.stepNodeId
        stepState = next
        let indexPath = IndexPath(row: 0, section: Section.step.rawValue)
        switch (had, next != nil) {
        case (false, true):
            tableView.insertRows(at: [indexPath], with: .fade)
        case (true, false):
            tableView.deleteRows(at: [indexPath], with: .fade)
        case (true, true):
            if sameStep, #available(iOS 15.0, *) {
                tableView.reconfigureRows(at: [indexPath])
            } else {
                tableView.reloadRows(at: [indexPath], with: .fade)
            }
        case (false, false):
            return
        }
        if next != nil { scrollToBottom(animated: true) }
    }

    /// Whether the step has a view of its own: everything that waits for the
    /// visitor except plain typed questions (the composer answers those) and
    /// the handover wait (the live strip draws its card).
    private func drawsStep(_ state: NodeUIState?) -> Bool {
        guard #available(iOS 15.0, *), let state = state, let nodeId = state.stepNodeId else { return false }
        if case .textInput = state {
            let type = ConferBot.shared.waitingStep(nodeId)?.type ?? ""
            return ["otp-node", "address-node", "signature-node"].contains(type)
        }
        return true
    }

    private func updateConnectionStatus() {
        if ConferBot.shared.isConnected {
            navigationItem.rightBarButtonItem = chatMenuItem()
        } else {
            let indicator = UIActivityIndicatorView(style: .medium)
            indicator.startAnimating()
            navigationItem.rightBarButtonItem = UIBarButtonItem(customView: indicator)
        }
    }

    /// The chat menu: "Your requests" once the visitor has one ("Your
    /// requests · New reply" when one is unread, iOS 15, #38), "Email me this
    /// chat" while there is a conversation (#39; the card shows in the live
    /// strip); none for a blocked visitor.
    private func chatMenuItem() -> UIBarButtonItem? {
        guard #available(iOS 14.0, *), ConferBot.shared.liveChat.blocked == nil else { return nil }
        var actions: [UIAction] = []
        if #available(iOS 15.0, *), ConferBot.shared.requests.hasRequests {
            actions.append(UIAction(title: ConferBot.shared.requests.menuTitle, image: UIImage(systemName: "tray")) { [weak self] _ in
                self?.present(RequestsViewController(), animated: true)
            })
        }
        if ConferBot.shared.currentSession != nil {
            actions.append(UIAction(title: EmailTranscript.Copy.menu, image: UIImage(systemName: "envelope")) { _ in
                ConferBot.shared.openEmailTranscript()
            })
        }
        guard !actions.isEmpty else { return nil }
        let item = UIBarButtonItem(image: UIImage(systemName: "ellipsis"), menu: UIMenu(children: actions))
        item.accessibilityLabel = "Chat menu"
        return item
    }

    private func scrollToBottom(animated: Bool) {
        DispatchQueue.main.async {
            // The last row there is: the typing dots, the step, or the last message.
            let section = Section.allCases.reversed().first { self.tableView.numberOfRows(inSection: $0.rawValue) > 0 }
            guard let section = section else { return }
            let row = self.tableView.numberOfRows(inSection: section.rawValue) - 1
            self.tableView.scrollToRow(at: IndexPath(row: row, section: section.rawValue), at: .bottom, animated: animated)
        }
    }

    /// A live chat file: the system document picker.
    private func pickFile() {
        let picker: UIDocumentPickerViewController
        if #available(iOS 14.0, *) {
            picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        } else {
            picker = UIDocumentPickerViewController(documentTypes: ["public.item"], in: .import)
        }
        picker.delegate = self
        present(picker, animated: true)
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        ConferBot.shared.setChatVisible(true)
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        ConferBot.shared.setChatVisible(false)
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func keyboardWillShow(_ notification: Notification) {
        // Handled by keyboardLayoutGuide
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        // Handled by keyboardLayoutGuide
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - UITableViewDataSource
extension ChatViewController: UITableViewDataSource {
    public func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .messages: return messages.count
        case .step: return stepState == nil ? 0 : 1
        case .typing: return isAgentTyping ? 1 : 0
        case nil: return 0
        }
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == Section.typing.rawValue {
            return tableView.dequeueReusableCell(withIdentifier: "TypingCell", for: indexPath)
        }
        if indexPath.section == Section.step.rawValue {
            let cell = tableView.dequeueReusableCell(withIdentifier: "StepCell", for: indexPath)
            if #available(iOS 15.0, *), let state = stepState, let stepCell = cell as? StepHostCell {
                stepCell.show(state, parent: self) { [weak self] in
                    // The step's view changed size (calendar slots, a picked file)
                    UIView.performWithoutAnimation {
                        self?.tableView.beginUpdates()
                        self?.tableView.endUpdates()
                    }
                }
            }
            return cell
        }

        guard let cell = tableView.dequeueReusableCell(withIdentifier: "MessageCell", for: indexPath) as? MessageCell else {
            return UITableViewCell()
        }
        let message = messages[indexPath.row]
        cell.configure(with: message, customization: ConferBot.shared.customization)
        return cell
    }
}

// MARK: - UITableViewDelegate
extension ChatViewController: UITableViewDelegate {
    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }
}

// MARK: - ChatInputViewDelegate
extension ChatViewController: ChatInputViewDelegate {
    public func chatInputView(_ inputView: ChatInputView, didSendMessage message: String) {
        // A typed question (ask-name, ask-email, OTP, AI, KB...) takes the
        // text as its answer; otherwise it goes as a chat message (#74).
        // A refused answer stays in the box with the reason over it.
        if let error = ConferBot.shared.submitText(message) {
            DispatchQueue.main.async { inputView.restore(message, error: error) }
        } else {
            inputView.restore(nil, error: nil)
        }
    }

    public func chatInputViewDidBeginEditing(_ inputView: ChatInputView) {
        ConferBot.shared.sendTypingIndicator(isTyping: true)
    }

    public func chatInputViewDidEndEditing(_ inputView: ChatInputView) {
        ConferBot.shared.sendTypingIndicator(isTyping: false)
    }
}

import Combine

extension ChatViewController: UIDocumentPickerDelegate {
    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        ConferBot.shared.sendLiveFile(fileURL: url) { [weak self] error in
            guard let error = error else { return }
            let alert = UIAlertController(title: nil, message: error, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self?.present(alert, animated: true)
        }
    }
}

/// The waiting step's SwiftUI view (FlowStepView) in a table cell.
final class StepHostCell: UITableViewCell {
    private var host: UIViewController?
    private var onResize: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @available(iOS 15.0, *)
    func show(_ state: NodeUIState, parent: UIViewController, onResize: @escaping () -> Void) {
        self.onResize = onResize
        if #available(iOS 16.0, *) {
            // Sizes itself and follows its content's size.
            contentConfiguration = UIHostingConfiguration { FlowStepView(uiState: state) }
                .margins(.horizontal, 16)
                .margins(.vertical, 6)
            return
        }
        // iOS 15: a hosting controller pinned to the cell, which reports
        // its content's height changes so the table can re-measure the row.
        let root = AnyView(FlowStepView(uiState: state)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(GeometryReader { proxy in
                Color.clear.preference(key: StepHeightKey.self, value: proxy.size.height)
            })
            .onPreferenceChange(StepHeightKey.self) { [weak self] _ in
                DispatchQueue.main.async { self?.onResize?() }
            })
        if let host = host as? UIHostingController<AnyView> {
            host.rootView = root
            host.view.invalidateIntrinsicContentSize()
            return
        }
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        parent.addChild(host)
        contentView.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: contentView.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        ])
        host.didMove(toParent: parent)
        self.host = host
    }
}

private struct StepHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
