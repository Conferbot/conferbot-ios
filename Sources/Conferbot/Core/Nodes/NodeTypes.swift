//
//  NodeTypes.swift
//  Conferbot
//
//  Defines all 58 node types supported by the Conferbot SDK,
//  organized by category with helper functions for type checking.
//  All type strings match the server's kebab-case-node format.
//

import Foundation

// MARK: - Node Type Constants

/// All node types supported by Conferbot, organized by category.
/// Type strings match the server format exactly (kebab-case with -node suffix).
public enum NodeTypes {

    // MARK: - Display Nodes (32 types)

    /// Display nodes that show content or collect user input
    public enum Display {

        // MARK: Legacy Nodes (v1)

        /// Legacy: 2 choice buttons with port-based routing
        public static let twoChoices = "two-choices-node"

        /// Legacy: 3 choice buttons with port-based routing
        public static let threeChoices = "three-choices-node"

        /// Legacy: Dropdown select (up to 5 options)
        public static let selectOption = "select-option-node"

        /// Legacy: 5-star rating
        public static let userRating = "user-rating-node"

        /// Legacy: Multi-purpose input (name/email/number/url/phone/file/date)
        public static let userInput = "user-input-node"

        /// Legacy: Range slider
        public static let userRange = "user-range-node"

        /// Legacy: Quiz with correct/incorrect branching
        public static let quiz = "quiz-node"

        // MARK: Send Nodes (display content, then proceed)

        /// Sends a text message to the user
        public static let sendMessage = "message-node"

        /// Sends an image to the user
        public static let sendImage = "image-node"

        /// Sends a video to the user
        public static let sendVideo = "video-node"

        /// Sends an audio file to the user
        public static let sendAudio = "audio-node"

        /// Sends a file to the user
        public static let sendFile = "file-node"

        // MARK: Ask Nodes (display and wait for input)

        /// Asks for the user's name
        public static let askName = "ask-name-node"

        /// Asks for the user's email address
        public static let askEmail = "ask-email-node"

        /// Asks for the user's phone number
        public static let askPhone = "ask-phone-number-node"

        /// Asks for a numeric value
        public static let askNumber = "ask-number-node"

        /// Asks for a URL
        public static let askUrl = "ask-url-node"

        /// Asks for a location/address
        public static let askLocation = "ask-location-node"

        /// Asks a custom question
        public static let askCustomQuestion = "ask-custom-question-node"

        /// Asks user to upload a file
        public static let askFile = "ask-file-node"

        /// Asks multiple questions in sequence
        public static let askMultipleQuestions = "ask-multiple-questions-node"

        /// Calendar/date picker
        public static let calendar = "calendar-node"

        /// Dynamic dropdown with N options
        public static let nSelectOption = "n-select-option-node"

        /// Multi-checkbox selection
        public static let nCheckOptions = "n-check-options-node"

        // MARK: Choice Nodes (display choices, port-based routing)

        /// N dynamic choice buttons
        public static let nChoices = "n-choices-node"

        /// Image grid selection
        public static let imageChoice = "image-choice-node"

        /// Rating selector (smiley, 5-star, 10-point)
        public static let ratingChoice = "rating-choice-node"

        /// Binary yes/no choice
        public static let yesOrNoChoice = "yes-or-no-choice-node"

        /// NPS-style opinion scale
        public static let opinionScaleChoice = "opinion-scale-choice-node"

        // MARK: Special Display Nodes

        /// Redirects user to external URL
        public static let userRedirect = "user-redirect-node"

        /// Displays HTML content
        public static let html = "html-node"

        /// In-app navigation / internal redirect
        public static let navigate = "navigate-node"

        /// All display node types
        public static let allTypes: Set<String> = [
            // Legacy
            twoChoices, threeChoices, selectOption, userRating, userInput, userRange, quiz,
            // Send
            sendMessage, sendImage, sendVideo, sendAudio, sendFile,
            // Ask
            askName, askEmail, askPhone, askNumber, askUrl, askLocation,
            askCustomQuestion, askFile, askMultipleQuestions, calendar,
            nSelectOption, nCheckOptions,
            // Choices
            nChoices, imageChoice, ratingChoice, yesOrNoChoice, opinionScaleChoice,
            // Special
            userRedirect, html, navigate
        ]

        /// Node types that require user interaction
        public static let interactiveTypes: Set<String> = [
            // Legacy
            twoChoices, threeChoices, selectOption, userRating, userInput, userRange, quiz,
            // Ask
            askName, askEmail, askPhone, askNumber, askUrl, askLocation,
            askCustomQuestion, askFile, askMultipleQuestions, calendar,
            nSelectOption, nCheckOptions,
            // Choices
            nChoices, imageChoice, ratingChoice, yesOrNoChoice, opinionScaleChoice
        ]

