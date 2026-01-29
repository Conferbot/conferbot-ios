//
//  DisplayNodeHandlers.swift
//  Conferbot
//
//  Node handlers for all 28 display node types:
//
//  Send nodes (display then proceed):
//  - send_message (TEXT)
//  - send_image (IMAGE)
//  - send_video
//  - send_audio
//  - send_file
//  - send_gif
//
//  Ask nodes (display and wait for input):
//  - ask_name
//  - ask_email
//  - ask_phone
//  - ask_number
//  - ask_url
//  - ask_address
//  - ask_date
//  - ask_time
//  - ask_date_time
//  - ask_date_range
//  - ask_file_upload
//  - ask_question
//
//  Choice nodes:
//  - send_buttons
//  - send_quick_replies
//  - send_cards
//
//  Rating nodes:
//  - ask_rating
//  - opinion_scale
//
//  Special display:
//  - live_chat
//  - send_link
//  - embed_link
//  - embed_custom_code
//

import Foundation

// MARK: - Send Message Handler

/// Handler for send_message and TEXT nodes
/// Displays a text message and proceeds to next node
public final class SendMessageHandler: BaseNodeHandler {

    public override var nodeType: String { NodeTypes.Display.sendMessage }

    /// Additional node types this handler can process
    public static let additionalTypes: [String] = [NodeTypes.Display.text]

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("Send message node missing data")
        }

        // Extract message text from various possible keys
        let rawMessage = getString(data, "message")
            ?? getString(data, "text")
            ?? getString(data, "content")
            ?? ""

        // Resolve any variables in the message
        let resolvedMessage = state.resolveVariables(text: rawMessage)

        // Extract typing indicator preference (default true for better UX)
        let showTyping = getBool(data, "typing")
            ?? getBool(data, "showTyping")
            ?? true

        // Extract typing delay if specified
        let typingDelay = getDouble(data, "typingDelay")
            ?? getDouble(data, "delay")

        // Add to transcript
        let nodeId = getNodeId(node)
        state.addBotMessage(resolvedMessage, nodeId: nodeId, nodeType: nodeType)

        // If there's a typing delay, return delayed proceed after displaying
        if let delay = typingDelay, delay > 0 {
            // Display message first, then delay
            return .displayUI(.message(text: resolvedMessage, typing: showTyping))
        }

        return .displayUI(.message(text: resolvedMessage, typing: showTyping))
    }
}

// MARK: - Send Image Handler

/// Handler for send_image and IMAGE nodes
/// Displays an image with optional caption and proceeds
public final class SendImageHandler: BaseNodeHandler {

    public override var nodeType: String { NodeTypes.Display.sendImage }

    /// Additional node types this handler can process
    public static let additionalTypes: [String] = [NodeTypes.Display.image]

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("Send image node missing data")
        }

        // Extract image URL from various possible keys
        guard let rawUrl = getString(data, "imageUrl")
            ?? getString(data, "url")
            ?? getString(data, "src")
            ?? getString(data, "image") else {
            return .error("Send image node missing image URL")
        }

        // Resolve variables in URL
        let resolvedUrl = state.resolveVariables(text: rawUrl)

        // Extract and resolve optional caption
        var caption: String? = nil
        if let rawCaption = getString(data, "caption") ?? getString(data, "alt") ?? getString(data, "title") {
            caption = state.resolveVariables(text: rawCaption)
        }

        // Add to transcript
        let nodeId = getNodeId(node)
        state.addBotMessage("[Image: \(caption ?? resolvedUrl)]", nodeId: nodeId, nodeType: nodeType)

        return .displayUI(.image(url: resolvedUrl, caption: caption))
    }
}

// MARK: - Send Video Handler

/// Handler for send_video nodes
/// Displays a video with optional caption and proceeds
public final class SendVideoHandler: BaseNodeHandler {

    public override var nodeType: String { NodeTypes.Display.sendVideo }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("Send video node missing data")
        }

        // Extract video URL from various possible keys
        guard let rawUrl = getString(data, "videoUrl")
            ?? getString(data, "url")
            ?? getString(data, "src")
            ?? getString(data, "video") else {
            return .error("Send video node missing video URL")
        }

        // Resolve variables in URL
        let resolvedUrl = state.resolveVariables(text: rawUrl)

        // Extract and resolve optional caption
        var caption: String? = nil
        if let rawCaption = getString(data, "caption") ?? getString(data, "title") ?? getString(data, "description") {
            caption = state.resolveVariables(text: rawCaption)
        }

        // Add to transcript
        let nodeId = getNodeId(node)
        state.addBotMessage("[Video: \(caption ?? resolvedUrl)]", nodeId: nodeId, nodeType: nodeType)

        return .displayUI(.video(url: resolvedUrl, caption: caption))
    }
}

// MARK: - Send Audio Handler

