//
//  IntegrationNodeHandlers.swift
//  Conferbot
//
//  Created by Conferbot SDK
//

import Foundation

// MARK: - Integration Node Types

/// All supported integration node types
public enum IntegrationNodeType: String, CaseIterable {
    case webhook = "webhook"
    case googleSheets = "google_sheets"
    case sendEmail = "send_email"
    case calendly = "calendly"
    case hubspot = "hubspot"
    case salesforce = "salesforce"
    case zendesk = "zendesk"
    case slack = "slack"
    case zapier = "zapier"
    case dialogflow = "dialogflow"
    case openai = "openai"
    case gemini = "gemini"
    case perplexity = "perplexity"
    case claude = "claude"
    case groq = "groq"
    case customLLM = "custom_llm"
    case humanHandover = "human_handover"
}

// MARK: - Handler Result

/// Result returned by node handlers
public enum NodeHandlerResult {
    /// Proceed to the next node immediately
    case proceed

    /// Proceed to a specific node by ID
    case proceedTo(nodeId: String)

    /// Wait for external event (socket response)
    case waitForResponse

    /// Display UI element (calendly embed, human handover, etc.)
    case displayUI(type: DisplayUIType, data: [String: Any])

    /// Error occurred during handling
    case error(IntegrationError)
}

/// Types of UI elements that can be displayed
public enum DisplayUIType: String {
    case calendlyEmbed = "calendly_embed"
    case calendlyLink = "calendly_link"
    case humanHandover = "human_handover"
    case externalLink = "external_link"
}

// MARK: - Integration Error

/// Errors that can occur during integration handling
public enum IntegrationError: Error, LocalizedError {
    case missingRequiredField(String)
    case invalidURL(String)
    case networkError(Error)
    case invalidResponse
    case socketNotConnected
    case timeout
    case serverError(String)
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .missingRequiredField(let field):
            return "Missing required field: \(field)"
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server"
        case .socketNotConnected:
            return "Socket not connected"
        case .timeout:
            return "Request timed out"
        case .serverError(let message):
            return "Server error: \(message)"
        case .unknown(let message):
            return "Unknown error: \(message)"
        }
    }
}

// MARK: - Node State Protocol

/// Protocol for managing node execution state
public protocol NodeState {
    /// Current chat session ID
    var chatSessionId: String { get }

    /// Bot ID
    var botId: String { get }

    /// All collected variables from the conversation
    var variables: [String: Any] { get set }

    /// Resolve variable placeholders in a string
    func resolveVariables(in text: String) -> String

    /// Store a value in state variables
    func setValue(_ value: Any, forKey key: String)

    /// Get a value from state variables
    func getValue(forKey key: String) -> Any?

    /// Emit socket event
    func emitSocketEvent(_ event: String, data: [String: Any])

    /// Check if socket is connected
    var isSocketConnected: Bool { get }
}

// MARK: - Node Handler Protocol

/// Protocol that all node handlers must conform to
public protocol NodeHandler {
    /// The node type this handler processes
    static var nodeType: String { get }

    /// Handle the node execution
    func handle(nodeData: [String: Any], state: NodeState) async -> NodeHandlerResult
}

// MARK: - Base Integration Handler

/// Base class for integration node handlers with common functionality
open class BaseIntegrationHandler: NodeHandler {
    open class var nodeType: String { "" }

    public init() {}

    open func handle(nodeData: [String: Any], state: NodeState) async -> NodeHandlerResult {
        fatalError("Subclasses must implement handle(nodeData:state:)")
    }

    /// Extract string value from node data with variable resolution
    protected func extractString(
        _ key: String,
        from nodeData: [String: Any],
        state: NodeState,
        required: Bool = false
    ) -> Result<String?, IntegrationError> {
        guard let value = nodeData[key] else {
            if required {
                return .failure(.missingRequiredField(key))
            }
            return .success(nil)
        }

        if let stringValue = value as? String {
            return .success(state.resolveVariables(in: stringValue))
        }

        if required {
            return .failure(.missingRequiredField(key))
        }
        return .success(nil)
    }

    /// Extract dictionary value from node data
    protected func extractDictionary(
        _ key: String,
        from nodeData: [String: Any],
        required: Bool = false
    ) -> Result<[String: Any]?, IntegrationError> {
        guard let value = nodeData[key] else {
            if required {
                return .failure(.missingRequiredField(key))
            }
            return .success(nil)
        }

        if let dictValue = value as? [String: Any] {
            return .success(dictValue)
        }

        if required {
            return .failure(.missingRequiredField(key))
        }
        return .success(nil)
    }

    /// Extract array value from node data
    protected func extractArray(
        _ key: String,
        from nodeData: [String: Any],
        required: Bool = false
    ) -> Result<[Any]?, IntegrationError> {
        guard let value = nodeData[key] else {
            if required {
                return .failure(.missingRequiredField(key))
            }
            return .success(nil)
        }

        if let arrayValue = value as? [Any] {
            return .success(arrayValue)
        }

        if required {
            return .failure(.missingRequiredField(key))
        }
        return .success(nil)
    }

    /// Resolve variables in a dictionary's string values
    protected func resolveVariablesInDictionary(
        _ dict: [String: Any],
        state: NodeState
    ) -> [String: Any] {
        var resolved: [String: Any] = [:]
        for (key, value) in dict {
            if let stringValue = value as? String {
                resolved[key] = state.resolveVariables(in: stringValue)
            } else if let nestedDict = value as? [String: Any] {
                resolved[key] = resolveVariablesInDictionary(nestedDict, state: state)
            } else {
                resolved[key] = value
            }
        }
        return resolved
    }

    /// Log debug message
    protected func debugLog(_ message: String) {
        #if DEBUG
        print("[IntegrationHandler] \(message)")
        #endif
    }
}

// MARK: - 1. Webhook Handler

/// Handles webhook integration nodes
/// Makes HTTP requests to external URLs with custom headers and body
public final class WebhookHandler: BaseIntegrationHandler {
    public override class var nodeType: String { "webhook" }

