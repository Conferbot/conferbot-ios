//
//  NodeTypes.swift
//  Conferbot
//
//  Defines all 51 node types supported by the Conferbot SDK,
//  organized by category with helper functions for type checking.
//

import Foundation

// MARK: - Node Type Constants

/// All node types supported by Conferbot, organized by category
public enum NodeTypes {

    // MARK: - Display Nodes (28 types)

    /// Display nodes that show content or collect user input
    public enum Display {

        // MARK: Message Nodes

        /// Sends a text message to the user
        public static let sendMessage = "send_message"

        /// Sends an image to the user
        public static let sendImage = "send_image"

        /// Sends a video to the user
        public static let sendVideo = "send_video"

        /// Sends an audio file to the user
        public static let sendAudio = "send_audio"

        /// Sends a file to the user
        public static let sendFile = "send_file"

        /// Sends a GIF to the user
        public static let sendGif = "send_gif"

        // MARK: Input Collection Nodes

        /// Asks for the user's name
        public static let askName = "ask_name"

        /// Asks for the user's email address
        public static let askEmail = "ask_email"

        /// Asks for the user's phone number
        public static let askPhone = "ask_phone"

        /// Asks for a numeric value
        public static let askNumber = "ask_number"

        /// Asks for a URL
        public static let askUrl = "ask_url"

        /// Asks for an address
        public static let askAddress = "ask_address"

        /// Asks for a date
        public static let askDate = "ask_date"

        /// Asks for a time
        public static let askTime = "ask_time"

        /// Asks for a date and time
        public static let askDateTime = "ask_date_time"

        /// Asks for a date range
        public static let askDateRange = "ask_date_range"

        /// Asks user to upload a file
        public static let askFileUpload = "ask_file_upload"

        /// Asks a general question
        public static let askQuestion = "ask_question"

        // MARK: Interactive Nodes

        /// Displays buttons for user selection
        public static let sendButtons = "send_buttons"

        /// Displays quick reply options
        public static let sendQuickReplies = "send_quick_replies"

        /// Displays cards/carousel for selection
        public static let sendCards = "send_cards"

        /// Asks user for a rating
        public static let askRating = "ask_rating"

        /// Displays an opinion scale (NPS-style)
        public static let opinionScale = "opinion_scale"

        // MARK: Communication Nodes

        /// Initiates live chat with human agent
        public static let liveChat = "live_chat"

        // MARK: Embed Nodes

        /// Sends a clickable link
        public static let sendLink = "send_link"

        /// Embeds a link (iframe)
        public static let embedLink = "embed_link"

        /// Embeds custom HTML/JS code
        public static let embedCustomCode = "embed_custom_code"

        // MARK: Legacy Nodes

        /// Legacy text node type
        public static let text = "TEXT"

        /// Legacy image node type
        public static let image = "IMAGE"

        /// All display node types
        public static let allTypes: Set<String> = [
            sendMessage, sendImage, sendVideo, sendAudio, sendFile, sendGif,
            askName, askEmail, askPhone, askNumber, askUrl, askAddress,
            askDate, askTime, askDateTime, askDateRange, askFileUpload, askQuestion,
            sendButtons, sendQuickReplies, sendCards, askRating, opinionScale,
            liveChat,
            sendLink, embedLink, embedCustomCode,
            text, image
        ]

        /// Node types that require user interaction
        public static let interactiveTypes: Set<String> = [
            askName, askEmail, askPhone, askNumber, askUrl, askAddress,
            askDate, askTime, askDateTime, askDateRange, askFileUpload, askQuestion,
            sendButtons, sendQuickReplies, sendCards, askRating, opinionScale,
            liveChat
        ]

        /// Node types that only display content (no user input)
        public static let displayOnlyTypes: Set<String> = [
            sendMessage, sendImage, sendVideo, sendAudio, sendFile, sendGif,
            sendLink, embedLink, embedCustomCode,
            text, image
        ]
    }

    // MARK: - Logic Nodes (7 types)

    /// Logic nodes that control conversation flow
    public enum Logic {

        /// Redirects user to a URL
        public static let redirectUrl = "redirect_url"

        /// Sets a variable value
        public static let setVariable = "set_variable"

        /// Executes a JavaScript function
        public static let javascriptFunction = "javascript_function"

        /// Conditional branching based on conditions
        public static let conditional = "conditional"

        /// A/B testing node for split testing
        public static let abTest = "ab_test"

        /// Splits conversation into multiple paths
        public static let splitConversation = "split_conversation"

        /// Adds a delay before proceeding
        public static let delay = "delay"

        /// All logic node types
        public static let allTypes: Set<String> = [
            redirectUrl, setVariable, javascriptFunction,
            conditional, abTest, splitConversation, delay
        ]
    }

    // MARK: - Integration Nodes (17 types)

    /// Integration nodes that connect to external services
    public enum Integration {