/// Handler for send_audio nodes
/// Displays an audio player and proceeds
public final class SendAudioHandler: BaseNodeHandler {

    public override var nodeType: String { NodeTypes.Display.sendAudio }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("Send audio node missing data")
        }

        // Extract audio URL from various possible keys
        guard let rawUrl = getString(data, "audioUrl")
            ?? getString(data, "url")
            ?? getString(data, "src")
            ?? getString(data, "audio") else {
            return .error("Send audio node missing audio URL")
        }

        // Resolve variables in URL
        let resolvedUrl = state.resolveVariables(text: rawUrl)

        // Add to transcript
        let nodeId = getNodeId(node)
        state.addBotMessage("[Audio: \(resolvedUrl)]", nodeId: nodeId, nodeType: nodeType)

        return .displayUI(.audio(url: resolvedUrl))
    }
}

// MARK: - Send File Handler

/// Handler for send_file nodes
/// Displays a file download link and proceeds
public final class SendFileHandler: BaseNodeHandler {

    public override var nodeType: String { NodeTypes.Display.sendFile }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("Send file node missing data")
        }

        // Extract file URL from various possible keys
        guard let rawUrl = getString(data, "fileUrl")
            ?? getString(data, "url")
            ?? getString(data, "src")
            ?? getString(data, "file") else {
            return .error("Send file node missing file URL")
        }

        // Resolve variables in URL
        let resolvedUrl = state.resolveVariables(text: rawUrl)

        // Extract file name
        var fileName = getString(data, "fileName")
            ?? getString(data, "name")
            ?? getString(data, "filename")

        // If no filename provided, try to extract from URL
        if fileName == nil {
            if let url = URL(string: resolvedUrl) {
                fileName = url.lastPathComponent
            }
        }

        // Resolve variables in file name
        let resolvedFileName = fileName != nil ? state.resolveVariables(text: fileName!) : "file"

        // Add to transcript
        let nodeId = getNodeId(node)
        state.addBotMessage("[File: \(resolvedFileName)]", nodeId: nodeId, nodeType: nodeType)

        return .displayUI(.file(url: resolvedUrl, name: resolvedFileName))
    }
}

// MARK: - Send GIF Handler

/// Handler for send_gif nodes
/// Displays an animated GIF and proceeds
public final class SendGifHandler: BaseNodeHandler {

    public override var nodeType: String { NodeTypes.Display.sendGif }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("Send GIF node missing data")
        }

        // Extract GIF URL from various possible keys
        guard let rawUrl = getString(data, "gifUrl")
            ?? getString(data, "url")
            ?? getString(data, "src")
            ?? getString(data, "gif") else {
            return .error("Send GIF node missing GIF URL")
        }

        // Resolve variables in URL
        let resolvedUrl = state.resolveVariables(text: rawUrl)

        // Add to transcript
        let nodeId = getNodeId(node)
        state.addBotMessage("[GIF: \(resolvedUrl)]", nodeId: nodeId, nodeType: nodeType)

        return .displayUI(.gif(url: resolvedUrl))
    }
}

// MARK: - Ask Name Handler

/// Handler for ask_name nodes
/// Displays text input with name placeholder and waits for user input
public final class AskNameHandler: BaseNodeHandler {

    public override var nodeType: String { NodeTypes.Display.askName }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        let data = getNodeData(node)
        let nodeId = getNodeId(node) ?? UUID().uuidString

        // Extract custom message if provided
        if let message = data.flatMap({ getString($0, "message") ?? getString($0, "text") }) {
            let resolvedMessage = state.resolveVariables(text: message)
            state.addBotMessage(resolvedMessage, nodeId: nodeId, nodeType: nodeType)
        }

        // Extract placeholder or use default
        let placeholder = data.flatMap { getString($0, "placeholder") }
            ?? data.flatMap { getString($0, "inputPlaceholder") }
            ?? "Enter your name"

        let resolvedPlaceholder = state.resolveVariables(text: placeholder)

        // Name input typically has no validation, but could have length constraints
        // For now, we use nil validation to allow any text input
        return .displayUI(.textInput(placeholder: resolvedPlaceholder, validation: nil, nodeId: nodeId))
    }
}

// MARK: - Ask Email Handler

/// Handler for ask_email nodes
/// Displays text input with email validation and waits for user input
public final class AskEmailHandler: BaseNodeHandler {

    public override var nodeType: String { NodeTypes.Display.askEmail }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        let data = getNodeData(node)
        let nodeId = getNodeId(node) ?? UUID().uuidString

        // Extract custom message if provided
        if let message = data.flatMap({ getString($0, "message") ?? getString($0, "text") }) {
            let resolvedMessage = state.resolveVariables(text: message)
            state.addBotMessage(resolvedMessage, nodeId: nodeId, nodeType: nodeType)
        }