    public override func handle(nodeData: [String: Any], state: NodeState) async -> NodeHandlerResult {
        debugLog("Processing webhook node")

        // Extract URL (required)
        guard case .success(let urlString) = extractString("url", from: nodeData, state: state, required: true),
              let url = urlString else {
            return .error(.missingRequiredField("url"))
        }

        // Validate URL
        guard let requestURL = URL(string: url) else {
            return .error(.invalidURL(url))
        }

        // Extract HTTP method (default: POST)
        let method = (nodeData["method"] as? String)?.uppercased() ?? "POST"

        // Extract and resolve headers
        var headers: [String: String] = [:]
        if let headersData = nodeData["headers"] as? [String: Any] {
            for (key, value) in headersData {
                if let stringValue = value as? String {
                    headers[key] = state.resolveVariables(in: stringValue)
                }
            }
        }

        // Extract and resolve body
        var bodyData: Data?
        if let body = nodeData["body"] {
            if let bodyString = body as? String {
                let resolvedBody = state.resolveVariables(in: bodyString)
                bodyData = resolvedBody.data(using: .utf8)
            } else if let bodyDict = body as? [String: Any] {
                let resolvedDict = resolveVariablesInDictionary(bodyDict, state: state)
                bodyData = try? JSONSerialization.data(withJSONObject: resolvedDict)
                if headers["Content-Type"] == nil {
                    headers["Content-Type"] = "application/json"
                }
            }
        }

        // Create request
        var request = URLRequest(url: requestURL)
        request.httpMethod = method
        request.timeoutInterval = ConferBotConstants.apiTimeout

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        if let data = bodyData, ["POST", "PUT", "PATCH"].contains(method) {
            request.httpBody = data
        }

        // Execute request
        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return .error(.invalidResponse)
            }

            debugLog("Webhook response status: \(httpResponse.statusCode)")

            // Store response in state if responseVariable is specified
            if let responseVariable = nodeData["responseVariable"] as? String {
                if let jsonObject = try? JSONSerialization.jsonObject(with: data) {
                    state.setValue(jsonObject, forKey: responseVariable)
                } else if let responseString = String(data: data, encoding: .utf8) {
                    state.setValue(responseString, forKey: responseVariable)
                }
            }

            // Store status code if specified
            if let statusVariable = nodeData["statusVariable"] as? String {
                state.setValue(httpResponse.statusCode, forKey: statusVariable)
            }

            // Check for success (2xx status codes)
            if (200...299).contains(httpResponse.statusCode) {
                return .proceed
            } else {
                // Check if there's an error path defined
                if let errorNodeId = nodeData["errorNodeId"] as? String {
                    return .proceedTo(nodeId: errorNodeId)
                }
                return .proceed
            }

        } catch {
            debugLog("Webhook error: \(error.localizedDescription)")

            // Check if there's an error path defined
            if let errorNodeId = nodeData["errorNodeId"] as? String {
                return .proceedTo(nodeId: errorNodeId)
            }

            return .error(.networkError(error))
        }
    }
}

// MARK: - 2. Google Sheets Handler

/// Handles Google Sheets integration nodes
/// Server-side processing - emits socket event for server to handle
public final class GoogleSheetsHandler: BaseIntegrationHandler {
    public override class var nodeType: String { "google_sheets" }

    public override func handle(nodeData: [String: Any], state: NodeState) async -> NodeHandlerResult {
        debugLog("Processing Google Sheets node")

        guard state.isSocketConnected else {
            return .error(.socketNotConnected)
        }

        // Extract sheet configuration
        let spreadsheetId = nodeData["spreadsheetId"] as? String
        let sheetName = nodeData["sheetName"] as? String
        let action = nodeData["action"] as? String ?? "append" // append, read, update

        // Extract data to write/read
        var resolvedData: [String: Any] = [:]
        if let data = nodeData["data"] as? [String: Any] {
            resolvedData = resolveVariablesInDictionary(data, state: state)
        }

        // Extract column mappings if provided
        var columnMappings: [[String: Any]] = []
        if let mappings = nodeData["columnMappings"] as? [[String: Any]] {
            for mapping in mappings {
                var resolvedMapping: [String: Any] = [:]
                if let column = mapping["column"] as? String {
                    resolvedMapping["column"] = column
                }
                if let value = mapping["value"] as? String {
                    resolvedMapping["value"] = state.resolveVariables(in: value)
                }
                columnMappings.append(resolvedMapping)
            }
        }

        // Prepare socket payload
        let payload: [String: Any] = [
            "chatSessionId": state.chatSessionId,
            "botId": state.botId,
            "nodeType": "google_sheets",
            "spreadsheetId": spreadsheetId as Any,
            "sheetName": sheetName as Any,
            "action": action,
            "data": resolvedData,
            "columnMappings": columnMappings,
            "variables": state.variables
        ]

        // Emit socket event for server processing
        state.emitSocketEvent("integration-node-trigger", data: payload)

        debugLog("Google Sheets event emitted for server processing")
        return .proceed
    }
}

// MARK: - 3. Send Email Handler

/// Handles email sending integration nodes
/// Server-side processing - emits socket event for server to send email
public final class SendEmailHandler: BaseIntegrationHandler {
    public override class var nodeType: String { "send_email" }

    public override func handle(nodeData: [String: Any], state: NodeState) async -> NodeHandlerResult {
        debugLog("Processing send email node")

        guard state.isSocketConnected else {
            return .error(.socketNotConnected)
        }

        // Extract email fields
        guard case .success(let to) = extractString("to", from: nodeData, state: state, required: true),
              let toEmail = to else {
            return .error(.missingRequiredField("to"))
        }

        guard case .success(let subject) = extractString("subject", from: nodeData, state: state, required: true),
              let emailSubject = subject else {
            return .error(.missingRequiredField("subject"))
        }

        guard case .success(let body) = extractString("body", from: nodeData, state: state, required: true),
              let emailBody = body else {
            return .error(.missingRequiredField("body"))
        }

        // Optional fields
        let fromEmail = (nodeData["from"] as? String).map { state.resolveVariables(in: $0) }
        let replyTo = (nodeData["replyTo"] as? String).map { state.resolveVariables(in: $0) }
        let cc = (nodeData["cc"] as? String).map { state.resolveVariables(in: $0) }
        let bcc = (nodeData["bcc"] as? String).map { state.resolveVariables(in: $0) }
        let isHtml = nodeData["isHtml"] as? Bool ?? false

        // Extract attachments if any
        var attachments: [[String: Any]] = []
        if let attachmentList = nodeData["attachments"] as? [[String: Any]] {
            attachments = attachmentList
        }

        // Prepare socket payload
        var payload: [String: Any] = [
            "chatSessionId": state.chatSessionId,
            "botId": state.botId,
            "nodeType": "send_email",
            "to": toEmail,
            "subject": emailSubject,
            "body": emailBody,
            "isHtml": isHtml,
            "attachments": attachments,
            "variables": state.variables
        ]

        if let from = fromEmail { payload["from"] = from }
        if let reply = replyTo { payload["replyTo"] = reply }
        if let ccEmail = cc { payload["cc"] = ccEmail }
        if let bccEmail = bcc { payload["bcc"] = bccEmail }

        // Emit socket event for server processing
        state.emitSocketEvent(SocketEvents.emailNodeTrigger, data: payload)

        debugLog("Email event emitted for server processing")
        return .proceed
    }
}

