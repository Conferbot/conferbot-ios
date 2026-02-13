//
//  ChatInputView.swift
//  Conferbot
//
//  Created by Conferbot SDK
//

import UIKit

/// Delegate protocol for chat input events
public protocol ChatInputViewDelegate: AnyObject {
    func chatInputView(_ inputView: ChatInputView, didSendMessage message: String)
    func chatInputViewDidBeginEditing(_ inputView: ChatInputView)
    func chatInputViewDidEndEditing(_ inputView: ChatInputView)
}

/// Chat input view with text field and send button
public class ChatInputView: UIView {
    public weak var delegate: ChatInputViewDelegate?

    private let textView = UITextView()
    private let sendButton = UIButton(type: .system)
    private let placeholderLabel = UILabel()
    private let containerView = UIView()

    private var textViewHeightConstraint: NSLayoutConstraint?
    private let maxHeight: CGFloat = 100

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        backgroundColor = .systemBackground

        // Container view
        containerView.backgroundColor = .systemBackground
        containerView.layer.borderColor = UIColor.separator.cgColor
        containerView.layer.borderWidth = 0.5
        containerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(containerView)

        // Text view
        textView.font = .systemFont(ofSize: 16)
        textView.backgroundColor = .systemGray6
        textView.layer.cornerRadius = 20
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        textView.isScrollEnabled = false
        textView.delegate = self
        textView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(textView)

        // Placeholder
        placeholderLabel.text = "Type a message..."
        placeholderLabel.font = .systemFont(ofSize: 16)
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        textView.addSubview(placeholderLabel)

        // Send button
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        let image = UIImage(systemName: "arrow.up.circle.fill", withConfiguration: config)
        sendButton.setImage(image, for: .normal)
        sendButton.tintColor = .systemBlue
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        sendButton.isEnabled = false
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(sendButton)

        // Constraints
        textViewHeightConstraint = textView.heightAnchor.constraint(equalToConstant: 40)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),

            textView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 8),
            textView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            textView.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),
            textView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -8),
            textViewHeightConstraint ?? textView.heightAnchor.constraint(equalToConstant: 36),

            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: 10),
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 17),
            placeholderLabel.trailingAnchor.constraint(equalTo: textView.trailingAnchor, constant: -17),

            sendButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            sendButton.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -8),
            sendButton.widthAnchor.constraint(equalToConstant: 36),
            sendButton.heightAnchor.constraint(equalToConstant: 36)
        ])
    }

    @objc private func sendTapped() {
        let text = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else { return }

        delegate?.chatInputView(self, didSendMessage: text)

        // Clear text
        textView.text = ""
        textViewDidChange(textView)
    }

    public override var intrinsicContentSize: CGSize {
        return CGSize(width: UIView.noIntrinsicMetric, height: 56)
    }
}

// MARK: - UITextViewDelegate
extension ChatInputView: UITextViewDelegate {
    public func textViewDidChange(_ textView: UITextView) {
        // Update placeholder
        placeholderLabel.isHidden = !textView.text.isEmpty

        // Update send button
        sendButton.isEnabled = !textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        // Adjust height
        let size = textView.sizeThatFits(CGSize(width: textView.frame.width, height: .infinity))
        let newHeight = min(size.height, maxHeight)

        textViewHeightConstraint?.constant = newHeight
        textView.isScrollEnabled = size.height > maxHeight

        invalidateIntrinsicContentSize()
    }

    public func textViewDidBeginEditing(_ textView: UITextView) {
        delegate?.chatInputViewDidBeginEditing(self)
    }

    public func textViewDidEndEditing(_ textView: UITextView) {
        delegate?.chatInputViewDidEndEditing(self)
    }

    public func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        let currentText = textView.text ?? ""
        guard let stringRange = Range(range, in: currentText) else { return false }
        let updatedText = currentText.replacingCharacters(in: stringRange, with: text)

        return updatedText.count <= ConferBotConstants.maxMessageLength
    }
}