        // Extract placeholder or use default
        let placeholder = data.flatMap { getString($0, "placeholder") }
            ?? data.flatMap { getString($0, "inputPlaceholder") }
            ?? "Enter your email"

        let resolvedPlaceholder = state.resolveVariables(text: placeholder)

        // Email validation is required for this node type
        return .displayUI(.textInput(placeholder: resolvedPlaceholder, validation: .email, nodeId: nodeId))
    }
}

// MARK: - Ask Phone Handler

/// Handler for ask_phone nodes
/// Displays text input with phone validation and waits for user input
public final class AskPhoneHandler: BaseNodeHandler {

    public override var nodeType: String { NodeTypes.Display.askPhone }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        let data = getNodeData(node)
        let nodeId = getNodeId(node) ?? UUID().uuidString

        // Extract custom message if provided
        if let message = data.flatMap({ getString($0, "message") ?? getString($0, "text") }) {
            let resolvedMessage = state.resolveVariables(text: message)
            state.addBotMessage(resolvedMessage, nodeId: nodeId, nodeType: nodeType)
        }

        // Extract placeholder or use default
        let placeholder = data.flatMap { getString($0, "placeholder") }
            ?? data.flatMap { getString($0, "inputPlaceholder") }
            ?? "Enter your phone number"

        let resolvedPlaceholder = state.resolveVariables(text: placeholder)

        // Phone validation is required for this node type
        return .displayUI(.textInput(placeholder: resolvedPlaceholder, validation: .phone, nodeId: nodeId))
    }
}

// MARK: - Ask Number Handler

/// Handler for ask_number nodes
/// Displays text input with number validation and waits for user input
public final class AskNumberHandler: BaseNodeHandler {

    public override var nodeType: String { NodeTypes.Display.askNumber }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        let data = getNodeData(node)
        let nodeId = getNodeId(node) ?? UUID().uuidString

        // Extract custom message if provided
        if let message = data.flatMap({ getString($0, "message") ?? getString($0, "text") }) {
            let resolvedMessage = state.resolveVariables(text: message)
            state.addBotMessage(resolvedMessage, nodeId: nodeId, nodeType: nodeType)
        }

        // Extract placeholder or use default
        let placeholder = data.flatMap { getString($0, "placeholder") }
            ?? data.flatMap { getString($0, "inputPlaceholder") }
            ?? "Enter a number"

        let resolvedPlaceholder = state.resolveVariables(text: placeholder)

        // Number validation is required for this node type
        return .displayUI(.textInput(placeholder: resolvedPlaceholder, validation: .number, nodeId: nodeId))
    }
}

// MARK: - Ask URL Handler

/// Handler for ask_url nodes
/// Displays text input with URL validation and waits for user input
public final class AskUrlHandler: BaseNodeHandler {

    public override var nodeType: String { NodeTypes.Display.askUrl }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        let data = getNodeData(node)
        let nodeId = getNodeId(node) ?? UUID().uuidString

        // Extract custom message if provided
        if let message = data.flatMap({ getString($0, "message") ?? getString($0, "text") }) {
            let resolvedMessage = state.resolveVariables(text: message)
            state.addBotMessage(resolvedMessage, nodeId: nodeId, nodeType: nodeType)
        }

        // Extract placeholder or use default
        let placeholder = data.flatMap { getString($0, "placeholder") }
            ?? data.flatMap { getString($0, "inputPlaceholder") }
            ?? "Enter a URL"

        let resolvedPlaceholder = state.resolveVariables(text: placeholder)

        // URL validation is required for this node type
        return .displayUI(.textInput(placeholder: resolvedPlaceholder, validation: .url, nodeId: nodeId))
    }
}

// MARK: - Ask Address Handler

/// Handler for ask_address nodes
/// Displays text input for address entry and waits for user input
public final class AskAddressHandler: BaseNodeHandler {

    public override var nodeType: String { NodeTypes.Display.askAddress }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        let data = getNodeData(node)
        let nodeId = getNodeId(node) ?? UUID().uuidString

        // Extract custom message if provided
        if let message = data.flatMap({ getString($0, "message") ?? getString($0, "text") }) {
            let resolvedMessage = state.resolveVariables(text: message)
            state.addBotMessage(resolvedMessage, nodeId: nodeId, nodeType: nodeType)
        }

        // Extract placeholder or use default
        let placeholder = data.flatMap { getString($0, "placeholder") }
            ?? data.flatMap { getString($0, "inputPlaceholder") }
            ?? "Enter your address"

        let resolvedPlaceholder = state.resolveVariables(text: placeholder)

        // Address input typically has no strict validation
        // Could implement custom validation for address format if needed
        return .displayUI(.textInput(placeholder: resolvedPlaceholder, validation: nil, nodeId: nodeId))
    }
}

// MARK: - Ask Date Handler