// MARK: - 4. Calendly Handler

/// Handles Calendly integration nodes
/// Returns displayUI result for embedding or linking to Calendly
public final class CalendlyHandler: BaseIntegrationHandler {
    public override class var nodeType: String { "calendly" }

    public override func handle(nodeData: [String: Any], state: NodeState) async -> NodeHandlerResult {
        debugLog("Processing Calendly node")

        // Extract Calendly URL
        guard case .success(let urlString) = extractString("calendlyUrl", from: nodeData, state: state, required: true),
              let calendlyUrl = urlString else {
            return .error(.missingRequiredField("calendlyUrl"))
        }

        // Extract display mode (embed or link)
        let displayMode = nodeData["displayMode"] as? String ?? "link"

        // Extract prefill data if available
        var prefillData: [String: Any] = [:]
        if let name = state.getValue(forKey: "name") as? String {
            prefillData["name"] = name
        }
        if let email = state.getValue(forKey: "email") as? String {
            prefillData["email"] = email
        }
        if let customPrefill = nodeData["prefill"] as? [String: Any] {
            let resolved = resolveVariablesInDictionary(customPrefill, state: state)
            prefillData.merge(resolved) { _, new in new }
        }

        // Build URL with prefill parameters
        var finalUrl = calendlyUrl
        if !prefillData.isEmpty {
            var components = URLComponents(string: calendlyUrl)
            var queryItems = components?.queryItems ?? []

            for (key, value) in prefillData {
                if let stringValue = value as? String {
                    queryItems.append(URLQueryItem(name: key, value: stringValue))
                }
            }
            components?.queryItems = queryItems
            finalUrl = components?.url?.absoluteString ?? calendlyUrl
        }

        // Prepare UI data
        let uiData: [String: Any] = [
            "calendlyUrl": finalUrl,
            "displayMode": displayMode,
            "prefillData": prefillData,
            "title": nodeData["title"] as? String ?? "Schedule a Meeting",
            "buttonText": nodeData["buttonText"] as? String ?? "Open Calendar"
        ]

        let uiType: DisplayUIType = displayMode == "embed" ? .calendlyEmbed : .calendlyLink

        debugLog("Calendly display requested: \(displayMode)")
        return .displayUI(type: uiType, data: uiData)
    }
}

// MARK: - 5. HubSpot Handler

/// Handles HubSpot CRM integration nodes
/// Server-side processing - emits socket event for server to handle
public final class HubspotHandler: BaseIntegrationHandler {
    public override class var nodeType: String { "hubspot" }

    public override func handle(nodeData: [String: Any], state: NodeState) async -> NodeHandlerResult {
        debugLog("Processing HubSpot node")

        guard state.isSocketConnected else {
            return .error(.socketNotConnected)
        }

        // Extract action type (create_contact, update_contact, create_deal, etc.)
        let action = nodeData["action"] as? String ?? "create_contact"

        // Extract contact/deal data
        var contactData: [String: Any] = [:]
        if let data = nodeData["contactData"] as? [String: Any] {
            contactData = resolveVariablesInDictionary(data, state: state)
        }

        // Extract field mappings
        var fieldMappings: [String: String] = [:]
        if let mappings = nodeData["fieldMappings"] as? [String: String] {
            for (hubspotField, variableName) in mappings {
                if let value = state.getValue(forKey: variableName) {
                    if let stringValue = value as? String {
                        fieldMappings[hubspotField] = stringValue
                    } else {
                        fieldMappings[hubspotField] = String(describing: value)
                    }
                }
            }
        }

        // Merge field mappings into contact data
        contactData.merge(fieldMappings) { _, new in new }

        // Common fields from state
        if contactData["email"] == nil, let email = state.getValue(forKey: "email") as? String {
            contactData["email"] = email
        }
        if contactData["firstname"] == nil, let name = state.getValue(forKey: "name") as? String {
            contactData["firstname"] = name
        }
        if contactData["phone"] == nil, let phone = state.getValue(forKey: "phone") as? String {
            contactData["phone"] = phone
        }

        // Prepare socket payload
        let payload: [String: Any] = [
            "chatSessionId": state.chatSessionId,
            "botId": state.botId,
            "nodeType": "hubspot",
            "action": action,
            "contactData": contactData,
            "variables": state.variables
        ]

        // Emit socket event for server processing
        state.emitSocketEvent("integration-node-trigger", data: payload)

        debugLog("HubSpot event emitted for server processing")
        return .proceed
    }
}

// MARK: - 6. Salesforce Handler

/// Handles Salesforce CRM integration nodes
/// Server-side processing - emits socket event for server to handle
public final class SalesforceHandler: BaseIntegrationHandler {
    public override class var nodeType: String { "salesforce" }