        /// Node types that only display content (no user input)
        public static let displayOnlyTypes: Set<String> = [
            sendMessage, sendImage, sendVideo, sendAudio, sendFile,
            userRedirect, html, navigate
        ]
    }

    // MARK: - Logic Nodes (7 types)

    /// Logic nodes that control conversation flow
    public enum Logic {

        /// Conditional branching based on conditions
        public static let condition = "condition-node"

        /// Boolean logic (AND/OR/NOT/XOR/NAND/NOR/XNOR)
        public static let booleanLogic = "boolean-logic-node"

        /// Random flow routing based on weights
        public static let randomFlow = "random-flow-node"

        /// Math operations (+,-,*,/,%)
        public static let mathOperation = "math-operation-node"

        /// Create/update variables
        public static let variable = "variable-node"

        /// Jump to a specific node by ID
        public static let jumpTo = "jump-to-node"

        /// Time-based routing with business hours
        public static let businessHours = "business-hours-node"

        /// All logic node types
        public static let allTypes: Set<String> = [
            condition, booleanLogic, randomFlow, mathOperation,
            variable, jumpTo, businessHours
        ]
    }

    // MARK: - Integration Nodes (17 types)

    /// Integration nodes that connect to external services
    public enum Integration {

        /// Sends an email
        public static let email = "email-node"

        /// Makes a webhook/HTTP request
        public static let webhook = "webhook-node"

        /// AI/GPT integration
        public static let gpt = "gpt-node"

        /// Zapier automation
        public static let zapier = "zapier-node"

        /// Google Sheets integration
        public static let googleSheets = "google-sheets-node"

        /// Gmail integration
        public static let gmail = "gmail-node"

        /// Google Calendar integration
        public static let googleCalendar = "google-calendar-node"

        /// Google Meet integration
        public static let googleMeet = "google-meet-node"

        /// Google Drive integration
        public static let googleDrive = "google-drive-node"

        /// Google Docs integration
        public static let googleDocs = "google-docs-node"

        /// Slack messaging integration
        public static let slack = "slack-node"

        /// Discord messaging integration
        public static let discord = "discord-node"

        /// Airtable integration
        public static let airtable = "airtable-node"

        /// HubSpot CRM integration
        public static let hubspot = "hubspot-node"

        /// Notion integration
        public static let notion = "notion-node"

        /// Zoho CRM integration
        public static let zohoCrm = "zohocrm-node"

        /// Stripe payment integration
        public static let stripe = "stripe-node"

        /// All integration node types
        public static let allTypes: Set<String> = [
            email, webhook, gpt, zapier, googleSheets, gmail,
            googleCalendar, googleMeet, googleDrive, googleDocs,
            slack, discord, airtable, hubspot, notion, zohoCrm, stripe
        ]
    }

    // MARK: - Special Flow Nodes (2 types)

    /// Special nodes for flow control
    public enum Special {

        /// Adds a delay before proceeding
        public static let delay = "delay-node"

        /// Human handover / live agent
        public static let humanHandover = "human-handover-node"

        /// All special flow node types
        public static let allTypes: Set<String> = [
            delay, humanHandover
        ]
    }

    // MARK: - All Types Combined

    /// All node types
    public static let allTypes: Set<String> = {
        var types = Set<String>()
        types.formUnion(Display.allTypes)
        types.formUnion(Logic.allTypes)
        types.formUnion(Integration.allTypes)
        types.formUnion(Special.allTypes)
        return types
    }()
}

// MARK: - Helper Functions

/// Checks if a node type is a display node
public func isDisplayNode(_ type: String) -> Bool {
    return NodeTypes.Display.allTypes.contains(type)
}

/// Checks if a node type is a logic node
public func isLogicNode(_ type: String) -> Bool {
    return NodeTypes.Logic.allTypes.contains(type)
}

/// Checks if a node type is an integration node
public func isIntegrationNode(_ type: String) -> Bool {
    return NodeTypes.Integration.allTypes.contains(type)
}

/// Checks if a node type is a special flow node
public func isSpecialNode(_ type: String) -> Bool {
    return NodeTypes.Special.allTypes.contains(type)
}

/// Checks if a node type requires user interaction
public func requiresUserInteraction(_ type: String) -> Bool {
    return NodeTypes.Display.interactiveTypes.contains(type)
}

/// Checks if a node type is display-only (no user input)
public func isDisplayOnly(_ type: String) -> Bool {
    return NodeTypes.Display.displayOnlyTypes.contains(type)
}