/// Handler for ask_date nodes
/// Displays a calendar picker in date mode and waits for user selection
public final class AskDateHandler: BaseNodeHandler {

    public override var nodeType: String { NodeTypes.Display.askDate }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        let data = getNodeData(node)
        let nodeId = getNodeId(node) ?? UUID().uuidString

        // Extract custom message if provided
        if let message = data.flatMap({ getString($0, "message") ?? getString($0, "text") }) {
            let resolvedMessage = state.resolveVariables(text: message)
            state.addBotMessage(resolvedMessage, nodeId: nodeId, nodeType: nodeType)
        }

        // Date mode for calendar picker
        return .displayUI(.calendar(mode: .date, nodeId: nodeId))
    }
}

// MARK: - Ask Time Handler

/// Handler for ask_time nodes
/// Displays a calendar picker in time mode and waits for user selection
public final class AskTimeHandler: BaseNodeHandler {

    public override var nodeType: String { NodeTypes.Display.askTime }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        let data = getNodeData(node)
        let nodeId = getNodeId(node) ?? UUID().uuidString

        // Extract custom message if provided
        if let message = data.flatMap({ getString($0, "message") ?? getString($0, "text") }) {
            let resolvedMessage = state.resolveVariables(text: message)
            state.addBotMessage(resolvedMessage, nodeId: nodeId, nodeType: nodeType)
        }

        // Time mode for calendar picker
        return .displayUI(.calendar(mode: .time, nodeId: nodeId))
    }
}

// MARK: - Ask Date Time Handler

/// Handler for ask_date_time nodes
/// Displays a calendar picker in dateTime mode and waits for user selection
public final class AskDateTimeHandler: BaseNodeHandler {

    public override var nodeType: String { NodeTypes.Display.askDateTime }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        let data = getNodeData(node)
        let nodeId = getNodeId(node) ?? UUID().uuidString

        // Extract custom message if provided
        if let message = data.flatMap({ getString($0, "message") ?? getString($0, "text") }) {
            let resolvedMessage = state.resolveVariables(text: message)
            state.addBotMessage(resolvedMessage, nodeId: nodeId, nodeType: nodeType)
        }

        // DateTime mode for calendar picker
        return .displayUI(.calendar(mode: .dateTime, nodeId: nodeId))
    }
}

// MARK: - Ask Date Range Handler

/// Handler for ask_date_range nodes
/// Displays a calendar picker in dateRange mode and waits for user selection
public final class AskDateRangeHandler: BaseNodeHandler {

    public override var nodeType: String { NodeTypes.Display.askDateRange }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        let data = getNodeData(node)
        let nodeId = getNodeId(node) ?? UUID().uuidString

        // Extract custom message if provided
        if let message = data.flatMap({ getString($0, "message") ?? getString($0, "text") }) {
            let resolvedMessage = state.resolveVariables(text: message)
            state.addBotMessage(resolvedMessage, nodeId: nodeId, nodeType: nodeType)
        }

        // DateRange mode for calendar picker
        return .displayUI(.calendar(mode: .dateRange, nodeId: nodeId))
    }
}

// MARK: - Ask File Upload Handler

/// Handler for ask_file_upload nodes
/// Displays a file upload interface with allowed types and waits for upload
public final class AskFileUploadHandler: BaseNodeHandler {

    public override var nodeType: String { NodeTypes.Display.askFileUpload }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        let data = getNodeData(node)
        let nodeId = getNodeId(node) ?? UUID().uuidString

        // Extract custom message if provided
        if let message = data.flatMap({ getString($0, "message") ?? getString($0, "text") }) {
            let resolvedMessage = state.resolveVariables(text: message)
            state.addBotMessage(resolvedMessage, nodeId: nodeId, nodeType: nodeType)
        }

        // Extract allowed file types
        var allowedTypes: [String] = ["*/*"] // Default to all types

        if let data = data {
            if let types = getStringArray(data, "allowedTypes") {
                allowedTypes = types
            } else if let types = getStringArray(data, "accept") {
                allowedTypes = types
            } else if let types = getStringArray(data, "fileTypes") {
                allowedTypes = types
            } else if let mimeType = getString(data, "mimeType") {
                allowedTypes = [mimeType]
            }
        }

        // Extract max file size (in bytes)
        var maxSize: Int? = nil
        if let data = data {
            maxSize = getInt(data, "maxSize")
                ?? getInt(data, "maxFileSize")
                ?? getInt(data, "sizeLimit")
        }

        return .displayUI(.fileUpload(allowedTypes: allowedTypes, maxSize: maxSize, nodeId: nodeId))
    }
}

// MARK: - Ask Question Handler

/// Handler for ask_question nodes
/// Displays a generic text input with optional validation and waits for input
public final class AskQuestionHandler: BaseNodeHandler {