    public override func handle(nodeData: [String: Any], state: NodeState) async -> NodeHandlerResult {
        debugLog("Processing Salesforce node")

        guard state.isSocketConnected else {
            return .error(.socketNotConnected)
        }

        // Extract action type (create_lead, create_contact, create_opportunity, etc.)
        let action = nodeData["action"] as? String ?? "create_lead"

        // Extract object type (Lead, Contact, Account, Opportunity)
        let objectType = nodeData["objectType"] as? String ?? "Lead"

        // Extract record data
        var recordData: [String: Any] = [:]
        if let data = nodeData["recordData"] as? [String: Any] {
            recordData = resolveVariablesInDictionary(data, state: state)
        }

        // Extract field mappings
        if let mappings = nodeData["fieldMappings"] as? [String: String] {
            for (salesforceField, variableName) in mappings {
                if let value = state.getValue(forKey: variableName) {
                    recordData[salesforceField] = value
                }
            }
        }

        // Common field mappings for Lead/Contact
        if ["Lead", "Contact"].contains(objectType) {
            if recordData["Email"] == nil, let email = state.getValue(forKey: "email") as? String {
                recordData["Email"] = email
            }
            if recordData["FirstName"] == nil, let name = state.getValue(forKey: "name") as? String {
                recordData["FirstName"] = name
            }
            if recordData["Phone"] == nil, let phone = state.getValue(forKey: "phone") as? String {
                recordData["Phone"] = phone
            }
            if recordData["Company"] == nil, let company = state.getValue(forKey: "company") as? String {
                recordData["Company"] = company
            }
        }

        // Prepare socket payload
        let payload: [String: Any] = [
            "chatSessionId": state.chatSessionId,
            "botId": state.botId,
            "nodeType": "salesforce",
            "action": action,
            "objectType": objectType,
            "recordData": recordData,
            "variables": state.variables
        ]

        // Emit socket event for server processing
        state.emitSocketEvent("integration-node-trigger", data: payload)

        debugLog("Salesforce event emitted for server processing")
        return .proceed
    }
}

// MARK: - 7. Zendesk Handler

/// Handles Zendesk support integration nodes
/// Server-side processing - emits socket event for server to create tickets
public final class ZendeskHandler: BaseIntegrationHandler {
    public override class var nodeType: String { "zendesk" }

    public override func handle(nodeData: [String: Any], state: NodeState) async -> NodeHandlerResult {
        debugLog("Processing Zendesk node")

        guard state.isSocketConnected else {
            return .error(.socketNotConnected)
        }

        // Extract action (create_ticket, update_ticket, add_comment)
        let action = nodeData["action"] as? String ?? "create_ticket"

        // Extract ticket data
        var ticketData: [String: Any] = [:]
        if let data = nodeData["ticketData"] as? [String: Any] {
            ticketData = resolveVariablesInDictionary(data, state: state)
        }

        // Extract subject
        if let subject = nodeData["subject"] as? String {
            ticketData["subject"] = state.resolveVariables(in: subject)
        }

        // Extract description/body
        if let description = nodeData["description"] as? String {
            ticketData["description"] = state.resolveVariables(in: description)
        } else if let body = nodeData["body"] as? String {
            ticketData["description"] = state.resolveVariables(in: body)
        }

        // Extract priority (low, normal, high, urgent)
        if let priority = nodeData["priority"] as? String {
            ticketData["priority"] = priority
        }

        // Extract ticket type (question, incident, problem, task)
        if let ticketType = nodeData["ticketType"] as? String {
            ticketData["type"] = ticketType
        }

        // Extract tags
        if let tags = nodeData["tags"] as? [String] {
            ticketData["tags"] = tags
        }

        // Requester information from state
        var requester: [String: Any] = [:]
        if let email = state.getValue(forKey: "email") as? String {
            requester["email"] = email
        }
        if let name = state.getValue(forKey: "name") as? String {
            requester["name"] = name
        }
        if !requester.isEmpty {
            ticketData["requester"] = requester
        }

        // Prepare socket payload
        let payload: [String: Any] = [
            "chatSessionId": state.chatSessionId,
            "botId": state.botId,
            "nodeType": "zendesk",
            "action": action,
            "ticketData": ticketData,
            "variables": state.variables
        ]

        // Emit socket event for server processing
        state.emitSocketEvent("integration-node-trigger", data: payload)

        debugLog("Zendesk event emitted for server processing")
        return .proceed
    }
}

// MARK: - 8. Slack Handler

/// Handles Slack messaging integration nodes
/// Server-side processing - emits socket event for server to send Slack messages
public final class SlackHandler: BaseIntegrationHandler {
    public override class var nodeType: String { "slack" }

    public override func handle(nodeData: [String: Any], state: NodeState) async -> NodeHandlerResult {
        debugLog("Processing Slack node")

        guard state.isSocketConnected else {
            return .error(.socketNotConnected)
        }

        // Extract channel
        let channel = (nodeData["channel"] as? String).map { state.resolveVariables(in: $0) }

        // Extract message text
        guard case .success(let messageText) = extractString("message", from: nodeData, state: state, required: true),
              let message = messageText else {
            return .error(.missingRequiredField("message"))
        }

        // Extract optional username and icon
        let username = (nodeData["username"] as? String).map { state.resolveVariables(in: $0) }
        let iconEmoji = nodeData["iconEmoji"] as? String
        let iconUrl = nodeData["iconUrl"] as? String

        // Extract blocks for rich messages
        var blocks: [[String: Any]]?
        if let blockData = nodeData["blocks"] as? [[String: Any]] {
            blocks = blockData.map { resolveVariablesInDictionary($0, state: state) }
        }

        // Extract attachments
        var attachments: [[String: Any]]?
        if let attachmentData = nodeData["attachments"] as? [[String: Any]] {
            attachments = attachmentData.map { resolveVariablesInDictionary($0, state: state) }
        }

        // Prepare socket payload
        var payload: [String: Any] = [
            "chatSessionId": state.chatSessionId,
            "botId": state.botId,
            "nodeType": "slack",
            "message": message,
            "variables": state.variables
        ]

        if let ch = channel { payload["channel"] = ch }
        if let user = username { payload["username"] = user }
        if let emoji = iconEmoji { payload["iconEmoji"] = emoji }
        if let icon = iconUrl { payload["iconUrl"] = icon }
        if let blks = blocks { payload["blocks"] = blks }
        if let atts = attachments { payload["attachments"] = atts }

        // Emit socket event for server processing
        state.emitSocketEvent("integration-node-trigger", data: payload)

        debugLog("Slack event emitted for server processing")
        return .proceed
    }
}

// MARK: - 9. Zapier Handler