// MARK: - Node Type Utilities

/// Utility struct for working with node types
public struct NodeTypeUtils {

    /// Returns the category of a node type
    public static func category(for type: String) -> String {
        if isDisplayNode(type) { return "display" }
        if isLogicNode(type) { return "logic" }
        if isIntegrationNode(type) { return "integration" }
        if isSpecialNode(type) { return "special" }
        return "unknown"
    }

    /// Checks if a node type is valid
    public static func isValid(_ type: String) -> Bool {
        return NodeTypes.allTypes.contains(type)
    }

    /// Returns a human-readable name for a node type
    public static func displayName(for type: String) -> String {
        return type
            .replacingOccurrences(of: "-node", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }
}

// MARK: - Node Type Constants (Flat Access)

/// Provides flat access to all node type constants for convenience
public struct NodeType {

    // Display - Legacy
    public static let twoChoices = NodeTypes.Display.twoChoices
    public static let threeChoices = NodeTypes.Display.threeChoices
    public static let selectOption = NodeTypes.Display.selectOption
    public static let userRating = NodeTypes.Display.userRating
    public static let userInput = NodeTypes.Display.userInput
    public static let userRange = NodeTypes.Display.userRange
    public static let quiz = NodeTypes.Display.quiz

    // Display - Send
    public static let sendMessage = NodeTypes.Display.sendMessage
    public static let sendImage = NodeTypes.Display.sendImage
    public static let sendVideo = NodeTypes.Display.sendVideo
    public static let sendAudio = NodeTypes.Display.sendAudio
    public static let sendFile = NodeTypes.Display.sendFile

    // Display - Ask
    public static let askName = NodeTypes.Display.askName
    public static let askEmail = NodeTypes.Display.askEmail
    public static let askPhone = NodeTypes.Display.askPhone
    public static let askNumber = NodeTypes.Display.askNumber
    public static let askUrl = NodeTypes.Display.askUrl
    public static let askLocation = NodeTypes.Display.askLocation
    public static let askCustomQuestion = NodeTypes.Display.askCustomQuestion
    public static let askFile = NodeTypes.Display.askFile
    public static let askMultipleQuestions = NodeTypes.Display.askMultipleQuestions
    public static let calendar = NodeTypes.Display.calendar
    public static let nSelectOption = NodeTypes.Display.nSelectOption
    public static let nCheckOptions = NodeTypes.Display.nCheckOptions

    // Display - Choices
    public static let nChoices = NodeTypes.Display.nChoices
    public static let imageChoice = NodeTypes.Display.imageChoice
    public static let ratingChoice = NodeTypes.Display.ratingChoice
    public static let yesOrNoChoice = NodeTypes.Display.yesOrNoChoice
    public static let opinionScaleChoice = NodeTypes.Display.opinionScaleChoice

    // Display - Special
    public static let userRedirect = NodeTypes.Display.userRedirect
    public static let html = NodeTypes.Display.html
    public static let navigate = NodeTypes.Display.navigate

    // Logic
    public static let condition = NodeTypes.Logic.condition
    public static let booleanLogic = NodeTypes.Logic.booleanLogic
    public static let randomFlow = NodeTypes.Logic.randomFlow
    public static let mathOperation = NodeTypes.Logic.mathOperation
    public static let variable = NodeTypes.Logic.variable
    public static let jumpTo = NodeTypes.Logic.jumpTo
    public static let businessHours = NodeTypes.Logic.businessHours

    // Integration
    public static let email = NodeTypes.Integration.email
    public static let webhook = NodeTypes.Integration.webhook
    public static let gpt = NodeTypes.Integration.gpt
    public static let zapier = NodeTypes.Integration.zapier
    public static let googleSheets = NodeTypes.Integration.googleSheets
    public static let gmail = NodeTypes.Integration.gmail
    public static let googleCalendar = NodeTypes.Integration.googleCalendar
    public static let googleMeet = NodeTypes.Integration.googleMeet
    public static let googleDrive = NodeTypes.Integration.googleDrive
    public static let googleDocs = NodeTypes.Integration.googleDocs
    public static let slack = NodeTypes.Integration.slack
    public static let discord = NodeTypes.Integration.discord
    public static let airtable = NodeTypes.Integration.airtable
    public static let hubspot = NodeTypes.Integration.hubspot
    public static let notion = NodeTypes.Integration.notion
    public static let zohoCrm = NodeTypes.Integration.zohoCrm
    public static let stripe = NodeTypes.Integration.stripe

    // Special
    public static let delay = NodeTypes.Special.delay
    public static let humanHandover = NodeTypes.Special.humanHandover
}