    public override var nodeType: String { NodeTypes.Display.askQuestion }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        let data = getNodeData(node)
        let nodeId = getNodeId(node) ?? UUID().uuidString

        // Extract custom message/question if provided
        if let message = data.flatMap({ getString($0, "question") ?? getString($0, "message") ?? getString($0, "text") }) {
            let resolvedMessage = state.resolveVariables(text: message)
            state.addBotMessage(resolvedMessage, nodeId: nodeId, nodeType: nodeType)
        }

        // Extract placeholder or use default
        let placeholder = data.flatMap { getString($0, "placeholder") }
            ?? data.flatMap { getString($0, "inputPlaceholder") }
            ?? "Type your answer..."

        let resolvedPlaceholder = state.resolveVariables(text: placeholder)

        // Extract optional validation
        var validation: InputValidation? = nil
        if let data = data {
            if let validationType = getString(data, "validation") ?? getString(data, "validationType") {
                switch validationType.lowercased() {
                case "email":
                    validation = .email
                case "phone":
                    validation = .phone
                case "url":
                    validation = .url
                case "number":
                    validation = .number
                case "date":
                    validation = .date
                default:
                    // Check if it's a custom regex pattern
                    if let pattern = getString(data, "validationPattern") ?? getString(data, "regex") {
                        validation = .custom(pattern)
                    } else if !validationType.isEmpty {
                        validation = .custom(validationType)
                    }
                }
            }
        }

        return .displayUI(.textInput(placeholder: resolvedPlaceholder, validation: validation, nodeId: nodeId))
    }
}

// MARK: - Send Buttons Handler

/// Handler for send_buttons nodes
/// Displays action buttons with labels and optional URLs/actions
public final class SendButtonsHandler: BaseNodeHandler {

    public override var nodeType: String { NodeTypes.Display.sendButtons }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("Send buttons node missing data")
        }

        let nodeId = getNodeId(node) ?? UUID().uuidString

        // Extract message to display with buttons
        if let message = getString(data, "message") ?? getString(data, "text") {
            let resolvedMessage = state.resolveVariables(text: message)
            state.addBotMessage(resolvedMessage, nodeId: nodeId, nodeType: nodeType)
        }

        // Extract buttons array
        guard let buttonDicts = getArray(data, "buttons")
            ?? getArray(data, "options")
            ?? getArray(data, "actions") else {
            return .error("Send buttons node missing buttons array")
        }

        // Parse buttons with variable resolution
        var buttons: [ButtonOption] = []
        for dict in buttonDicts {
            let id = getString(dict, "id") ?? UUID().uuidString
            let rawLabel = getString(dict, "label") ?? getString(dict, "text") ?? ""
            let label = state.resolveVariables(text: rawLabel)

            var url: String? = nil
            if let rawUrl = getString(dict, "url") ?? getString(dict, "href") {
                url = state.resolveVariables(text: rawUrl)
            }

            let action = getString(dict, "action") ?? getString(dict, "type")

            buttons.append(ButtonOption(id: id, label: label, url: url, action: action))
        }

        return .displayUI(.buttons(buttons: buttons, nodeId: nodeId))
    }
}

// MARK: - Send Quick Replies Handler

/// Handler for send_quick_replies nodes
/// Displays quick reply options as chips/pills
public final class SendQuickRepliesHandler: BaseNodeHandler {

    public override var nodeType: String { NodeTypes.Display.sendQuickReplies }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("Send quick replies node missing data")
        }

        let nodeId = getNodeId(node) ?? UUID().uuidString

        // Extract message to display with quick replies
        if let message = getString(data, "message") ?? getString(data, "text") {
            let resolvedMessage = state.resolveVariables(text: message)
            state.addBotMessage(resolvedMessage, nodeId: nodeId, nodeType: nodeType)
        }

        // Extract quick replies array
        guard let optionDicts = getArray(data, "quickReplies")
            ?? getArray(data, "replies")
            ?? getArray(data, "options") else {
            return .error("Send quick replies node missing options array")
        }

        // Parse options with variable resolution
        var options: [ChoiceOption] = []
        for dict in optionDicts {
            let id = getString(dict, "id") ?? UUID().uuidString
            let rawLabel = getString(dict, "label") ?? getString(dict, "text") ?? ""
            let label = state.resolveVariables(text: rawLabel)

            let rawValue = getString(dict, "value") ?? label
            let value = state.resolveVariables(text: rawValue)

            let imageUrl = getString(dict, "imageUrl") ?? getString(dict, "image")

            options.append(ChoiceOption(id: id, label: label, value: value, imageUrl: imageUrl))
        }

        return .displayUI(.quickReplies(options: options, nodeId: nodeId))
    }
}

// MARK: - Send Cards Handler

/// Handler for send_cards nodes
/// Displays a carousel of cards with title, subtitle, image, and buttons
public final class SendCardsHandler: BaseNodeHandler {