/// Handles Zapier webhook integration nodes
/// Makes HTTP POST request to Zapier webhook URL
public final class ZapierHandler: BaseIntegrationHandler {
    public override class var nodeType: String { "zapier" }

    public override func handle(nodeData: [String: Any], state: NodeState) async -> NodeHandlerResult {
        debugLog("Processing Zapier node")

        // Extract webhook URL
        guard case .success(let urlString) = extractString("webhookUrl", from: nodeData, state: state, required: true),
              let webhookUrl = urlString else {
            return .error(.missingRequiredField("webhookUrl"))
        }

        // Validate URL
        guard let requestURL = URL(string: webhookUrl) else {
            return .error(.invalidURL(webhookUrl))
        }

        // Prepare payload data
        var zapierData: [String: Any] = [:]

        // Include all state variables
        for (key, value) in state.variables {
            zapierData[key] = value
        }

        // Merge with custom data if provided
        if let customData = nodeData["data"] as? [String: Any] {
            let resolved = resolveVariablesInDictionary(customData, state: state)
            zapierData.merge(resolved) { _, new in new }
        }

        // Add metadata
        zapierData["_chatSessionId"] = state.chatSessionId
        zapierData["_botId"] = state.botId
        zapierData["_timestamp"] = ISO8601DateFormatter().string(from: Date())

        // Create request
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = ConferBotConstants.apiTimeout

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: zapierData)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return .error(.invalidResponse)
            }

            debugLog("Zapier response status: \(httpResponse.statusCode)")

            // Store response if variable specified
            if let responseVariable = nodeData["responseVariable"] as? String {
                if let jsonObject = try? JSONSerialization.jsonObject(with: data) {
                    state.setValue(jsonObject, forKey: responseVariable)
                }
            }

            if (200...299).contains(httpResponse.statusCode) {
                return .proceed
            } else {
                if let errorNodeId = nodeData["errorNodeId"] as? String {
                    return .proceedTo(nodeId: errorNodeId)
                }
                return .proceed
            }

        } catch {
            debugLog("Zapier error: \(error.localizedDescription)")

            if let errorNodeId = nodeData["errorNodeId"] as? String {
                return .proceedTo(nodeId: errorNodeId)
            }

            return .error(.networkError(error))
        }
    }
}

// MARK: - 10. Dialogflow Handler

/// Handles Dialogflow NLU integration nodes
/// Server-side processing - emits socket event for server to process
public final class DialogflowHandler: BaseIntegrationHandler {
    public override class var nodeType: String { "dialogflow" }

    public override func handle(nodeData: [String: Any], state: NodeState) async -> NodeHandlerResult {
        debugLog("Processing Dialogflow node")

        guard state.isSocketConnected else {
            return .error(.socketNotConnected)
        }

        // Extract query text
        guard case .success(let queryText) = extractString("queryText", from: nodeData, state: state, required: true),
              let query = queryText else {
            // If no explicit query, use last user message
            if let lastMessage = state.getValue(forKey: "_lastUserMessage") as? String {
                // Continue with last message
                let payload: [String: Any] = [
                    "chatSessionId": state.chatSessionId,
                    "botId": state.botId,
                    "nodeType": "dialogflow",
                    "queryText": lastMessage,
                    "languageCode": nodeData["languageCode"] as? String ?? "en",
                    "variables": state.variables
                ]
                state.emitSocketEvent("integration-node-trigger", data: payload)
                return .proceed
            }
            return .error(.missingRequiredField("queryText"))
        }

        // Extract language code
        let languageCode = nodeData["languageCode"] as? String ?? "en"

        // Extract session ID (optional - server may generate)
        let sessionId = nodeData["sessionId"] as? String

        // Extract contexts if provided
        var contexts: [[String: Any]]?
        if let contextData = nodeData["contexts"] as? [[String: Any]] {
            contexts = contextData.map { resolveVariablesInDictionary($0, state: state) }
        }

        // Prepare socket payload
        var payload: [String: Any] = [
            "chatSessionId": state.chatSessionId,
            "botId": state.botId,
            "nodeType": "dialogflow",
            "queryText": query,
            "languageCode": languageCode,
            "variables": state.variables
        ]

        if let sid = sessionId { payload["sessionId"] = sid }
        if let ctx = contexts { payload["contexts"] = ctx }

        // Emit socket event for server processing
        state.emitSocketEvent("integration-node-trigger", data: payload)

        debugLog("Dialogflow event emitted for server processing")
        return .proceed
    }
}

// MARK: - 11. OpenAI Handler

/// Handles OpenAI GPT integration nodes
/// Server-side processing - emits socket event for server to call OpenAI API
public final class OpenAIHandler: BaseIntegrationHandler {
    public override class var nodeType: String { "openai" }

    public override func handle(nodeData: [String: Any], state: NodeState) async -> NodeHandlerResult {
        debugLog("Processing OpenAI node")

        guard state.isSocketConnected else {
            return .error(.socketNotConnected)
        }

        // Extract prompt
        guard case .success(let promptText) = extractString("prompt", from: nodeData, state: state, required: true),
              let prompt = promptText else {
            return .error(.missingRequiredField("prompt"))
        }

        // Extract model settings
        let model = nodeData["model"] as? String ?? "gpt-4"
        let temperature = nodeData["temperature"] as? Double ?? 0.7
        let maxTokens = nodeData["maxTokens"] as? Int ?? 1000
        let topP = nodeData["topP"] as? Double ?? 1.0
        let frequencyPenalty = nodeData["frequencyPenalty"] as? Double ?? 0.0
        let presencePenalty = nodeData["presencePenalty"] as? Double ?? 0.0

        // Extract system message
        let systemMessage = (nodeData["systemMessage"] as? String).map { state.resolveVariables(in: $0) }

        // Extract conversation history if provided
        var messages: [[String: Any]] = []
        if let history = nodeData["messages"] as? [[String: Any]] {
            messages = history.map { resolveVariablesInDictionary($0, state: state) }
        }

        // Extract response variable name
        let responseVariable = nodeData["responseVariable"] as? String ?? "ai_response"

        // Prepare socket payload
        var payload: [String: Any] = [
            "chatSessionId": state.chatSessionId,
            "botId": state.botId,
            "nodeType": "openai",
            "prompt": prompt,
            "model": model,
            "temperature": temperature,
            "maxTokens": maxTokens,
            "topP": topP,
            "frequencyPenalty": frequencyPenalty,
            "presencePenalty": presencePenalty,
            "responseVariable": responseVariable,
            "variables": state.variables
        ]

        if let sys = systemMessage { payload["systemMessage"] = sys }
        if !messages.isEmpty { payload["messages"] = messages }

        // Emit socket event for server processing
        state.emitSocketEvent("integration-node-trigger", data: payload)

        debugLog("OpenAI event emitted for server processing")
        return .proceed
    }
}