        // MARK: Web & Data Integrations

        /// Makes a webhook/HTTP request
        public static let webhook = "webhook"

        /// Integrates with Google Sheets
        public static let googleSheets = "google_sheets"

        /// Sends an email
        public static let sendEmail = "send_email"

        // MARK: CRM & Business Integrations

        /// Integrates with Calendly for scheduling
        public static let calendly = "calendly"

        /// Integrates with HubSpot CRM
        public static let hubspot = "hubspot"

        /// Integrates with Salesforce CRM
        public static let salesforce = "salesforce"

        /// Integrates with Zendesk support
        public static let zendesk = "zendesk"

        /// Integrates with Slack messaging
        public static let slack = "slack"

        /// Integrates with Zapier automation
        public static let zapier = "zapier"

        // MARK: AI & NLP Integrations

        /// Integrates with Google Dialogflow
        public static let dialogflow = "dialogflow"

        /// Integrates with OpenAI (GPT)
        public static let openai = "openai"

        /// Integrates with Google Gemini
        public static let gemini = "gemini"

        /// Integrates with Perplexity AI
        public static let perplexity = "perplexity"

        /// Integrates with Anthropic Claude
        public static let claude = "claude"

        /// Integrates with Groq
        public static let groq = "groq"

        /// Integrates with custom LLM endpoints
        public static let customLlm = "custom_llm"

        // MARK: Support Integrations

        /// Hands over to human agent
        public static let humanHandover = "human_handover"

        /// All integration node types
        public static let allTypes: Set<String> = [
            webhook, googleSheets, sendEmail,
            calendly, hubspot, salesforce, zendesk, slack, zapier,
            dialogflow, openai, gemini, perplexity, claude, groq, customLlm,
            humanHandover
        ]

        /// AI/LLM integration types
        public static let aiTypes: Set<String> = [
            dialogflow, openai, gemini, perplexity, claude, groq, customLlm
        ]

        /// CRM integration types
        public static let crmTypes: Set<String> = [
            hubspot, salesforce, zendesk
        ]
    }

    // MARK: - Special Flow Nodes (2 types)

    /// Special nodes for flow control
    public enum Flow {

        /// Marks a conversion goal
        public static let goal = "goal"

        /// Ends the conversation
        public static let endConversation = "end_conversation"

        /// All flow node types
        public static let allTypes: Set<String> = [
            goal, endConversation
        ]
    }

    // MARK: - All Types Combined

    /// All 51 node types
    public static let allTypes: Set<String> = {
        var types = Set<String>()
        types.formUnion(Display.allTypes)
        types.formUnion(Logic.allTypes)
        types.formUnion(Integration.allTypes)
        types.formUnion(Flow.allTypes)
        return types
    }()
}

// MARK: - Helper Functions

/// Checks if a node type is a display node
/// - Parameter type: The node type string
/// - Returns: True if the node is a display node
public func isDisplayNode(_ type: String) -> Bool {
    return NodeTypes.Display.allTypes.contains(type)
}

/// Checks if a node type is a logic node
/// - Parameter type: The node type string
/// - Returns: True if the node is a logic node
public func isLogicNode(_ type: String) -> Bool {
    return NodeTypes.Logic.allTypes.contains(type)
}

/// Checks if a node type is an integration node
/// - Parameter type: The node type string
/// - Returns: True if the node is an integration node
public func isIntegrationNode(_ type: String) -> Bool {
    return NodeTypes.Integration.allTypes.contains(type)
}

/// Checks if a node type is a flow control node
/// - Parameter type: The node type string
/// - Returns: True if the node is a flow control node
public func isFlowNode(_ type: String) -> Bool {
    return NodeTypes.Flow.allTypes.contains(type)
}

/// Checks if a node type requires user interaction
/// - Parameter type: The node type string
/// - Returns: True if the node requires user input
public func requiresUserInteraction(_ type: String) -> Bool {
    return NodeTypes.Display.interactiveTypes.contains(type)
}

/// Checks if a node type is display-only (no user input)
/// - Parameter type: The node type string
/// - Returns: True if the node only displays content
public func isDisplayOnly(_ type: String) -> Bool {
    return NodeTypes.Display.displayOnlyTypes.contains(type)
}

/// Checks if a node type is an AI/LLM integration
/// - Parameter type: The node type string
/// - Returns: True if the node is an AI integration
public func isAINode(_ type: String) -> Bool {
    return NodeTypes.Integration.aiTypes.contains(type)
}

/// Checks if a node type is a CRM integration
/// - Parameter type: The node type string
/// - Returns: True if the node is a CRM integration
public func isCRMNode(_ type: String) -> Bool {
    return NodeTypes.Integration.crmTypes.contains(type)
}

// MARK: - Node Type Utilities

/// Utility struct for working with node types
public struct NodeTypeUtils {