    public override var nodeType: String { NodeTypes.Display.sendCards }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("Send cards node missing data")
        }

        let nodeId = getNodeId(node) ?? UUID().uuidString

        // Extract cards array
        guard let cardDicts = getArray(data, "cards")
            ?? getArray(data, "items")
            ?? getArray(data, "carousel") else {
            return .error("Send cards node missing cards array")
        }

        // Parse cards with variable resolution
        var cards: [CardData] = []
        for dict in cardDicts {
            let id = getString(dict, "id") ?? UUID().uuidString

            let rawTitle = getString(dict, "title") ?? ""
            let title = state.resolveVariables(text: rawTitle)

            var subtitle: String? = nil
            if let rawSubtitle = getString(dict, "subtitle") ?? getString(dict, "description") {
                subtitle = state.resolveVariables(text: rawSubtitle)
            }

            var imageUrl: String? = nil
            if let rawImageUrl = getString(dict, "imageUrl") ?? getString(dict, "image") ?? getString(dict, "img") {
                imageUrl = state.resolveVariables(text: rawImageUrl)
            }

            // Parse card buttons
            var buttons: [ButtonOption] = []
            if let buttonDicts = getArray(dict, "buttons") ?? getArray(dict, "actions") {
                for buttonDict in buttonDicts {
                    let buttonId = getString(buttonDict, "id") ?? UUID().uuidString
                    let rawLabel = getString(buttonDict, "label") ?? getString(buttonDict, "text") ?? ""
                    let buttonLabel = state.resolveVariables(text: rawLabel)

                    var buttonUrl: String? = nil
                    if let rawUrl = getString(buttonDict, "url") ?? getString(buttonDict, "href") {
                        buttonUrl = state.resolveVariables(text: rawUrl)
                    }

                    let buttonAction = getString(buttonDict, "action") ?? getString(buttonDict, "type")

                    buttons.append(ButtonOption(id: buttonId, label: buttonLabel, url: buttonUrl, action: buttonAction))
                }
            }

            cards.append(CardData(id: id, title: title, subtitle: subtitle, imageUrl: imageUrl, buttons: buttons))
        }

        return .displayUI(.cards(cards: cards, nodeId: nodeId))
    }
}

// MARK: - Ask Rating Handler

/// Handler for ask_rating nodes
/// Displays a rating input with configurable max and style
public final class AskRatingHandler: BaseNodeHandler {

    public override var nodeType: String { NodeTypes.Display.askRating }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        let data = getNodeData(node)
        let nodeId = getNodeId(node) ?? UUID().uuidString

        // Extract custom message if provided
        if let message = data.flatMap({ getString($0, "message") ?? getString($0, "text") }) {
            let resolvedMessage = state.resolveVariables(text: message)
            state.addBotMessage(resolvedMessage, nodeId: nodeId, nodeType: nodeType)
        }

        // Extract max rating (default 5)
        let maxRating = data.flatMap { getInt($0, "maxRating") ?? getInt($0, "max") ?? getInt($0, "scale") } ?? 5

        // Extract rating style (default stars)
        var style: RatingStyle = .stars
        if let styleString = data.flatMap({ getString($0, "style") ?? getString($0, "ratingStyle") ?? getString($0, "type") }) {
            switch styleString.lowercased() {
            case "stars", "star":
                style = .stars
            case "hearts", "heart":
                style = .hearts
            case "thumbs", "thumb":
                style = .thumbs
            case "emojis", "emoji":
                style = .emojis
            default:
                style = .stars
            }
        }

        return .displayUI(.rating(max: maxRating, style: style, nodeId: nodeId))
    }
}

// MARK: - Opinion Scale Handler

/// Handler for opinion_scale nodes
/// Displays an NPS-style scale with configurable min/max and labels
public final class OpinionScaleHandler: BaseNodeHandler {

    public override var nodeType: String { NodeTypes.Display.opinionScale }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        let data = getNodeData(node)
        let nodeId = getNodeId(node) ?? UUID().uuidString

        // Extract custom message if provided
        if let message = data.flatMap({ getString($0, "message") ?? getString($0, "text") ?? getString($0, "question") }) {
            let resolvedMessage = state.resolveVariables(text: message)
            state.addBotMessage(resolvedMessage, nodeId: nodeId, nodeType: nodeType)
        }

        // Extract min value (default 0 or 1)
        let min = data.flatMap { getInt($0, "min") ?? getInt($0, "minValue") ?? getInt($0, "start") } ?? 0

        // Extract max value (default 10)
        let max = data.flatMap { getInt($0, "max") ?? getInt($0, "maxValue") ?? getInt($0, "end") } ?? 10

        // Extract labels
        var minLabel: String? = nil
        if let rawMinLabel = data.flatMap({ getString($0, "minLabel") ?? getString($0, "leftLabel") ?? getString($0, "lowLabel") }) {
            minLabel = state.resolveVariables(text: rawMinLabel)
        }