// MARK: - 12. Gemini Handler

/// Handles Google Gemini AI integration nodes
/// Server-side processing - emits socket event for server to call Gemini API
public final class GeminiHandler: BaseIntegrationHandler {
    public override class var nodeType: String { "gemini" }

    public override func handle(nodeData: [String: Any], state: NodeState) async -> NodeHandlerResult {
        debugLog("Processing Gemini node")

        guard state.isSocketConnected else {
            return .error(.socketNotConnected)
        }

        // Extract prompt
        guard case .success(let promptText) = extractString("prompt", from: nodeData, state: state, required: true),
              let prompt = promptText else {
            return .error(.missingRequiredField("prompt"))
        }

        // Extract model settings
        let model = nodeData["model"] as? String ?? "gemini-pro"
        let temperature = nodeData["temperature"] as? Double ?? 0.7
        let maxOutputTokens = nodeData["maxOutputTokens"] as? Int ?? 1000
        let topP = nodeData["topP"] as? Double ?? 0.95
        let topK = nodeData["topK"] as? Int ?? 40

        // Extract safety settings
        var safetySettings: [[String: Any]]?
        if let settings = nodeData["safetySettings"] as? [[String: Any]] {
            safetySettings = settings
        }

        // Extract response variable name
        let responseVariable = nodeData["responseVariable"] as? String ?? "ai_response"

        // Prepare socket payload
        var payload: [String: Any] = [
            "chatSessionId": state.chatSessionId,
            "botId": state.botId,
            "nodeType": "gemini",
            "prompt": prompt,
            "model": model,
            "temperature": temperature,
            "maxOutputTokens": maxOutputTokens,
            "topP": topP,
            "topK": topK,
            "responseVariable": responseVariable,
            "variables": state.variables
        ]

        if let safety = safetySettings { payload["safetySettings"] = safety }

        // Emit socket event for server processing
        state.emitSocketEvent("integration-node-trigger", data: payload)

        debugLog("Gemini event emitted for server processing")
        return .proceed
    }
}

// MARK: - 13. Perplexity Handler

/// Handles Perplexity AI integration nodes
/// Server-side processing - emits socket event for server to call Perplexity API
public final class PerplexityHandler: BaseIntegrationHandler {
    public override class var nodeType: String { "perplexity" }

    public override func handle(nodeData: [String: Any], state: NodeState) async -> NodeHandlerResult {
        debugLog("Processing Perplexity node")

        guard state.isSocketConnected else {
            return .error(.socketNotConnected)
        }

        // Extract prompt
        guard case .success(let promptText) = extractString("prompt", from: nodeData, state: state, required: true),
              let prompt = promptText else {
            return .error(.missingRequiredField("prompt"))
        }

        // Extract model settings
        let model = nodeData["model"] as? String ?? "pplx-7b-online"
        let temperature = nodeData["temperature"] as? Double ?? 0.7
        let maxTokens = nodeData["maxTokens"] as? Int ?? 1000

        // Extract system message
        let systemMessage = (nodeData["systemMessage"] as? String).map { state.resolveVariables(in: $0) }

        // Extract search domain filter
        let searchDomainFilter = nodeData["searchDomainFilter"] as? [String]

        // Extract response variable name
        let responseVariable = nodeData["responseVariable"] as? String ?? "ai_response"

        // Prepare socket payload
        var payload: [String: Any] = [
            "chatSessionId": state.chatSessionId,
            "botId": state.botId,
            "nodeType": "perplexity",
            "prompt": prompt,
            "model": model,
            "temperature": temperature,
            "maxTokens": maxTokens,
            "responseVariable": responseVariable,
            "variables": state.variables
        ]

        if let sys = systemMessage { payload["systemMessage"] = sys }
        if let domains = searchDomainFilter { payload["searchDomainFilter"] = domains }

        // Emit socket event for server processing
        state.emitSocketEvent("integration-node-trigger", data: payload)

        debugLog("Perplexity event emitted for server processing")
        return .proceed
    }
}

// MARK: - 14. Claude Handler

/// Handles Anthropic Claude AI integration nodes
/// Server-side processing - emits socket event for server to call Claude API
public final class ClaudeHandler: BaseIntegrationHandler {
    public override class var nodeType: String { "claude" }

    public override func handle(nodeData: [String: Any], state: NodeState) async -> NodeHandlerResult {
        debugLog("Processing Claude node")

        guard state.isSocketConnected else {
            return .error(.socketNotConnected)
        }

        // Extract prompt
        guard case .success(let promptText) = extractString("prompt", from: nodeData, state: state, required: true),
              let prompt = promptText else {
            return .error(.missingRequiredField("prompt"))
        }

        // Extract model settings
        let model = nodeData["model"] as? String ?? "claude-3-opus-20240229"
        let temperature = nodeData["temperature"] as? Double ?? 0.7
        let maxTokens = nodeData["maxTokens"] as? Int ?? 1000
        let topP = nodeData["topP"] as? Double ?? 1.0
        let topK = nodeData["topK"] as? Int

        // Extract system message
        let systemMessage = (nodeData["systemMessage"] as? String).map { state.resolveVariables(in: $0) }

        // Extract conversation history if provided
        var messages: [[String: Any]] = []
        if let history = nodeData["messages"] as? [[String: Any]] {
            messages = history.map { resolveVariablesInDictionary($0, state: state) }
        }

        // Extract response variable name
        let responseVariable = nodeData["responseVariable"] as? String ?? "ai_response"

        // Prepare socket payload
        var payload: [String: Any] = [
            "chatSessionId": state.chatSessionId,
            "botId": state.botId,
            "nodeType": "claude",
            "prompt": prompt,
            "model": model,
            "temperature": temperature,
            "maxTokens": maxTokens,
            "topP": topP,
            "responseVariable": responseVariable,
            "variables": state.variables
        ]

        if let sys = systemMessage { payload["systemMessage"] = sys }
        if let k = topK { payload["topK"] = k }
        if !messages.isEmpty { payload["messages"] = messages }

        // Emit socket event for server processing
        state.emitSocketEvent("integration-node-trigger", data: payload)

        debugLog("Claude event emitted for server processing")
        return .proceed
    }
}

