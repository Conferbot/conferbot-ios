//
//  MessageCell.swift
//  Conferbot
//
//  Created by Conferbot SDK
//

import UIKit

/// Table view cell for displaying chat messages
public class MessageCell: UITableViewCell {
    private let bubbleView = UIView()
    private let messageLabel = UILabel()
    private let timeLabel = UILabel()
    private let avatarImageView = UIImageView()

    private var leadingConstraint: NSLayoutConstraint?
    private var trailingConstraint: NSLayoutConstraint?

    public override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        backgroundColor = .clear
        selectionStyle = .none

        // Bubble view
        bubbleView.layer.cornerRadius = 16
        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(bubbleView)

        // Message label
        messageLabel.numberOfLines = 0
        messageLabel.font = .systemFont(ofSize: 16)
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.addSubview(messageLabel)

        // Time label
        timeLabel.font = .systemFont(ofSize: 11)
        timeLabel.textColor = .secondaryLabel
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(timeLabel)

        // Avatar
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.layer.cornerRadius = 16
        avatarImageView.clipsToBounds = true
        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(avatarImageView)

        // Constraints
        leadingConstraint = bubbleView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 48)
        trailingConstraint = bubbleView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -48)

        NSLayoutConstraint.activate([
            bubbleView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            bubbleView.widthAnchor.constraint(lessThanOrEqualToConstant: 280),

            messageLabel.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 12),
            messageLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 12),
            messageLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -12),
            messageLabel.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -12),

            timeLabel.topAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: 4),
            timeLabel.centerXAnchor.constraint(equalTo: bubbleView.centerXAnchor),
            timeLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),

            avatarImageView.widthAnchor.constraint(equalToConstant: 32),
            avatarImageView.heightAnchor.constraint(equalToConstant: 32),
            avatarImageView.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor)
        ])
    }

    public func configure(with message: any RecordItem, customization: ConferBotCustomization?) {
        // Determine if user or bot/agent message
        let isUserMessage = message.type == .userMessage

        // Configure bubble position
        leadingConstraint?.isActive = false
        trailingConstraint?.isActive = false

        if isUserMessage {
            trailingConstraint?.isActive = true
            bubbleView.backgroundColor = customization?.userBubbleColor ?? UIColor.systemBlue
            messageLabel.textColor = .white
            avatarImageView.isHidden = true
        } else {
            leadingConstraint?.isActive = true
            bubbleView.backgroundColor = customization?.botBubbleColor ?? UIColor.systemGray5
            messageLabel.textColor = .label
            avatarImageView.isHidden = !(customization?.showAvatar ?? true)

            // Position avatar
            NSLayoutConstraint.activate([
                avatarImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8)
            ])

            // Load avatar if needed
            if let avatarURL = customization?.avatarURL {
                loadAvatar(from: avatarURL)
            } else {
                avatarImageView.image = UIImage(systemName: "person.circle.fill")
                avatarImageView.tintColor = .systemGray
            }
        }

        // Configure content based on message type
        if let userMessage = message as? UserMessageRecord {
            messageLabel.text = userMessage.text
        } else if let botMessage = message as? BotMessageRecord {
            messageLabel.text = botMessage.text ?? "..."
        } else if let agentMessage = message as? AgentMessageRecord {
            messageLabel.text = agentMessage.text
        } else if let fileMessage = message as? AgentMessageFileRecord {
            messageLabel.text = "📎 File: \(fileMessage.file)"
        } else if let audioMessage = message as? AgentMessageAudioRecord {
            messageLabel.text = "🎵 Audio message"
        } else if let joinedMessage = message as? AgentJoinedMessageRecord {
            messageLabel.text = "\(joinedMessage.agentDetails.name) joined the chat"
            bubbleView.backgroundColor = .systemYellow.withAlphaComponent(0.2)
            messageLabel.textColor = .label
        } else if let systemMessage = message as? SystemMessageRecord {
            messageLabel.text = systemMessage.text
            bubbleView.backgroundColor = .systemGray6
            messageLabel.textColor = .secondaryLabel
        }

        // Time
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        timeLabel.text = formatter.string(from: message.time)

        // Apply corner radius customization
        if let radius = customization?.bubbleCornerRadius {
            bubbleView.layer.cornerRadius = radius
        }
    }

    private func loadAvatar(from url: URL) {
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                self?.avatarImageView.image = image
            }
        }.resume()
    }
}

/// Typing indicator cell
public class TypingIndicatorCell: UITableViewCell {
    private let bubbleView = UIView()
    private let dot1 = UIView()
    private let dot2 = UIView()
    private let dot3 = UIView()

    public override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
        startAnimating()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        backgroundColor = .clear
        selectionStyle = .none

        bubbleView.backgroundColor = .systemGray5
        bubbleView.layer.cornerRadius = 16
        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(bubbleView)

        let dots = [dot1, dot2, dot3]
        dots.forEach { dot in
            dot.backgroundColor = .systemGray
            dot.layer.cornerRadius = 4
            dot.translatesAutoresizingMaskIntoConstraints = false
            bubbleView.addSubview(dot)
        }

        NSLayoutConstraint.activate([
            bubbleView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 48),
            bubbleView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            bubbleView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            bubbleView.widthAnchor.constraint(equalToConstant: 60),
            bubbleView.heightAnchor.constraint(equalToConstant: 36),

            dot1.centerYAnchor.constraint(equalTo: bubbleView.centerYAnchor),
            dot1.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 12),
            dot1.widthAnchor.constraint(equalToConstant: 8),
            dot1.heightAnchor.constraint(equalToConstant: 8),

            dot2.centerYAnchor.constraint(equalTo: bubbleView.centerYAnchor),
            dot2.leadingAnchor.constraint(equalTo: dot1.trailingAnchor, constant: 6),
            dot2.widthAnchor.constraint(equalToConstant: 8),
            dot2.heightAnchor.constraint(equalToConstant: 8),

            dot3.centerYAnchor.constraint(equalTo: bubbleView.centerYAnchor),
            dot3.leadingAnchor.constraint(equalTo: dot2.trailingAnchor, constant: 6),
            dot3.widthAnchor.constraint(equalToConstant: 8),
            dot3.heightAnchor.constraint(equalToConstant: 8)
        ])
    }

    private func startAnimating() {
        let dots = [dot1, dot2, dot3]

        for (index, dot) in dots.enumerated() {
            UIView.animate(
                withDuration: 0.6,
                delay: Double(index) * 0.2,
                options: [.repeat, .autoreverse],
                animations: {
                    dot.alpha = 0.3
                }
            )
        }
    }
}