        var maxLabel: String? = nil
        if let rawMaxLabel = data.flatMap({ getString($0, "maxLabel") ?? getString($0, "rightLabel") ?? getString($0, "highLabel") }) {
            maxLabel = state.resolveVariables(text: rawMaxLabel)
        }

        return .displayUI(.opinionScale(min: min, max: max, minLabel: minLabel, maxLabel: maxLabel, nodeId: nodeId))
    }
}

// MARK: - Live Chat Handler

/// Handler for live_chat nodes
/// Initiates human handover/live chat request
public final class LiveChatHandler: BaseNodeHandler {

    public override var nodeType: String { NodeTypes.Display.liveChat }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        let data = getNodeData(node)
        let nodeId = getNodeId(node)

        // Extract message to display
        var message: String? = nil
        if let rawMessage = data.flatMap({ getString($0, "message") ?? getString($0, "text") }) {
            message = state.resolveVariables(text: rawMessage)
        }

        // Add to transcript
        if let msg = message {
            state.addBotMessage(msg, nodeId: nodeId, nodeType: nodeType)
        }

        return .displayUI(.liveChat(message: message))
    }
}

// MARK: - Send Link Handler

/// Handler for send_link nodes
/// Displays a clickable link with optional text
public final class SendLinkHandler: BaseNodeHandler {

    public override var nodeType: String { NodeTypes.Display.sendLink }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("Send link node missing data")
        }

        let nodeId = getNodeId(node)

        // Extract URL
        guard let rawUrl = getString(data, "url")
            ?? getString(data, "href")
            ?? getString(data, "link") else {
            return .error("Send link node missing URL")
        }

        let resolvedUrl = state.resolveVariables(text: rawUrl)

        // Extract link text
        var linkText: String? = nil
        if let rawText = getString(data, "linkText")
            ?? getString(data, "text")
            ?? getString(data, "label")
            ?? getString(data, "title") {
            linkText = state.resolveVariables(text: rawText)
        }

        // Add to transcript
        state.addBotMessage("[Link: \(linkText ?? resolvedUrl)]", nodeId: nodeId, nodeType: nodeType)

        return .displayUI(.link(url: resolvedUrl, text: linkText))
    }
}

// MARK: - Embed Link Handler

/// Handler for embed_link nodes
/// Converts a URL to an embedded iframe
public final class EmbedLinkHandler: BaseNodeHandler {

    public override var nodeType: String { NodeTypes.Display.embedLink }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("Embed link node missing data")
        }

        let nodeId = getNodeId(node)

        // Extract embed URL
        guard let rawUrl = getString(data, "embedUrl")
            ?? getString(data, "url")
            ?? getString(data, "src") else {
            return .error("Embed link node missing embed URL")
        }

        let resolvedUrl = state.resolveVariables(text: rawUrl)

        // Extract dimensions
        let width = getString(data, "width") ?? "100%"
        let height = getString(data, "height") ?? "400"

        // Extract optional title for iframe
        let title = getString(data, "title") ?? "Embedded content"

        // Convert to iframe HTML
        let iframeHtml = """
        <iframe
            src="\(resolvedUrl)"
            width="\(width)"
            height="\(height)"
            title="\(title)"
            frameborder="0"
            allowfullscreen
            style="border: none; border-radius: 8px;">
        </iframe>
        """

        // Add to transcript
        state.addBotMessage("[Embedded: \(resolvedUrl)]", nodeId: nodeId, nodeType: nodeType)

        return .displayUI(.embed(html: iframeHtml))
    }
}

// MARK: - Embed Custom Code Handler

/// Handler for embed_custom_code nodes
/// Embeds custom HTML/CSS/JS code
public final class EmbedCustomCodeHandler: BaseNodeHandler {

    public override var nodeType: String { NodeTypes.Display.embedCustomCode }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("Embed custom code node missing data")
        }

        let nodeId = getNodeId(node)

        // Extract HTML code
        guard let rawHtml = getString(data, "htmlCode")
            ?? getString(data, "html")
            ?? getString(data, "code")
            ?? getString(data, "content") else {
            return .error("Embed custom code node missing HTML code")
        }

        // Resolve any variables in the HTML
        let resolvedHtml = state.resolveVariables(text: rawHtml)

        // Add to transcript
        state.addBotMessage("[Custom Embed]", nodeId: nodeId, nodeType: nodeType)

        return .displayUI(.embed(html: resolvedHtml))
    }
}

// MARK: - Handler Registration Extension

public extension NodeHandlerRegistry {