// MARK: - 15. Groq Handler

/// Handles Groq AI integration nodes
/// Server-side processing - emits socket event for server to call Groq API
public final class GroqHandler: BaseIntegrationHandler {
    public override class var nodeType: String { "groq" }

    public override func handle(nodeData: [String: Any], state: NodeState) async -> NodeHandlerResult {
        debugLog("Processing Groq node")

        guard state.isSocketConnected else {
            return .error(.socketNotConnected)
        }

        // Extract prompt
        guard case .success(let promptText) = extractString("prompt", from: nodeData, state: state, required: true),
              let prompt = promptText else {
            return .error(.missingRequiredField("prompt"))
        }

        // Extract model settings
        let model = nodeData["model"] as? String ?? "llama2-70b-4096"
        let temperature = nodeData["temperature"] as? Double ?? 0.7
        let maxTokens = nodeData["maxTokens"] as? Int ?? 1000
        let topP = nodeData["topP"] as? Double ?? 1.0

        // Extract system message
        let systemMessage = (nodeData["systemMessage"] as? String).map { state.resolveVariables(in: $0) }

        // Extract conversation history if provided
        var messages: [[String: Any]] = []
        if let history = nodeData["messages"] as? [[String: Any]] {
            messages = history.map { resolveVariablesInDictionary($0, state: state) }
        }

        // Extract response variable name
        let responseVariable = nodeData["responseVariable"] as? String ?? "ai_response"

        // Prepare socket payload
        var payload: [String: Any] = [
            "chatSessionId": state.chatSessionId,
            "botId": state.botId,
            "nodeType": "groq",
            "prompt": prompt,
            "model": model,
            "temperature": temperature,
            "maxTokens": maxTokens,
            "topP": topP,
            "responseVariable": responseVariable,
            "variables": state.variables
        ]

        if let sys = systemMessage { payload["systemMessage"] = sys }
        if !messages.isEmpty { payload["messages"] = messages }

        // Emit socket event for server processing
        state.emitSocketEvent("integration-node-trigger", data: payload)

        debugLog("Groq event emitted for server processing")
        return .proceed
    }
}

// MARK: - 16. Custom LLM Handler

/// Handles custom LLM integration nodes
/// Server-side processing - emits socket event for server to call custom LLM endpoint
public final class CustomLLMHandler: BaseIntegrationHandler {
    public override class var nodeType: String { "custom_llm" }

    public override func handle(nodeData: [String: Any], state: NodeState) async -> NodeHandlerResult {
        debugLog("Processing Custom LLM node")

        guard state.isSocketConnected else {
            return .error(.socketNotConnected)
        }

        // Extract prompt
        guard case .success(let promptText) = extractString("prompt", from: nodeData, state: state, required: true),
              let prompt = promptText else {
            return .error(.missingRequiredField("prompt"))
        }

        // Extract endpoint URL
        let endpointUrl = (nodeData["endpointUrl"] as? String).map { state.resolveVariables(in: $0) }

        // Extract model name/identifier
        let model = nodeData["model"] as? String

        // Extract common LLM parameters
        let temperature = nodeData["temperature"] as? Double ?? 0.7
        let maxTokens = nodeData["maxTokens"] as? Int ?? 1000

        // Extract system message
        let systemMessage = (nodeData["systemMessage"] as? String).map { state.resolveVariables(in: $0) }

        // Extract custom headers
        var customHeaders: [String: String]?
        if let headers = nodeData["headers"] as? [String: String] {
            customHeaders = [:]
            for (key, value) in headers {
                customHeaders?[key] = state.resolveVariables(in: value)
            }
        }

        // Extract custom request body template
        var requestBodyTemplate: [String: Any]?
        if let template = nodeData["requestBodyTemplate"] as? [String: Any] {
            requestBodyTemplate = resolveVariablesInDictionary(template, state: state)
        }

        // Extract response path (JSONPath-like string to extract response)
        let responsePath = nodeData["responsePath"] as? String

        // Extract response variable name
        let responseVariable = nodeData["responseVariable"] as? String ?? "ai_response"

        // Prepare socket payload
        var payload: [String: Any] = [
            "chatSessionId": state.chatSessionId,
            "botId": state.botId,
            "nodeType": "custom_llm",
            "prompt": prompt,
            "temperature": temperature,
            "maxTokens": maxTokens,
            "responseVariable": responseVariable,
            "variables": state.variables
        ]

        if let url = endpointUrl { payload["endpointUrl"] = url }
        if let m = model { payload["model"] = m }
        if let sys = systemMessage { payload["systemMessage"] = sys }
        if let headers = customHeaders { payload["headers"] = headers }
        if let template = requestBodyTemplate { payload["requestBodyTemplate"] = template }
        if let path = responsePath { payload["responsePath"] = path }

        // Emit socket event for server processing
        state.emitSocketEvent("integration-node-trigger", data: payload)

        debugLog("Custom LLM event emitted for server processing")
        return .proceed
    }
}

// MARK: - 17. Human Handover Handler

/// Handles human handover integration nodes
/// Returns displayUI result for showing handover UI and notifies server
public final class HumanHandoverHandler: BaseIntegrationHandler {
    public override class var nodeType: String { "human_handover" }