    /// Returns the category of a node type
    /// - Parameter type: The node type string
    /// - Returns: The category name
    public static func category(for type: String) -> String {
        if isDisplayNode(type) { return "display" }
        if isLogicNode(type) { return "logic" }
        if isIntegrationNode(type) { return "integration" }
        if isFlowNode(type) { return "flow" }
        return "unknown"
    }

    /// Checks if a node type is valid
    /// - Parameter type: The node type string
    /// - Returns: True if the node type is recognized
    public static func isValid(_ type: String) -> Bool {
        return NodeTypes.allTypes.contains(type)
    }

    /// Returns a human-readable name for a node type
    /// - Parameter type: The node type string
    /// - Returns: A formatted display name
    public static func displayName(for type: String) -> String {
        return type
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    /// Maps legacy node types to modern equivalents
    /// - Parameter type: The legacy node type
    /// - Returns: The modern node type, or the original if not a legacy type
    public static func modernType(for type: String) -> String {
        switch type {
        case NodeTypes.Display.text:
            return NodeTypes.Display.sendMessage
        case NodeTypes.Display.image:
            return NodeTypes.Display.sendImage
        default:
            return type
        }
    }
}

// MARK: - Node Type Constants (Flat Access)

/// Provides flat access to all node type constants for convenience
public struct NodeType {

    // MARK: Display Nodes
    public static let sendMessage = NodeTypes.Display.sendMessage
    public static let sendImage = NodeTypes.Display.sendImage
    public static let sendVideo = NodeTypes.Display.sendVideo
    public static let sendAudio = NodeTypes.Display.sendAudio
    public static let sendFile = NodeTypes.Display.sendFile
    public static let sendGif = NodeTypes.Display.sendGif
    public static let askName = NodeTypes.Display.askName
    public static let askEmail = NodeTypes.Display.askEmail
    public static let askPhone = NodeTypes.Display.askPhone
    public static let askNumber = NodeTypes.Display.askNumber
    public static let askUrl = NodeTypes.Display.askUrl
    public static let askAddress = NodeTypes.Display.askAddress
    public static let askDate = NodeTypes.Display.askDate
    public static let askTime = NodeTypes.Display.askTime
    public static let askDateTime = NodeTypes.Display.askDateTime
    public static let askDateRange = NodeTypes.Display.askDateRange
    public static let askFileUpload = NodeTypes.Display.askFileUpload
    public static let askQuestion = NodeTypes.Display.askQuestion
    public static let sendButtons = NodeTypes.Display.sendButtons
    public static let sendQuickReplies = NodeTypes.Display.sendQuickReplies
    public static let sendCards = NodeTypes.Display.sendCards
    public static let askRating = NodeTypes.Display.askRating
    public static let opinionScale = NodeTypes.Display.opinionScale
    public static let liveChat = NodeTypes.Display.liveChat
    public static let sendLink = NodeTypes.Display.sendLink
    public static let embedLink = NodeTypes.Display.embedLink
    public static let embedCustomCode = NodeTypes.Display.embedCustomCode
    public static let text = NodeTypes.Display.text
    public static let image = NodeTypes.Display.image

    // MARK: Logic Nodes
    public static let redirectUrl = NodeTypes.Logic.redirectUrl
    public static let setVariable = NodeTypes.Logic.setVariable
    public static let javascriptFunction = NodeTypes.Logic.javascriptFunction
    public static let conditional = NodeTypes.Logic.conditional
    public static let abTest = NodeTypes.Logic.abTest
    public static let splitConversation = NodeTypes.Logic.splitConversation
    public static let delay = NodeTypes.Logic.delay

    // MARK: Integration Nodes
    public static let webhook = NodeTypes.Integration.webhook
    public static let googleSheets = NodeTypes.Integration.googleSheets
    public static let sendEmail = NodeTypes.Integration.sendEmail
    public static let calendly = NodeTypes.Integration.calendly
    public static let hubspot = NodeTypes.Integration.hubspot
    public static let salesforce = NodeTypes.Integration.salesforce
    public static let zendesk = NodeTypes.Integration.zendesk
    public static let slack = NodeTypes.Integration.slack
    public static let zapier = NodeTypes.Integration.zapier
    public static let dialogflow = NodeTypes.Integration.dialogflow
    public static let openai = NodeTypes.Integration.openai
    public static let gemini = NodeTypes.Integration.gemini
    public static let perplexity = NodeTypes.Integration.perplexity
    public static let claude = NodeTypes.Integration.claude
    public static let groq = NodeTypes.Integration.groq
    public static let customLlm = NodeTypes.Integration.customLlm
    public static let humanHandover = NodeTypes.Integration.humanHandover

    // MARK: Flow Nodes
    public static let goal = NodeTypes.Flow.goal
    public static let endConversation = NodeTypes.Flow.endConversation
}