    /// Registers all display node handlers
    func registerDisplayHandlers() {
        // Send nodes (display then proceed)
        register(SendMessageHandler())
        register(SendImageHandler())
        register(SendVideoHandler())
        register(SendAudioHandler())
        register(SendFileHandler())
        register(SendGifHandler())

        // Also register handlers for legacy node types
        registerWithAlias(SendMessageHandler(), aliases: SendMessageHandler.additionalTypes)
        registerWithAlias(SendImageHandler(), aliases: SendImageHandler.additionalTypes)

        // Ask nodes (display and wait for input)
        register(AskNameHandler())
        register(AskEmailHandler())
        register(AskPhoneHandler())
        register(AskNumberHandler())
        register(AskUrlHandler())
        register(AskAddressHandler())
        register(AskDateHandler())
        register(AskTimeHandler())
        register(AskDateTimeHandler())
        register(AskDateRangeHandler())
        register(AskFileUploadHandler())
        register(AskQuestionHandler())

        // Choice nodes
        register(SendButtonsHandler())
        register(SendQuickRepliesHandler())
        register(SendCardsHandler())

        // Rating nodes
        register(AskRatingHandler())
        register(OpinionScaleHandler())

        // Special display nodes
        register(LiveChatHandler())
        register(SendLinkHandler())
        register(EmbedLinkHandler())
        register(EmbedCustomCodeHandler())
    }

    /// Helper method to register a handler with additional type aliases
    private func registerWithAlias(_ handler: NodeHandler, aliases: [String]) {
        for alias in aliases {
            // Create an alias handler wrapper
            let aliasHandler = AliasNodeHandler(wrapping: handler, forType: alias)
            register(aliasHandler)
        }
    }
}

// MARK: - Alias Node Handler

/// Wrapper handler that allows a handler to respond to multiple node types
private final class AliasNodeHandler: BaseNodeHandler {

    private let wrappedHandler: NodeHandler
    private let aliasType: String

    public override var nodeType: String { aliasType }

    init(wrapping handler: NodeHandler, forType type: String) {
        self.wrappedHandler = handler
        self.aliasType = type
        super.init()
    }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        return await wrappedHandler.handle(node: node, state: state)
    }
}

// MARK: - Display Handler Registry

/// Convenience registry for display handlers only
public final class DisplayHandlerRegistry {

    /// Shared singleton instance
    public static let shared = DisplayHandlerRegistry()

    /// Map of node types to handlers
    private var handlers: [String: NodeHandler] = [:]

    private init() {
        registerDefaultHandlers()
    }

    /// Register default display handlers
    private func registerDefaultHandlers() {
        // Send nodes
        registerHandler(SendMessageHandler())
        registerHandler(SendImageHandler())
        registerHandler(SendVideoHandler())
        registerHandler(SendAudioHandler())
        registerHandler(SendFileHandler())
        registerHandler(SendGifHandler())

        // Legacy types
        handlers[NodeTypes.Display.text] = SendMessageHandler()
        handlers[NodeTypes.Display.image] = SendImageHandler()

        // Ask nodes
        registerHandler(AskNameHandler())
        registerHandler(AskEmailHandler())
        registerHandler(AskPhoneHandler())
        registerHandler(AskNumberHandler())
        registerHandler(AskUrlHandler())
        registerHandler(AskAddressHandler())
        registerHandler(AskDateHandler())
        registerHandler(AskTimeHandler())
        registerHandler(AskDateTimeHandler())
        registerHandler(AskDateRangeHandler())
        registerHandler(AskFileUploadHandler())
        registerHandler(AskQuestionHandler())

        // Choice nodes
        registerHandler(SendButtonsHandler())
        registerHandler(SendQuickRepliesHandler())
        registerHandler(SendCardsHandler())

        // Rating nodes
        registerHandler(AskRatingHandler())
        registerHandler(OpinionScaleHandler())

        // Special display
        registerHandler(LiveChatHandler())
        registerHandler(SendLinkHandler())
        registerHandler(EmbedLinkHandler())
        registerHandler(EmbedCustomCodeHandler())
    }

    /// Register a handler
    private func registerHandler(_ handler: NodeHandler) {
        handlers[handler.nodeType] = handler
    }

    /// Get handler for a node type
    public func handler(for nodeType: String) -> NodeHandler? {
        return handlers[nodeType]
    }

    /// Check if a handler exists for a node type
    public func hasHandler(for nodeType: String) -> Bool {
        return handlers[nodeType] != nil
    }

    /// Handle a display node
    public func handleNode(
        nodeType: String,
        node: [String: Any],
        state: ChatState
    ) async -> NodeResult {
        guard let handler = handler(for: nodeType) else {
            return .error("No display handler registered for node type: \(nodeType)")
        }

        return await handler.handle(node: node, state: state)
    }

    /// Get all registered node types
    public var registeredNodeTypes: [String] {
        return Array(handlers.keys)
    }

    /// Get count of registered handlers
    public var count: Int {
        return handlers.count
    }
}