    public override func handle(nodeData: [String: Any], state: NodeState) async -> NodeHandlerResult {
        debugLog("Processing Human Handover node")

        // Extract handover message
        let handoverMessage = (nodeData["message"] as? String).map { state.resolveVariables(in: $0) }
            ?? "You are being transferred to a live agent. Please wait..."

        // Extract department/queue
        let department = nodeData["department"] as? String
        let priority = nodeData["priority"] as? String ?? "normal"

        // Extract custom fields to pass to agent
        var customFields: [String: Any] = [:]
        if let fields = nodeData["customFields"] as? [String: Any] {
            customFields = resolveVariablesInDictionary(fields, state: state)
        }

        // Collect conversation summary for agent
        var conversationSummary: [String: Any] = [:]

        // Add collected variables
        for (key, value) in state.variables {
            if !key.hasPrefix("_") { // Exclude internal variables
                conversationSummary[key] = value
            }
        }

        // Extract waiting message
        let waitingMessage = (nodeData["waitingMessage"] as? String).map { state.resolveVariables(in: $0) }
            ?? "An agent will be with you shortly..."

        // Extract offline message
        let offlineMessage = (nodeData["offlineMessage"] as? String).map { state.resolveVariables(in: $0) }
            ?? "Our agents are currently offline. Please leave a message."

        // Extract estimated wait time display setting
        let showEstimatedWaitTime = nodeData["showEstimatedWaitTime"] as? Bool ?? true

        // Notify server of handover request
        if state.isSocketConnected {
            var handoverPayload: [String: Any] = [
                "chatSessionId": state.chatSessionId,
                "botId": state.botId,
                "message": handoverMessage,
                "priority": priority,
                "conversationSummary": conversationSummary,
                "customFields": customFields,
                "variables": state.variables
            ]

            if let dept = department { handoverPayload["department"] = dept }

            state.emitSocketEvent(SocketEvents.initiateHandover, data: handoverPayload)
            debugLog("Human handover request sent to server")
        }

        // Prepare UI data for displaying handover interface
        let uiData: [String: Any] = [
            "handoverMessage": handoverMessage,
            "waitingMessage": waitingMessage,
            "offlineMessage": offlineMessage,
            "department": department as Any,
            "priority": priority,
            "showEstimatedWaitTime": showEstimatedWaitTime,
            "customFields": customFields,
            "conversationSummary": conversationSummary
        ]

        return .displayUI(type: .humanHandover, data: uiData)
    }
}

// MARK: - Integration Handler Registry

/// Registry for managing and accessing integration node handlers
public final class IntegrationHandlerRegistry {

    /// Shared singleton instance
    public static let shared = IntegrationHandlerRegistry()

    /// Map of node types to handlers
    private var handlers: [String: NodeHandler] = [:]

    private init() {
        registerDefaultHandlers()
    }

    /// Register default integration handlers
    private func registerDefaultHandlers() {
        // Register all 17 integration handlers
        register(WebhookHandler())
        register(GoogleSheetsHandler())
        register(SendEmailHandler())
        register(CalendlyHandler())
        register(HubspotHandler())
        register(SalesforceHandler())
        register(ZendeskHandler())
        register(SlackHandler())
        register(ZapierHandler())
        register(DialogflowHandler())
        register(OpenAIHandler())
        register(GeminiHandler())
        register(PerplexityHandler())
        register(ClaudeHandler())
        register(GroqHandler())
        register(CustomLLMHandler())
        register(HumanHandoverHandler())
    }

    /// Register a handler
    public func register(_ handler: NodeHandler) {
        handlers[type(of: handler).nodeType] = handler
    }

    /// Get handler for a node type
    public func handler(for nodeType: String) -> NodeHandler? {
        return handlers[nodeType]
    }

    /// Check if a handler exists for a node type
    public func hasHandler(for nodeType: String) -> Bool {
        return handlers[nodeType] != nil
    }

    /// Get all registered node types
    public var registeredNodeTypes: [String] {
        return Array(handlers.keys)
    }

    /// Handle a node with the appropriate handler
    public func handleNode(
        nodeType: String,
        nodeData: [String: Any],
        state: NodeState
    ) async -> NodeHandlerResult {
        guard let handler = handler(for: nodeType) else {
            debugLog("No handler found for node type: \(nodeType)")
            return .error(.unknown("No handler registered for node type: \(nodeType)"))
        }

        return await handler.handle(nodeData: nodeData, state: state)
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        print("[IntegrationHandlerRegistry] \(message)")
        #endif
    }
}

// MARK: - Default Node State Implementation

/// Default implementation of NodeState for use in the SDK
public class DefaultNodeState: NodeState {
    public let chatSessionId: String
    public let botId: String
    public var variables: [String: Any]

    private weak var socketClient: SocketClient?

    public init(
        chatSessionId: String,
        botId: String,
        variables: [String: Any] = [:],
        socketClient: SocketClient? = nil
    ) {
        self.chatSessionId = chatSessionId
        self.botId = botId
        self.variables = variables
        self.socketClient = socketClient
    }

    public func resolveVariables(in text: String) -> String {
        var resolved = text

        // Match patterns like {{variableName}} or {variableName}
        let patterns = [
            "\\{\\{([^}]+)\\}\\}",  // {{variable}}
            "\\{([^}]+)\\}"         // {variable}
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
                continue
            }

            let range = NSRange(resolved.startIndex..<resolved.endIndex, in: resolved)
            let matches = regex.matches(in: resolved, options: [], range: range)

            // Process matches in reverse order to maintain correct indices
            for match in matches.reversed() {
                guard let variableRange = Range(match.range(at: 1), in: resolved) else {
                    continue
                }

                let variableName = String(resolved[variableRange]).trimmingCharacters(in: .whitespaces)

                if let value = variables[variableName] {
                    let fullMatchRange = Range(match.range, in: resolved)!
                    let replacement: String

                    if let stringValue = value as? String {
                        replacement = stringValue
                    } else if let intValue = value as? Int {
                        replacement = String(intValue)
                    } else if let doubleValue = value as? Double {
                        replacement = String(doubleValue)
                    } else if let boolValue = value as? Bool {
                        replacement = boolValue ? "true" : "false"
                    } else {
                        replacement = String(describing: value)
                    }

                    resolved.replaceSubrange(fullMatchRange, with: replacement)
                }
            }
        }

        return resolved
    }

    public func setValue(_ value: Any, forKey key: String) {
        variables[key] = value
    }

    public func getValue(forKey key: String) -> Any? {
        return variables[key]
    }

    public func emitSocketEvent(_ event: String, data: [String: Any]) {
        socketClient?.emit(event, data)
    }

    public var isSocketConnected: Bool {
        return socketClient?.isConnected ?? false
    }
}
