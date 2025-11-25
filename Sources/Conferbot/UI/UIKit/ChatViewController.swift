//
//  ChatViewController.swift
//  Conferbot
//
//  Created by Conferbot SDK
//

import UIKit

/// Main chat view controller for UIKit
public class ChatViewController: UIViewController {
    private let tableView = UITableView()
    private let inputView = ChatInputView()
    private var messages: [any RecordItem] = []
    private var isAgentTyping = false

    public override func viewDidLoad() {
        super.viewDidLoad()

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

        view.addSubview(tableView)
        view.addSubview(inputView)

        // Layout
        tableView.translatesAutoresizingMaskIntoConstraints = false
        inputView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: inputView.topAnchor),

            inputView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
        ])

        // Input view delegate
        inputView.delegate = self
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

        // Subscribe to typing indicator
        ConferBot.shared.$isAgentTyping
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isTyping in
                self?.handleTypingIndicator(isTyping)
            }
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
        let oldCount = messages.count
        messages = newMessages

        if oldCount < newMessages.count {
            // New messages added
            let newIndexPaths = (oldCount..<newMessages.count).map {
                IndexPath(row: $0, section: 0)
            }

            tableView.insertRows(at: newIndexPaths, with: .automatic)
            scrollToBottom(animated: true)
        }
    }

    private func handleTypingIndicator(_ isTyping: Bool) {
        self.isAgentTyping = isTyping

        if isTyping {
            // Add typing indicator
            let indexPath = IndexPath(row: messages.count, section: 0)
            tableView.insertRows(at: [indexPath], with: .automatic)
            scrollToBottom(animated: true)
        } else {
            // Remove typing indicator
            let indexPath = IndexPath(row: messages.count, section: 0)
            tableView.deleteRows(at: [indexPath], with: .automatic)
        }
    }

    private func updateConnectionStatus() {
        if ConferBot.shared.isConnected {
            navigationItem.rightBarButtonItem = nil
        } else {
            let indicator = UIActivityIndicatorView(style: .medium)
            indicator.startAnimating()
            navigationItem.rightBarButtonItem = UIBarButtonItem(customView: indicator)
        }
    }

    private func scrollToBottom(animated: Bool) {
        guard !messages.isEmpty || isAgentTyping else { return }

        let lastRow = isAgentTyping ? messages.count : messages.count - 1
        let indexPath = IndexPath(row: lastRow, section: 0)

        DispatchQueue.main.async {
            self.tableView.scrollToRow(at: indexPath, at: .bottom, animated: animated)
        }
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
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return messages.count + (isAgentTyping ? 1 : 0)
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        // Check if this is typing indicator
        if isAgentTyping && indexPath.row == messages.count {
            let cell = tableView.dequeueReusableCell(withIdentifier: "TypingCell", for: indexPath) as! TypingIndicatorCell
            return cell
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: "MessageCell", for: indexPath) as! MessageCell
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
    func chatInputView(_ inputView: ChatInputView, didSendMessage message: String) {
        Task {
            try? await ConferBot.shared.sendMessage(message)
        }
    }

    func chatInputViewDidBeginEditing(_ inputView: ChatInputView) {
        ConferBot.shared.sendTypingIndicator(isTyping: true)
    }

    func chatInputViewDidEndEditing(_ inputView: ChatInputView) {
        ConferBot.shared.sendTypingIndicator(isTyping: false)
    }
}

import Combine
