//
//  IntegrationNodeHandlers.swift
//  Conferbot
//
//  Created by Conferbot SDK
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking

// Polyfill: URLSession.data(for:) async is not available in Linux's FoundationNetworking
extension URLSession {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        return try await withCheckedThrowingContinuation { continuation in
            let task = self.dataTask(with: request) { data, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let data = data, let response = response {
                    continuation.resume(returning: (data, response))
                } else {
                    continuation.resume(throwing: URLError(.unknown))
                }
            }
            task.resume()
        }
    }
}
#endif

// MARK: - Integration Node Types

/// All supported integration node types (server-format kebab-case-node)
public enum IntegrationNodeType: String, CaseIterable {
    case webhook = "webhook-node"
    case googleSheets = "google-sheets-node"
    case email = "email-node"
    case gpt = "gpt-node"
    case zapier = "zapier-node"
    case gmail = "gmail-node"
    case googleCalendar = "google-calendar-node"
    case googleMeet = "google-meet-node"
    case googleDrive = "google-drive-node"
    case googleDocs = "google-docs-node"
    case slack = "slack-node"
    case discord = "discord-node"
    case airtable = "airtable-node"
    case hubspot = "hubspot-node"
    case notion = "notion-node"
    case zohoCrm = "zohocrm-node"
    case stripe = "stripe-node"
    case humanHandover = "human-handover-node"
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
public protocol NodeState: AnyObject {
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

/// Protocol that all integration node handlers must conform to
/// Note: This is separate from the main NodeHandler protocol in NodeHandler.swift
/// but BaseIntegrationHandler bridges to NodeHandler so integration handlers
/// can be registered in NodeHandlerRegistry.
public protocol IntegrationNodeHandler {
    /// The node type this handler processes
    static var nodeType: String { get }

    /// Handle the node execution
    func handle(nodeData: [String: Any], state: NodeState) async -> NodeHandlerResult
}

// MARK: - Base Integration Handler

/// Base class for integration node handlers with common functionality.
/// Conforms to both IntegrationNodeHandler and NodeHandler so that subclasses
/// can be registered directly in NodeHandlerRegistry.
open class BaseIntegrationHandler: IntegrationNodeHandler, NodeHandler {
    open class var nodeType: String { "" }

    /// Instance-level nodeType required by NodeHandler protocol.
    /// Delegates to the class-level static property.
    public var nodeType: String { type(of: self).nodeType }

    /// Reference to socket client for emitting events via the NodeState adapter.
    /// Set by the registry or during handler registration.
    public weak var socketClient: SocketClient?

    public init() {}

    open func handle(nodeData: [String: Any], state: NodeState) async -> NodeHandlerResult {
        fatalError("Subclasses must implement handle(nodeData:state:)")
    }

    /// NodeHandler protocol bridge: converts ChatState to NodeState adapter,
    /// extracts node data, delegates to the integration-specific handle method,
    /// and maps the result back to NodeResult.
    public func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        let nodeData = node["data"] as? [String: Any] ?? node
        let nodeStateAdapter = ChatStateNodeStateAdapter(chatState: state, socketClient: socketClient)
        let integrationResult = await handle(nodeData: nodeData, state: nodeStateAdapter)
        return integrationResult.toNodeResult(node: node)
    }

    /// Extract string value from node data with variable resolution
    public func extractString(
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
    public func extractDictionary(
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
    public func extractArray(
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
    public func resolveVariablesInDictionary(
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
    public func debugLog(_ message: String) {
        #if DEBUG
        print("[IntegrationHandler] \(message)")
        #endif
    }
}

// MARK: - 1. Webhook Handler

/// Handles webhook integration nodes
/// Makes HTTP requests to external URLs with custom headers and body
public final class WebhookHandler: BaseIntegrationHandler {
    public override class var nodeType: String { NodeTypes.Integration.webhook }

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
    public override class var nodeType: String { NodeTypes.Integration.googleSheets }

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
        let nodeId = nodeData["id"] as? String ?? nodeData["nodeId"] as? String ?? ""
        let payload: [String: Any] = [
            "nodeType": Self.nodeType,
            "nodeId": nodeId,
            "nodeData": nodeData,
            "chatSessionId": state.chatSessionId,
            "chatbotId": state.botId,
            "workspaceId": state.getValue(forKey: "_workspaceId") ?? "",
            "answerVariables": state.getValue(forKey: "_answerVariables") ?? [],
        ]

        // Emit socket event for server processing
        state.emitSocketEvent("execute-integration", data: payload)

        debugLog("Google Sheets event emitted for server processing")
        return .proceed
    }
}

// MARK: - 3. Send Email Handler

/// Handles email sending integration nodes
/// Server-side processing - emits socket event for server to send email
public final class SendEmailHandler: BaseIntegrationHandler {
    public override class var nodeType: String { NodeTypes.Integration.email }

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
    // Legacy: calendly is not a server node type; kept for compat
    public override class var nodeType: String { "calendly-node" }

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
    public override class var nodeType: String { NodeTypes.Integration.hubspot }

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
        let nodeId = nodeData["id"] as? String ?? nodeData["nodeId"] as? String ?? ""
        let payload: [String: Any] = [
            "nodeType": Self.nodeType,
            "nodeId": nodeId,
            "nodeData": nodeData,
            "chatSessionId": state.chatSessionId,
            "chatbotId": state.botId,
            "workspaceId": state.getValue(forKey: "_workspaceId") ?? "",
            "answerVariables": state.getValue(forKey: "_answerVariables") ?? [],
        ]

        // Emit socket event for server processing
        state.emitSocketEvent("execute-integration", data: payload)

        debugLog("HubSpot event emitted for server processing")
        return .proceed
    }
}

// MARK: - 6. Salesforce Handler

/// Handles Salesforce CRM integration nodes
/// Server-side processing - emits socket event for server to handle
public final class SalesforceHandler: BaseIntegrationHandler {
    // Legacy: salesforce is not in server types; kept for compat
    public override class var nodeType: String { "salesforce-node" }

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
        let nodeId = nodeData["id"] as? String ?? nodeData["nodeId"] as? String ?? ""
        let payload: [String: Any] = [
            "nodeType": Self.nodeType,
            "nodeId": nodeId,
            "nodeData": nodeData,
            "chatSessionId": state.chatSessionId,
            "chatbotId": state.botId,
            "workspaceId": state.getValue(forKey: "_workspaceId") ?? "",
            "answerVariables": state.getValue(forKey: "_answerVariables") ?? [],
        ]

        // Emit socket event for server processing
        state.emitSocketEvent("execute-integration", data: payload)

        debugLog("Salesforce event emitted for server processing")
        return .proceed
    }
}

// MARK: - 7. Zendesk Handler

/// Handles Zendesk support integration nodes
/// Server-side processing - emits socket event for server to create tickets
public final class ZendeskHandler: BaseIntegrationHandler {
    // Legacy: zendesk is not in server types; kept for compat
    public override class var nodeType: String { "zendesk-node" }

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
        let nodeId = nodeData["id"] as? String ?? nodeData["nodeId"] as? String ?? ""
        let payload: [String: Any] = [
            "nodeType": Self.nodeType,
            "nodeId": nodeId,
            "nodeData": nodeData,
            "chatSessionId": state.chatSessionId,
            "chatbotId": state.botId,
            "workspaceId": state.getValue(forKey: "_workspaceId") ?? "",
            "answerVariables": state.getValue(forKey: "_answerVariables") ?? [],
        ]

        // Emit socket event for server processing
        state.emitSocketEvent("execute-integration", data: payload)

        debugLog("Zendesk event emitted for server processing")
        return .proceed
    }
}

// MARK: - 8. Slack Handler

/// Handles Slack messaging integration nodes
/// Server-side processing - emits socket event for server to send Slack messages
public final class SlackHandler: BaseIntegrationHandler {
    public override class var nodeType: String { NodeTypes.Integration.slack }

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

        // Build standardized execute-integration payload
        let nodeId = nodeData["id"] as? String ?? nodeData["nodeId"] as? String ?? ""
        let integrationPayload: [String: Any] = [
            "nodeType": Self.nodeType,
            "nodeId": nodeId,
            "nodeData": nodeData,
            "chatSessionId": state.chatSessionId,
            "chatbotId": state.botId,
            "workspaceId": state.getValue(forKey: "_workspaceId") ?? "",
            "answerVariables": state.getValue(forKey: "_answerVariables") ?? [],
        ]

        // Emit socket event for server processing
        state.emitSocketEvent("execute-integration", data: integrationPayload)

        debugLog("Slack event emitted for server processing")
        return .proceed
    }
}

// MARK: - 9. Discord Handler

/// Handles Discord messaging integration nodes
/// Server-side processing - emits socket event for server to send Discord messages
public final class DiscordHandler: BaseIntegrationHandler {
    public override class var nodeType: String { NodeTypes.Integration.discord }

    public override func handle(nodeData: [String: Any], state: NodeState) async -> NodeHandlerResult {
        debugLog("Processing Discord node")

        guard state.isSocketConnected else {
            return .error(.socketNotConnected)
        }

        // Extract channel ID or webhook URL
        let channelId = (nodeData["channelId"] as? String).map { state.resolveVariables(in: $0) }
        let webhookUrl = (nodeData["webhookUrl"] as? String).map { state.resolveVariables(in: $0) }

        // Extract message content
        guard case .success(let messageText) = extractString("message", from: nodeData, state: state, required: true),
              let message = messageText else {
            return .error(.missingRequiredField("message"))
        }

        // Extract optional username (for webhook)
        let username = (nodeData["username"] as? String).map { state.resolveVariables(in: $0) }

        // Extract optional avatar URL (for webhook)
        let avatarUrl = (nodeData["avatarUrl"] as? String).map { state.resolveVariables(in: $0) }

        // Extract embeds for rich messages
        var embeds: [[String: Any]]?
        if let embedData = nodeData["embeds"] as? [[String: Any]] {
            embeds = embedData.map { resolveVariablesInDictionary($0, state: state) }
        }

        // Extract server ID (guild ID) if provided
        let serverId = (nodeData["serverId"] as? String).map { state.resolveVariables(in: $0) }
            ?? (nodeData["guildId"] as? String).map { state.resolveVariables(in: $0) }

        // Prepare socket payload
        var payload: [String: Any] = [
            "chatSessionId": state.chatSessionId,
            "botId": state.botId,
            "nodeType": "discord",
            "message": message,
            "variables": state.variables
        ]

        // Add channel/webhook configuration
        if let ch = channelId { payload["channelId"] = ch }
        if let wh = webhookUrl { payload["webhookUrl"] = wh }
        if let server = serverId { payload["serverId"] = server }

        // Add optional customization
        if let user = username { payload["username"] = user }
        if let avatar = avatarUrl { payload["avatarUrl"] = avatar }
        if let emb = embeds { payload["embeds"] = emb }

        // Build standardized execute-integration payload
        let nodeId = nodeData["id"] as? String ?? nodeData["nodeId"] as? String ?? ""
        let integrationPayload: [String: Any] = [
            "nodeType": Self.nodeType,
            "nodeId": nodeId,
            "nodeData": nodeData,
            "chatSessionId": state.chatSessionId,
            "chatbotId": state.botId,
            "workspaceId": state.getValue(forKey: "_workspaceId") ?? "",
            "answerVariables": state.getValue(forKey: "_answerVariables") ?? [],
        ]

        // Emit socket event for server processing
        state.emitSocketEvent("execute-integration", data: integrationPayload)

        debugLog("Discord event emitted for server processing")
        return .proceed
    }
}

// MARK: - 10. Zapier Handler

/// Handles Zapier webhook integration nodes
/// Makes HTTP POST request to Zapier webhook URL
public final class ZapierHandler: BaseIntegrationHandler {
    public override class var nodeType: String { NodeTypes.Integration.zapier }

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
    // Legacy: dialogflow is not in server types; kept for compat
    public override class var nodeType: String { "dialogflow-node" }

    public override func handle(nodeData: [String: Any], state: NodeState) async -> NodeHandlerResult {
        debugLog("Processing Dialogflow node")

        guard state.isSocketConnected else {
            return .error(.socketNotConnected)
        }

        let nodeId = nodeData["id"] as? String ?? nodeData["nodeId"] as? String ?? ""

        // Extract query text
        guard case .success(let queryText) = extractString("queryText", from: nodeData, state: state, required: true),
              let query = queryText else {
            // If no explicit query, use last user message
            if state.getValue(forKey: "_lastUserMessage") as? String != nil {
                // Continue with last message
                let payload: [String: Any] = [
                    "nodeType": Self.nodeType,
                    "nodeId": nodeId,
                    "nodeData": nodeData,
                    "chatSessionId": state.chatSessionId,
                    "chatbotId": state.botId,
                    "workspaceId": state.getValue(forKey: "_workspaceId") ?? "",
                    "answerVariables": state.getValue(forKey: "_answerVariables") ?? [],
                ]
                state.emitSocketEvent("execute-integration", data: payload)
                return .proceed
            }
            return .error(.missingRequiredField("queryText"))
        }

        // Extract language code - unused locally but included in nodeData for server
        _ = nodeData["languageCode"] as? String ?? "en"

        // Prepare standardized socket payload
        let payload: [String: Any] = [
            "nodeType": Self.nodeType,
            "nodeId": nodeId,
            "nodeData": nodeData,
            "chatSessionId": state.chatSessionId,
            "chatbotId": state.botId,
            "workspaceId": state.getValue(forKey: "_workspaceId") ?? "",
            "answerVariables": state.getValue(forKey: "_answerVariables") ?? [],
        ]

        // Emit socket event for server processing
        state.emitSocketEvent("execute-integration", data: payload)

        debugLog("Dialogflow event emitted for server processing")
        return .proceed
    }
}

// MARK: - 11. OpenAI Handler

/// Handles OpenAI GPT integration nodes
/// Server-side processing - emits socket event for server to call OpenAI API
public final class OpenAIHandler: BaseIntegrationHandler {
    // Legacy: openai is handled by gpt-node; kept for compat
    public override class var nodeType: String { "openai-node" }

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

        // Build standardized execute-integration payload
        let nodeId = nodeData["id"] as? String ?? nodeData["nodeId"] as? String ?? ""
        let integrationPayload: [String: Any] = [
            "nodeType": Self.nodeType,
            "nodeId": nodeId,
            "nodeData": nodeData,
            "chatSessionId": state.chatSessionId,
            "chatbotId": state.botId,
            "workspaceId": state.getValue(forKey: "_workspaceId") ?? "",
            "answerVariables": state.getValue(forKey: "_answerVariables") ?? [],
        ]

        // Emit socket event for server processing
        state.emitSocketEvent("execute-integration", data: integrationPayload)

        debugLog("OpenAI event emitted for server processing")
        return .proceed
    }
}

// MARK: - 12. Gemini Handler

/// Handles Google Gemini AI integration nodes
/// Server-side processing - emits socket event for server to call Gemini API
public final class GeminiHandler: BaseIntegrationHandler {
    // Legacy: gemini is handled by gpt-node; kept for compat
    public override class var nodeType: String { "gemini-node" }

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

        // Build standardized execute-integration payload
        let nodeId = nodeData["id"] as? String ?? nodeData["nodeId"] as? String ?? ""
        let integrationPayload: [String: Any] = [
            "nodeType": Self.nodeType,
            "nodeId": nodeId,
            "nodeData": nodeData,
            "chatSessionId": state.chatSessionId,
            "chatbotId": state.botId,
            "workspaceId": state.getValue(forKey: "_workspaceId") ?? "",
            "answerVariables": state.getValue(forKey: "_answerVariables") ?? [],
        ]

        // Emit socket event for server processing
        state.emitSocketEvent("execute-integration", data: integrationPayload)

        debugLog("Gemini event emitted for server processing")
        return .proceed
    }
}

// MARK: - 13. Perplexity Handler

/// Handles Perplexity AI integration nodes
/// Server-side processing - emits socket event for server to call Perplexity API
public final class PerplexityHandler: BaseIntegrationHandler {
    // Legacy: perplexity is handled by gpt-node; kept for compat
    public override class var nodeType: String { "perplexity-node" }

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

        // Build standardized execute-integration payload
        let nodeId = nodeData["id"] as? String ?? nodeData["nodeId"] as? String ?? ""
        let integrationPayload: [String: Any] = [
            "nodeType": Self.nodeType,
            "nodeId": nodeId,
            "nodeData": nodeData,
            "chatSessionId": state.chatSessionId,
            "chatbotId": state.botId,
            "workspaceId": state.getValue(forKey: "_workspaceId") ?? "",
            "answerVariables": state.getValue(forKey: "_answerVariables") ?? [],
        ]

        // Emit socket event for server processing
        state.emitSocketEvent("execute-integration", data: integrationPayload)

        debugLog("Perplexity event emitted for server processing")
        return .proceed
    }
}

// MARK: - 14. Claude Handler

/// Handles Anthropic Claude AI integration nodes
/// Server-side processing - emits socket event for server to call Claude API
public final class ClaudeHandler: BaseIntegrationHandler {
    // Legacy: claude is handled by gpt-node; kept for compat
    public override class var nodeType: String { "claude-node" }

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

        // Build standardized execute-integration payload
        let nodeId = nodeData["id"] as? String ?? nodeData["nodeId"] as? String ?? ""
        let integrationPayload: [String: Any] = [
            "nodeType": Self.nodeType,
            "nodeId": nodeId,
            "nodeData": nodeData,
            "chatSessionId": state.chatSessionId,
            "chatbotId": state.botId,
            "workspaceId": state.getValue(forKey: "_workspaceId") ?? "",
            "answerVariables": state.getValue(forKey: "_answerVariables") ?? [],
        ]

        // Emit socket event for server processing
        state.emitSocketEvent("execute-integration", data: integrationPayload)

        debugLog("Claude event emitted for server processing")
        return .proceed
    }
}

// MARK: - 15. Groq Handler

/// Handles Groq AI integration nodes
/// Server-side processing - emits socket event for server to call Groq API
public final class GroqHandler: BaseIntegrationHandler {
    // Legacy: groq is handled by gpt-node; kept for compat
    public override class var nodeType: String { "groq-node" }

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

        // Build standardized execute-integration payload
        let nodeId = nodeData["id"] as? String ?? nodeData["nodeId"] as? String ?? ""
        let integrationPayload: [String: Any] = [
            "nodeType": Self.nodeType,
            "nodeId": nodeId,
            "nodeData": nodeData,
            "chatSessionId": state.chatSessionId,
            "chatbotId": state.botId,
            "workspaceId": state.getValue(forKey: "_workspaceId") ?? "",
            "answerVariables": state.getValue(forKey: "_answerVariables") ?? [],
        ]

        // Emit socket event for server processing
        state.emitSocketEvent("execute-integration", data: integrationPayload)

        debugLog("Groq event emitted for server processing")
        return .proceed
    }
}

// MARK: - 16. Custom LLM Handler

/// Handles custom LLM integration nodes
/// Server-side processing - emits socket event for server to call custom LLM endpoint
public final class CustomLLMHandler: BaseIntegrationHandler {
    // Legacy: custom_llm is handled by gpt-node; kept for compat
    public override class var nodeType: String { "custom-llm-node" }

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

        // Build standardized execute-integration payload
        let nodeId = nodeData["id"] as? String ?? nodeData["nodeId"] as? String ?? ""
        let integrationPayload: [String: Any] = [
            "nodeType": Self.nodeType,
            "nodeId": nodeId,
            "nodeData": nodeData,
            "chatSessionId": state.chatSessionId,
            "chatbotId": state.botId,
            "workspaceId": state.getValue(forKey: "_workspaceId") ?? "",
            "answerVariables": state.getValue(forKey: "_answerVariables") ?? [],
        ]

        // Emit socket event for server processing
        state.emitSocketEvent("execute-integration", data: integrationPayload)

        debugLog("Custom LLM event emitted for server processing")
        return .proceed
    }
}

// MARK: - 17. Google Meet Handler

/// Handles Google Meet integration nodes
/// Creates Google Meet meetings via server-side integration
/// Server processes via execute-integration event
public final class GoogleMeetHandler: BaseIntegrationHandler {
    public override class var nodeType: String { NodeTypes.Integration.googleMeet }

    public override func handle(nodeData: [String: Any], state: NodeState) async -> NodeHandlerResult {
        debugLog("Processing Google Meet node")

        guard state.isSocketConnected else {
            return .error(.socketNotConnected)
        }

        // Extract operation type (book, create, etc.)
        let operation = nodeData["operation"] as? String ?? "book"

        // Handle booking operation - display calendar UI for meeting selection
        if operation == "book" {
            // Extract timezone
            let timezone = (nodeData["timeZone"] as? String) ?? TimeZone.current.identifier

            // Extract answer variable name for storing the result
            let answerVariable = nodeData["answerVariable"] as? String ?? "meet_booking"

            // Extract meeting configuration
            let meetingTitle = (nodeData["title"] as? String).map { state.resolveVariables(in: $0) }
            let meetingDescription = (nodeData["description"] as? String).map { state.resolveVariables(in: $0) }
            let duration = nodeData["duration"] as? Int ?? 30 // Default 30 minutes

            // Extract attendee configuration
            let collectAttendeeEmail = nodeData["collectAttendeeEmail"] as? Bool ?? false
            let collectAttendeeName = nodeData["collectAttendeeName"] as? Bool ?? false

            // Extract slot configuration if provided
            var availableSlots: [[String: Any]]?
            if let slots = nodeData["availableSlots"] as? [[String: Any]] {
                availableSlots = slots.map { resolveVariablesInDictionary($0, state: state) }
            }

            // Extract calendar settings
            let calendarId = (nodeData["calendarId"] as? String).map { state.resolveVariables(in: $0) }
            let minDate = nodeData["minDate"] as? String
            let maxDate = nodeData["maxDate"] as? String
            let excludeWeekends = nodeData["excludeWeekends"] as? Bool ?? false

            // Build payload for server
            var payload: [String: Any] = [
                "chatSessionId": state.chatSessionId,
                "botId": state.botId,
                "nodeType": "google_meet",
                "operation": operation,
                "timezone": timezone,
                "answerVariable": answerVariable,
                "duration": duration,
                "collectAttendeeEmail": collectAttendeeEmail,
                "collectAttendeeName": collectAttendeeName,
                "excludeWeekends": excludeWeekends,
                "variables": state.variables
            ]

            // Add optional fields
            if let title = meetingTitle { payload["title"] = title }
            if let desc = meetingDescription { payload["description"] = desc }
            if let slots = availableSlots { payload["availableSlots"] = slots }
            if let calId = calendarId { payload["calendarId"] = calId }
            if let min = minDate { payload["minDate"] = min }
            if let max = maxDate { payload["maxDate"] = max }

            // Add user info from state if available
            if let email = state.getValue(forKey: "email") as? String {
                payload["attendeeEmail"] = email
            }
            if let name = state.getValue(forKey: "name") as? String {
                payload["attendeeName"] = name
            }

            // Build standardized execute-integration payload for server
            let bookNodeId = nodeData["id"] as? String ?? nodeData["nodeId"] as? String ?? ""
            let bookIntegrationPayload: [String: Any] = [
                "nodeType": Self.nodeType,
                "nodeId": bookNodeId,
                "nodeData": nodeData,
                "chatSessionId": state.chatSessionId,
                "chatbotId": state.botId,
                "workspaceId": state.getValue(forKey: "_workspaceId") ?? "",
                "answerVariables": state.getValue(forKey: "_answerVariables") ?? [],
            ]

            // Emit socket event for server to process and prepare calendar slots
            state.emitSocketEvent("execute-integration", data: bookIntegrationPayload)

            // Return display UI for calendar/meeting selection
            let uiData: [String: Any] = [
                "timezone": timezone,
                "title": meetingTitle ?? "Schedule a Google Meet",
                "duration": duration,
                "collectAttendeeEmail": collectAttendeeEmail,
                "collectAttendeeName": collectAttendeeName,
                "answerVariable": answerVariable,
                "availableSlots": availableSlots as Any,
                "minDate": minDate as Any,
                "maxDate": maxDate as Any,
                "excludeWeekends": excludeWeekends
            ]

            debugLog("Google Meet booking UI requested with timezone: \(timezone)")
            return .displayUI(type: .calendlyEmbed, data: uiData)
        }

        // Handle direct meeting creation (no calendar UI needed)
        if operation == "create" {
            // Extract meeting configuration
            let meetingTitle = (nodeData["title"] as? String).map { state.resolveVariables(in: $0) }
                ?? "Meeting"
            let meetingDescription = (nodeData["description"] as? String).map { state.resolveVariables(in: $0) }
            let startTime = (nodeData["startTime"] as? String).map { state.resolveVariables(in: $0) }
            let endTime = (nodeData["endTime"] as? String).map { state.resolveVariables(in: $0) }
            let duration = nodeData["duration"] as? Int ?? 30
            let timezone = (nodeData["timeZone"] as? String) ?? TimeZone.current.identifier

            // Extract attendees
            var attendees: [String] = []
            if let attendeeList = nodeData["attendees"] as? [String] {
                attendees = attendeeList.map { state.resolveVariables(in: $0) }
            }
            if let singleAttendee = nodeData["attendeeEmail"] as? String {
                let resolved = state.resolveVariables(in: singleAttendee)
                if !resolved.isEmpty && !attendees.contains(resolved) {
                    attendees.append(resolved)
                }
            }
            // Add email from state if available
            if let email = state.getValue(forKey: "email") as? String, !attendees.contains(email) {
                attendees.append(email)
            }

            // Extract response variable name
            let responseVariable = nodeData["responseVariable"] as? String ?? "meet_link"

            // Build payload for server
            var payload: [String: Any] = [
                "chatSessionId": state.chatSessionId,
                "botId": state.botId,
                "nodeType": "google_meet",
                "operation": operation,
                "title": meetingTitle,
                "duration": duration,
                "timezone": timezone,
                "attendees": attendees,
                "responseVariable": responseVariable,
                "variables": state.variables
            ]

            if let desc = meetingDescription { payload["description"] = desc }
            if let start = startTime { payload["startTime"] = start }
            if let end = endTime { payload["endTime"] = end }

            // Build standardized execute-integration payload
            let createNodeId = nodeData["id"] as? String ?? nodeData["nodeId"] as? String ?? ""
            let createIntegrationPayload: [String: Any] = [
                "nodeType": Self.nodeType,
                "nodeId": createNodeId,
                "nodeData": nodeData,
                "chatSessionId": state.chatSessionId,
                "chatbotId": state.botId,
                "workspaceId": state.getValue(forKey: "_workspaceId") ?? "",
                "answerVariables": state.getValue(forKey: "_answerVariables") ?? [],
            ]

            // Emit socket event for server to create meeting
            state.emitSocketEvent("execute-integration", data: createIntegrationPayload)

            debugLog("Google Meet creation request sent to server")
            return .proceed
        }

        // Handle other operations (list, cancel, etc.)
        let nodeId = nodeData["id"] as? String ?? nodeData["nodeId"] as? String ?? ""
        let integrationPayload: [String: Any] = [
            "nodeType": Self.nodeType,
            "nodeId": nodeId,
            "nodeData": nodeData,
            "chatSessionId": state.chatSessionId,
            "chatbotId": state.botId,
            "workspaceId": state.getValue(forKey: "_workspaceId") ?? "",
            "answerVariables": state.getValue(forKey: "_answerVariables") ?? [],
        ]

        // Emit socket event for server processing
        state.emitSocketEvent("execute-integration", data: integrationPayload)

        debugLog("Google Meet \(operation) event emitted for server processing")
        return .proceed
    }
}

// MARK: - 17b. Google Calendar Handler

/// Handles Google Calendar integration nodes for booking calendar appointments
/// Server-side processing via socket event with optional calendar selection UI
public final class GoogleCalendarHandler: BaseIntegrationHandler {
    public override class var nodeType: String { NodeTypes.Integration.googleCalendar }

    public override func handle(nodeData: [String: Any], state: NodeState) async -> NodeHandlerResult {
        debugLog("Processing Google Calendar node")

        guard state.isSocketConnected else {
            return .error(.socketNotConnected)
        }

        // Extract operation type (book, create, list, etc.)
        let operation = nodeData["operation"] as? String ?? "book"

        // Handle booking operation - display calendar UI for slot selection
        if operation == "book" {
            return await handleBookOperation(nodeData: nodeData, state: state)
        }

        // Handle create operation - create an event directly
        if operation == "create" {
            return await handleCreateOperation(nodeData: nodeData, state: state)
        }

        // Handle list operation - list available slots
        if operation == "list" {
            return await handleListOperation(nodeData: nodeData, state: state)
        }

        // Handle other operations (update, delete, etc.)
        return await handleGenericOperation(operation: operation, nodeData: nodeData, state: state)
    }

    // MARK: - Book Operation

    /// Handles the "book" operation - displays calendar UI for user to select a time slot
    private func handleBookOperation(nodeData: [String: Any], state: NodeState) async -> NodeHandlerResult {
        // Extract timezone (default to device timezone)
        let timezone = (nodeData["timeZone"] as? String) ?? TimeZone.current.identifier

        // Extract answer variable name for storing the booking result
        let answerVariable = nodeData["answerVariable"] as? String ?? "calendar_booking"

        // Extract event configuration
        let eventTitle = (nodeData["title"] as? String).map { state.resolveVariables(in: $0) }
        let eventDescription = (nodeData["description"] as? String).map { state.resolveVariables(in: $0) }
        let duration = nodeData["duration"] as? Int ?? 30 // Default 30 minutes
        let location = (nodeData["location"] as? String).map { state.resolveVariables(in: $0) }

        // Extract attendee collection settings
        let collectAttendeeEmail = nodeData["collectAttendeeEmail"] as? Bool ?? false
        let collectAttendeeName = nodeData["collectAttendeeName"] as? Bool ?? false

        // Extract calendar settings
        let calendarId = (nodeData["calendarId"] as? String).map { state.resolveVariables(in: $0) }
        let minDate = nodeData["minDate"] as? String
        let maxDate = nodeData["maxDate"] as? String
        let excludeWeekends = nodeData["excludeWeekends"] as? Bool ?? false

        // Extract slot configuration if pre-defined slots are provided
        var availableSlots: [[String: Any]]?
        if let slots = nodeData["availableSlots"] as? [[String: Any]] {
            availableSlots = slots.map { resolveVariablesInDictionary($0, state: state) }
        }

        // Extract business hours configuration
        var businessHours: [String: Any]?
        if let hours = nodeData["businessHours"] as? [String: Any] {
            businessHours = resolveVariablesInDictionary(hours, state: state)
        }

        // Build payload for server
        var payload: [String: Any] = [
            "chatSessionId": state.chatSessionId,
            "botId": state.botId,
            "nodeType": NodeTypes.Integration.googleCalendar,
            "operation": "book",
            "timezone": timezone,
            "answerVariable": answerVariable,
            "duration": duration,
            "collectAttendeeEmail": collectAttendeeEmail,
            "collectAttendeeName": collectAttendeeName,
            "excludeWeekends": excludeWeekends,
            "variables": state.variables
        ]

        // Add optional fields
        if let title = eventTitle { payload["title"] = title }
        if let desc = eventDescription { payload["description"] = desc }
        if let loc = location { payload["location"] = loc }
        if let slots = availableSlots { payload["availableSlots"] = slots }
        if let calId = calendarId { payload["calendarId"] = calId }
        if let min = minDate { payload["minDate"] = min }
        if let max = maxDate { payload["maxDate"] = max }
        if let hours = businessHours { payload["businessHours"] = hours }

        // Add user info from state if available
        if let email = state.getValue(forKey: "email") as? String {
            payload["attendeeEmail"] = email
        }
        if let name = state.getValue(forKey: "name") as? String {
            payload["attendeeName"] = name
        }

        // Build standardized execute-integration payload for server
        let bookNodeId = nodeData["id"] as? String ?? nodeData["nodeId"] as? String ?? ""
        let bookIntegrationPayload: [String: Any] = [
            "nodeType": Self.nodeType,
            "nodeId": bookNodeId,
            "nodeData": nodeData,
            "chatSessionId": state.chatSessionId,
            "chatbotId": state.botId,
            "workspaceId": state.getValue(forKey: "_workspaceId") ?? "",
            "answerVariables": state.getValue(forKey: "_answerVariables") ?? [],
        ]

        // Emit socket event for server to process and prepare available calendar slots
        state.emitSocketEvent("execute-integration", data: bookIntegrationPayload)

        // Return display UI for calendar/slot selection
        // The UI will show a date/time picker for the user to select an appointment slot
        let uiData: [String: Any] = [
            "type": "googleCalendar",
            "operation": "book",
            "timezone": timezone,
            "title": eventTitle ?? "Select a date and time",
            "duration": duration,
            "collectAttendeeEmail": collectAttendeeEmail,
            "collectAttendeeName": collectAttendeeName,
            "answerVariable": answerVariable,
            "availableSlots": availableSlots as Any,
            "minDate": minDate as Any,
            "maxDate": maxDate as Any,
            "excludeWeekends": excludeWeekends,
            "businessHours": businessHours as Any
        ]

        debugLog("Google Calendar booking UI requested with timezone: \(timezone)")
        return .displayUI(type: .calendlyEmbed, data: uiData)
    }

    // MARK: - Create Operation

    /// Handles the "create" operation - creates a calendar event directly without UI
    private func handleCreateOperation(nodeData: [String: Any], state: NodeState) async -> NodeHandlerResult {
        // Extract event configuration
        let eventTitle = (nodeData["title"] as? String).map { state.resolveVariables(in: $0) }
            ?? "Calendar Event"
        let eventDescription = (nodeData["description"] as? String).map { state.resolveVariables(in: $0) }
        let startTime = (nodeData["startTime"] as? String).map { state.resolveVariables(in: $0) }
        let endTime = (nodeData["endTime"] as? String).map { state.resolveVariables(in: $0) }
        let duration = nodeData["duration"] as? Int ?? 30
        let timezone = (nodeData["timeZone"] as? String) ?? TimeZone.current.identifier
        let location = (nodeData["location"] as? String).map { state.resolveVariables(in: $0) }

        // Extract calendar ID
        let calendarId = (nodeData["calendarId"] as? String).map { state.resolveVariables(in: $0) }

        // Extract attendees
        var attendees: [String] = []
        if let attendeeList = nodeData["attendees"] as? [String] {
            attendees = attendeeList.map { state.resolveVariables(in: $0) }
        }
        if let singleAttendee = nodeData["attendeeEmail"] as? String {
            let resolved = state.resolveVariables(in: singleAttendee)
            if !resolved.isEmpty && !attendees.contains(resolved) {
                attendees.append(resolved)
            }
        }
        // Add email from state if available and not already present
        if let email = state.getValue(forKey: "email") as? String, !attendees.contains(email) {
            attendees.append(email)
        }

        // Extract reminders configuration
        var reminders: [String: Any]?
        if let reminderConfig = nodeData["reminders"] as? [String: Any] {
            reminders = resolveVariablesInDictionary(reminderConfig, state: state)
        }

        // Extract response variable name
        let responseVariable = nodeData["responseVariable"] as? String ?? "calendar_event"

        // Build payload for server
        var payload: [String: Any] = [
            "chatSessionId": state.chatSessionId,
            "botId": state.botId,
            "nodeType": NodeTypes.Integration.googleCalendar,
            "operation": "create",
            "title": eventTitle,
            "duration": duration,
            "timezone": timezone,
            "attendees": attendees,
            "responseVariable": responseVariable,
            "variables": state.variables
        ]

        if let desc = eventDescription { payload["description"] = desc }
        if let start = startTime { payload["startTime"] = start }
        if let end = endTime { payload["endTime"] = end }
        if let loc = location { payload["location"] = loc }
        if let calId = calendarId { payload["calendarId"] = calId }
        if let rem = reminders { payload["reminders"] = rem }

        // Build standardized execute-integration payload
        let createNodeId = nodeData["id"] as? String ?? nodeData["nodeId"] as? String ?? ""
        let createIntegrationPayload: [String: Any] = [
            "nodeType": GoogleCalendarHandler.nodeType,
            "nodeId": createNodeId,
            "nodeData": nodeData,
            "chatSessionId": state.chatSessionId,
            "chatbotId": state.botId,
            "workspaceId": state.getValue(forKey: "_workspaceId") ?? "",
            "answerVariables": state.getValue(forKey: "_answerVariables") ?? [],
        ]

        // Emit socket event for server to create the calendar event
        state.emitSocketEvent("execute-integration", data: createIntegrationPayload)

        debugLog("Google Calendar event creation request sent to server")
        return .proceed
    }

    // MARK: - List Operation

    /// Handles the "list" operation - retrieves available time slots
    private func handleListOperation(nodeData: [String: Any], state: NodeState) async -> NodeHandlerResult {
        let timezone = (nodeData["timeZone"] as? String) ?? TimeZone.current.identifier
        let calendarId = (nodeData["calendarId"] as? String).map { state.resolveVariables(in: $0) }
        let minDate = nodeData["minDate"] as? String
        let maxDate = nodeData["maxDate"] as? String
        let duration = nodeData["duration"] as? Int ?? 30
        let responseVariable = nodeData["responseVariable"] as? String ?? "available_slots"

        var payload: [String: Any] = [
            "chatSessionId": state.chatSessionId,
            "botId": state.botId,
            "nodeType": NodeTypes.Integration.googleCalendar,
            "operation": "list",
            "timezone": timezone,
            "duration": duration,
            "responseVariable": responseVariable,
            "variables": state.variables
        ]

        if let calId = calendarId { payload["calendarId"] = calId }
        if let min = minDate { payload["minDate"] = min }
        if let max = maxDate { payload["maxDate"] = max }

        // Build standardized execute-integration payload
        let listNodeId = nodeData["id"] as? String ?? nodeData["nodeId"] as? String ?? ""
        let listIntegrationPayload: [String: Any] = [
            "nodeType": GoogleCalendarHandler.nodeType,
            "nodeId": listNodeId,
            "nodeData": nodeData,
            "chatSessionId": state.chatSessionId,
            "chatbotId": state.botId,
            "workspaceId": state.getValue(forKey: "_workspaceId") ?? "",
            "answerVariables": state.getValue(forKey: "_answerVariables") ?? [],
        ]

        state.emitSocketEvent("execute-integration", data: listIntegrationPayload)

        debugLog("Google Calendar list slots request sent to server")
        return .proceed
    }

    // MARK: - Generic Operation

    /// Handles other operations (update, delete, etc.)
    private func handleGenericOperation(
        operation: String,
        nodeData: [String: Any],
        state: NodeState
    ) async -> NodeHandlerResult {
        var payload: [String: Any] = [
            "chatSessionId": state.chatSessionId,
            "botId": state.botId,
            "nodeType": NodeTypes.Integration.googleCalendar,
            "operation": operation,
            "variables": state.variables
        ]

        // Build standardized execute-integration payload
        let genericNodeId = nodeData["id"] as? String ?? nodeData["nodeId"] as? String ?? ""
        let genericIntegrationPayload: [String: Any] = [
            "nodeType": GoogleCalendarHandler.nodeType,
            "nodeId": genericNodeId,
            "nodeData": nodeData,
            "chatSessionId": state.chatSessionId,
            "chatbotId": state.botId,
            "workspaceId": state.getValue(forKey: "_workspaceId") ?? "",
            "answerVariables": state.getValue(forKey: "_answerVariables") ?? [],
        ]

        // Emit socket event for server processing
        state.emitSocketEvent("execute-integration", data: genericIntegrationPayload)

        debugLog("Google Calendar \(operation) event emitted for server processing")
        return .proceed
    }
}

// MARK: - 18. Human Handover Handler

/// Handles human handover integration nodes
/// Returns displayUI result for showing handover UI and notifies server
public final class HumanHandoverHandler: BaseIntegrationHandler {
    public override class var nodeType: String { NodeTypes.Special.humanHandover }

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

        // Notify server of handover request — payload matches web widget format
        if state.isSocketConnected {
            let workspaceId = state.getValue(forKey: "_workspaceId") as? String ?? ""
            let botName = state.getValue(forKey: "_botName") as? String ?? ""
            let maxWaitTime = (nodeData["maxWaitTime"] as? Int) ?? 2

            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let now = dateFormatter.string(from: Date())

            // Build chatMetaData matching web widget format exactly
            let chatMetaData: [String: Any] = [
                "version": "v2",
                "workspaceId": workspaceId,
                "chatSessionId": state.chatSessionId,
                "botId": state.botId,
                "botName": botName,
                "chatDate": now,
                "deviceInfo": "iOS/\(ProcessInfo.processInfo.operatingSystemVersionString)",
                "location": TimeZone.current.identifier,
                "record": conversationSummary,
                "answerVariables": state.variables.filter { !$0.key.hasPrefix("_") },
                "transcript": [] as [[String: String]]
            ]

            // Build visitor metaData
            let metaData: [String: Any] = [
                "visitorId": state.chatSessionId,
                "chatDate": now,
                "deviceInfo": "iOS/\(ProcessInfo.processInfo.operatingSystemVersionString)",
                "location": TimeZone.current.identifier
            ]

            var handoverPayload: [String: Any] = [
                "workspaceId": workspaceId,
                "chatbotId": state.botId,
                "chatbotName": botName,
                "chatSessionId": state.chatSessionId,
                "chatMetaData": chatMetaData,
                "metaData": metaData,
                "priority": priority,
                "maxWaitTime": maxWaitTime,
                "assignmentType": (nodeData["assignmentType"] as? String) ?? "auto",
                "assignmentStrategy": (nodeData["agentAssignmentStrategy"] as? String) ?? "",
                "assignedAgents": (nodeData["assignedAgents"] as? [String]) ?? [],
                "assignedAIAgents": (nodeData["assignedAIAgents"] as? [String]) ?? []
            ]

            if let dept = department { handoverPayload["department"] = dept }

            // Send response-record before handover so the server has the
            // Response document when creating the ticket/notification
            state.emitSocketEvent("response-record", data: [
                "chatSessionId": state.chatSessionId,
                "botId": state.botId,
                "record": (state.getValue(forKey: "_record") as? [[String: Any]]) ?? [],
                "answerVariables": (state.getValue(forKey: "_answerVariables") as? [[String: Any]]) ?? [],
                "channel": "mobile",
            ])

            // Re-join chat room to ensure socket is in the correct room
            state.emitSocketEvent("join-chat-room-visitor", data: ["chatSessionId": state.chatSessionId])

            state.emitSocketEvent(SocketEvents.initiateHandover, data: handoverPayload)
            debugLog("Human handover request sent to server with full chatMetaData")
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

// MARK: - 19. Airtable Handler

/// Handles Airtable integration nodes
/// Server-side processing - emits socket event for server to perform CRUD operations on Airtable
public final class AirtableHandler: BaseIntegrationHandler {
    public override class var nodeType: String { NodeTypes.Integration.airtable }

    public override func handle(nodeData: [String: Any], state: NodeState) async -> NodeHandlerResult {
        debugLog("Processing Airtable node")

        guard state.isSocketConnected else {
            return .error(.socketNotConnected)
        }

        // Extract operation type (create, read, update, delete)
        let operation = nodeData["operation"] as? String ?? "create"

        // Extract base and table configuration
        let baseId = (nodeData["baseId"] as? String).map { state.resolveVariables(in: $0) }
        let tableName = (nodeData["tableName"] as? String).map { state.resolveVariables(in: $0) }

        // Extract record ID for update/delete operations
        let recordId = (nodeData["recordId"] as? String).map { state.resolveVariables(in: $0) }

        // Extract record data for create/update operations
        var recordData: [String: Any] = [:]
        if let data = nodeData["recordData"] as? [String: Any] {
            recordData = resolveVariablesInDictionary(data, state: state)
        }

        // Extract field mappings if provided
        var fieldMappings: [[String: Any]] = []
        if let mappings = nodeData["fieldMappings"] as? [[String: Any]] {
            for mapping in mappings {
                var resolvedMapping: [String: Any] = [:]
                if let field = mapping["field"] as? String {
                    resolvedMapping["field"] = field
                }
                if let column = mapping["column"] as? String {
                    resolvedMapping["column"] = column
                }
                if let value = mapping["value"] as? String {
                    resolvedMapping["value"] = state.resolveVariables(in: value)
                }
                if let variableName = mapping["variableName"] as? String,
                   let variableValue = state.getValue(forKey: variableName) {
                    resolvedMapping["value"] = variableValue
                }
                fieldMappings.append(resolvedMapping)
            }
        }

        // Extract filter formula for read operations
        let filterFormula = (nodeData["filterFormula"] as? String).map { state.resolveVariables(in: $0) }

        // Extract view name for read operations
        let viewName = nodeData["viewName"] as? String

        // Extract max records for read operations
        let maxRecords = nodeData["maxRecords"] as? Int

        // Extract sort configuration for read operations
        var sortConfig: [[String: Any]]?
        if let sort = nodeData["sort"] as? [[String: Any]] {
            sortConfig = sort.map { resolveVariablesInDictionary($0, state: state) }
        }

        // Extract response variable name
        let responseVariable = nodeData["responseVariable"] as? String ?? "airtable_response"

        // Prepare socket payload
        var payload: [String: Any] = [
            "chatSessionId": state.chatSessionId,
            "botId": state.botId,
            "nodeType": "airtable",
            "operation": operation,
            "responseVariable": responseVariable,
            "variables": state.variables
        ]

        // Add base/table configuration
        if let base = baseId { payload["baseId"] = base }
        if let table = tableName { payload["tableName"] = table }

        // Add operation-specific data
        if let recId = recordId { payload["recordId"] = recId }
        if !recordData.isEmpty { payload["recordData"] = recordData }
        if !fieldMappings.isEmpty { payload["fieldMappings"] = fieldMappings }

        // Add read operation specific fields
        if let filter = filterFormula { payload["filterFormula"] = filter }
        if let view = viewName { payload["viewName"] = view }
        if let maxRecs = maxRecords { payload["maxRecords"] = maxRecs }
        if let sort = sortConfig { payload["sort"] = sort }

        // Build standardized execute-integration payload
        let nodeId = nodeData["id"] as? String ?? nodeData["nodeId"] as? String ?? ""
        let integrationPayload: [String: Any] = [
            "nodeType": Self.nodeType,
            "nodeId": nodeId,
            "nodeData": nodeData,
            "chatSessionId": state.chatSessionId,
            "chatbotId": state.botId,
            "workspaceId": state.getValue(forKey: "_workspaceId") ?? "",
            "answerVariables": state.getValue(forKey: "_answerVariables") ?? [],
        ]

        // Emit socket event for server processing
        state.emitSocketEvent("execute-integration", data: integrationPayload)

        debugLog("Airtable \(operation) event emitted for server processing")
        return .proceed
    }
}

// MARK: - 21. Zoho CRM Handler

/// Handles Zoho CRM integration nodes
/// Creates/updates records in Zoho CRM modules (Contacts, Leads, Deals, etc.)
/// Server-side processing - emits socket event for server to handle
public final class ZohoCRMHandler: BaseIntegrationHandler {
    public override class var nodeType: String { NodeTypes.Integration.zohoCrm }

    public override func handle(nodeData: [String: Any], state: NodeState) async -> NodeHandlerResult {
        debugLog("Processing Zoho CRM node")

        guard state.isSocketConnected else {
            return .error(.socketNotConnected)
        }

        // Extract operation type (create, update, upsert, search, get)
        let operation = nodeData["operation"] as? String ?? "create"

        // Extract module name (Contacts, Leads, Deals, Accounts, etc.)
        let module = nodeData["module"] as? String ?? "Contacts"

        // Extract record ID for update/get operations
        let recordId = (nodeData["recordId"] as? String).map { state.resolveVariables(in: $0) }

        // Extract and resolve record data
        var recordData: [String: Any] = [:]
        if let data = nodeData["recordData"] as? [String: Any] {
            recordData = resolveVariablesInDictionary(data, state: state)
        }

        // Extract field mappings (maps Zoho fields to chat variables)
        if let mappings = nodeData["fieldMappings"] as? [String: String] {
            for (zohoField, variableName) in mappings {
                if let value = state.getValue(forKey: variableName) {
                    recordData[zohoField] = value
                }
            }
        }

        // Extract column mappings (alternative format for field mappings)
        if let columnMappings = nodeData["columnMappings"] as? [[String: Any]] {
            for mapping in columnMappings {
                if let field = mapping["field"] as? String ?? mapping["column"] as? String,
                   let value = mapping["value"] as? String {
                    let resolvedValue = state.resolveVariables(in: value)
                    recordData[field] = resolvedValue
                }
            }
        }

        // Common field mappings from state for contact-type modules
        if ["Contacts", "Leads"].contains(module) {
            if recordData["Email"] == nil, let email = state.getValue(forKey: "email") as? String {
                recordData["Email"] = email
            }
            if recordData["First_Name"] == nil, let name = state.getValue(forKey: "name") as? String {
                // Try to split full name into first/last
                let nameParts = name.split(separator: " ")
                if nameParts.count > 1 {
                    recordData["First_Name"] = String(nameParts[0])
                    recordData["Last_Name"] = nameParts.dropFirst().joined(separator: " ")
                } else {
                    recordData["First_Name"] = name
                }
            }
            if recordData["Phone"] == nil, let phone = state.getValue(forKey: "phone") as? String {
                recordData["Phone"] = phone
            }
            if recordData["Company"] == nil, let company = state.getValue(forKey: "company") as? String {
                recordData["Company"] = company
            }
        }

        // Extract search criteria for search operation
        var searchCriteria: [String: Any]?
        if operation == "search" {
            if let criteria = nodeData["searchCriteria"] as? [String: Any] {
                searchCriteria = resolveVariablesInDictionary(criteria, state: state)
            } else if let searchField = nodeData["searchField"] as? String,
                      let searchValue = nodeData["searchValue"] as? String {
                searchCriteria = [
                    "field": searchField,
                    "value": state.resolveVariables(in: searchValue)
                ]
            }
        }

        // Extract duplicate check field for upsert
        let duplicateCheckField = nodeData["duplicateCheckField"] as? String

        // Extract response variable name
        let responseVariable = nodeData["responseVariable"] as? String ?? "zoho_response"

        // Extract answer variable for storing specific response data
        let answerVariable = nodeData["answerVariable"] as? String

        // Build socket payload
        var payload: [String: Any] = [
            "chatSessionId": state.chatSessionId,
            "botId": state.botId,
            "nodeType": "zoho_crm",
            "operation": operation,
            "module": module,
            "recordData": recordData,
            "responseVariable": responseVariable,
            "variables": state.variables
        ]

        // Add optional fields to payload
        if let id = recordId { payload["recordId"] = id }
        if let criteria = searchCriteria { payload["searchCriteria"] = criteria }
        if let dupField = duplicateCheckField { payload["duplicateCheckField"] = dupField }
        if let ansVar = answerVariable { payload["answerVariable"] = ansVar }

        // Include trigger fields if specified (for workflow triggers)
        if let triggerFields = nodeData["triggerFields"] as? [String] {
            payload["triggerFields"] = triggerFields
        }

        // Include layout ID if specified
        if let layoutId = nodeData["layoutId"] as? String {
            payload["layoutId"] = layoutId
        }

        // Build standardized execute-integration payload
        let nodeId = nodeData["id"] as? String ?? nodeData["nodeId"] as? String ?? ""
        let integrationPayload: [String: Any] = [
            "nodeType": Self.nodeType,
            "nodeId": nodeId,
            "nodeData": nodeData,
            "chatSessionId": state.chatSessionId,
            "chatbotId": state.botId,
            "workspaceId": state.getValue(forKey: "_workspaceId") ?? "",
            "answerVariables": state.getValue(forKey: "_answerVariables") ?? [],
        ]

        // Emit socket event for server processing
        state.emitSocketEvent("execute-integration", data: integrationPayload)

        debugLog("Zoho CRM \(operation) event emitted for module: \(module)")
        return .proceed
    }
}

// MARK: - 22. Google Docs Handler

/// Handles Google Docs integration nodes
/// Server-side processing - emits socket event for server to create/update Google Docs
public final class GoogleDocsHandler: BaseIntegrationHandler {
    public override class var nodeType: String { NodeTypes.Integration.googleDocs }

    public override func handle(nodeData: [String: Any], state: NodeState) async -> NodeHandlerResult {
        debugLog("Processing Google Docs node")

        guard state.isSocketConnected else {
            return .error(.socketNotConnected)
        }

        // Extract operation type (create, update, append, read)
        let operation = nodeData["operation"] as? String ?? "create"

        // Extract document configuration
        let documentId = (nodeData["documentId"] as? String).map { state.resolveVariables(in: $0) }
        let title = (nodeData["title"] as? String).map { state.resolveVariables(in: $0) }

        // Extract content for create/update/append operations
        let content = (nodeData["content"] as? String).map { state.resolveVariables(in: $0) }

        // Extract folder ID for create operations (where to store the new document)
        let folderId = (nodeData["folderId"] as? String).map { state.resolveVariables(in: $0) }

        // Extract template configuration for create operations
        let templateId = (nodeData["templateId"] as? String).map { state.resolveVariables(in: $0) }

        // Extract field mappings for template-based creation
        var fieldMappings: [[String: Any]] = []
        if let mappings = nodeData["fieldMappings"] as? [[String: Any]] {
            for mapping in mappings {
                var resolvedMapping: [String: Any] = [:]
                if let placeholder = mapping["placeholder"] as? String {
                    resolvedMapping["placeholder"] = placeholder
                }
                if let value = mapping["value"] as? String {
                    resolvedMapping["value"] = state.resolveVariables(in: value)
                }
                if let variableName = mapping["variableName"] as? String,
                   let variableValue = state.getValue(forKey: variableName) {
                    if let stringValue = variableValue as? String {
                        resolvedMapping["value"] = stringValue
                    } else {
                        resolvedMapping["value"] = String(describing: variableValue)
                    }
                }
                fieldMappings.append(resolvedMapping)
            }
        }

        // Extract text replacement pairs for update operations
        var replacements: [[String: String]] = []
        if let replaceList = nodeData["replacements"] as? [[String: String]] {
            for replacement in replaceList {
                var resolvedReplacement: [String: String] = [:]
                if let find = replacement["find"] {
                    resolvedReplacement["find"] = state.resolveVariables(in: find)
                }
                if let replaceWith = replacement["replace"] {
                    resolvedReplacement["replace"] = state.resolveVariables(in: replaceWith)
                }
                replacements.append(resolvedReplacement)
            }
        }

        // Extract position for append/insert operations
        let insertPosition = nodeData["insertPosition"] as? String ?? "end" // start, end, or index
        let insertIndex = nodeData["insertIndex"] as? Int

        // Extract sharing configuration
        var sharing: [String: Any]?
        if let shareConfig = nodeData["sharing"] as? [String: Any] {
            sharing = resolveVariablesInDictionary(shareConfig, state: state)
        }

        // Extract response variable name
        let responseVariable = nodeData["responseVariable"] as? String ?? "google_docs_response"

        // Prepare socket payload
        var payload: [String: Any] = [
            "chatSessionId": state.chatSessionId,
            "botId": state.botId,
            "nodeType": "google_docs",
            "operation": operation,
            "responseVariable": responseVariable,
            "variables": state.variables
        ]

        // Add document configuration
        if let docId = documentId { payload["documentId"] = docId }
        if let docTitle = title { payload["title"] = docTitle }
        if let docContent = content { payload["content"] = docContent }
        if let folder = folderId { payload["folderId"] = folder }
        if let template = templateId { payload["templateId"] = template }

        // Add field mappings for template operations
        if !fieldMappings.isEmpty { payload["fieldMappings"] = fieldMappings }

        // Add text replacements for update operations
        if !replacements.isEmpty { payload["replacements"] = replacements }

        // Add position information for append/insert operations
        payload["insertPosition"] = insertPosition
        if let index = insertIndex { payload["insertIndex"] = index }

        // Add sharing configuration
        if let share = sharing { payload["sharing"] = share }

        // Build standardized execute-integration payload
        let nodeId = nodeData["id"] as? String ?? nodeData["nodeId"] as? String ?? ""
        let integrationPayload: [String: Any] = [
            "nodeType": Self.nodeType,
            "nodeId": nodeId,
            "nodeData": nodeData,
            "chatSessionId": state.chatSessionId,
            "chatbotId": state.botId,
            "workspaceId": state.getValue(forKey: "_workspaceId") ?? "",
            "answerVariables": state.getValue(forKey: "_answerVariables") ?? [],
        ]

        // Emit socket event for server processing
        state.emitSocketEvent("execute-integration", data: integrationPayload)

        debugLog("Google Docs \(operation) event emitted for server processing")
        return .proceed
    }
}

// MARK: - 24. Google Drive Handler

/// Handles Google Drive integration nodes
/// Supports file/folder operations including upload, download, create, list, share
/// Server-side processing - emits socket event for server to handle Google Drive API calls
public final class GoogleDriveHandler: BaseIntegrationHandler {
    public override class var nodeType: String { NodeTypes.Integration.googleDrive }

    public override func handle(nodeData: [String: Any], state: NodeState) async -> NodeHandlerResult {
        debugLog("Processing Google Drive node")

        guard state.isSocketConnected else {
            return .error(.socketNotConnected)
        }

        // Extract operation type (upload, download, create_folder, list, share, delete, move, copy)
        let operation = nodeData["operation"] as? String ?? "upload"

        // Extract file/folder configuration with variable resolution
        let fileId = (nodeData["fileId"] as? String).map { state.resolveVariables(in: $0) }
        let folderId = (nodeData["folderId"] as? String).map { state.resolveVariables(in: $0) }
        let fileName = (nodeData["fileName"] as? String).map { state.resolveVariables(in: $0) }
        let folderName = (nodeData["folderName"] as? String).map { state.resolveVariables(in: $0) }
        let mimeType = (nodeData["mimeType"] as? String).map { state.resolveVariables(in: $0) }
        let fileContent = (nodeData["fileContent"] as? String).map { state.resolveVariables(in: $0) }
        let fileUrl = (nodeData["fileUrl"] as? String).map { state.resolveVariables(in: $0) }

        // Extract sharing configuration
        let shareEmail = (nodeData["shareEmail"] as? String).map { state.resolveVariables(in: $0) }
        let shareRole = nodeData["shareRole"] as? String ?? "reader" // reader, writer, commenter, owner
        let shareType = nodeData["shareType"] as? String ?? "user" // user, group, domain, anyone
        let sendNotification = nodeData["sendNotification"] as? Bool ?? true

        // Extract search/list configuration
        let query = (nodeData["query"] as? String).map { state.resolveVariables(in: $0) }
        let pageSize = nodeData["pageSize"] as? Int ?? 100
        let orderBy = nodeData["orderBy"] as? String ?? "modifiedTime desc"
        let includeTrash = nodeData["includeTrash"] as? Bool ?? false

        // Extract destination for move/copy operations
        let destinationFolderId = (nodeData["destinationFolderId"] as? String).map { state.resolveVariables(in: $0) }

        // Extract response variable name for storing results
        let responseVariable = nodeData["responseVariable"] as? String ?? "drive_response"

        // Extract field mappings if provided (for storing specific response fields in variables)
        var fieldMappings: [String: String] = [:]
        if let mappings = nodeData["fieldMappings"] as? [String: String] {
            for (responseField, variableName) in mappings {
                fieldMappings[responseField] = state.resolveVariables(in: variableName)
            }
        }

        // Build the payload for server processing
        var payload: [String: Any] = [
            "chatSessionId": state.chatSessionId,
            "botId": state.botId,
            "nodeType": "google_drive",
            "operation": operation,
            "responseVariable": responseVariable,
            "variables": state.variables
        ]

        // Add operation-specific parameters
        switch operation {
        case "upload":
            if let name = fileName { payload["fileName"] = name }
            if let folder = folderId { payload["folderId"] = folder }
            if let mime = mimeType { payload["mimeType"] = mime }
            if let content = fileContent { payload["fileContent"] = content }
            if let url = fileUrl { payload["fileUrl"] = url }

            // Check for file data from a previous file upload node
            if let uploadedFile = state.getValue(forKey: "_uploadedFile") {
                payload["uploadedFile"] = uploadedFile
            }
            if let uploadedFileKey = nodeData["uploadedFileVariable"] as? String,
               let uploadedFile = state.getValue(forKey: uploadedFileKey) {
                payload["uploadedFile"] = uploadedFile
            }

        case "download":
            if let file = fileId { payload["fileId"] = file }
            if let name = fileName { payload["fileName"] = name }

        case "create_folder":
            if let name = folderName ?? fileName { payload["folderName"] = name }
            if let parent = folderId { payload["parentFolderId"] = parent }

        case "list":
            if let folder = folderId { payload["folderId"] = folder }
            if let q = query { payload["query"] = q }
            payload["pageSize"] = pageSize
            payload["orderBy"] = orderBy
            payload["includeTrash"] = includeTrash

        case "share":
            if let file = fileId { payload["fileId"] = file }
            if let email = shareEmail { payload["shareEmail"] = email }
            payload["shareRole"] = shareRole
            payload["shareType"] = shareType
            payload["sendNotification"] = sendNotification

            // Optionally include email message for notification
            if let message = (nodeData["shareMessage"] as? String).map({ state.resolveVariables(in: $0) }) {
                payload["shareMessage"] = message
            }

        case "delete":
            if let file = fileId { payload["fileId"] = file }
            // Optionally support permanent deletion vs trash
            payload["permanent"] = nodeData["permanent"] as? Bool ?? false

        case "move":
            if let file = fileId { payload["fileId"] = file }
            if let dest = destinationFolderId { payload["destinationFolderId"] = dest }

        case "copy":
            if let file = fileId { payload["fileId"] = file }
            if let dest = destinationFolderId { payload["destinationFolderId"] = dest }
            if let name = fileName { payload["newFileName"] = name }

        case "get_info":
            if let file = fileId { payload["fileId"] = file }

        case "search":
            if let q = query { payload["query"] = q }
            payload["pageSize"] = pageSize
            payload["orderBy"] = orderBy
            payload["includeTrash"] = includeTrash

        default:
            // For any custom operations, include all node data with resolved variables
            for (key, value) in nodeData {
                if !["operation", "type", "id", "nodeType"].contains(key) {
                    if let stringValue = value as? String {
                        payload[key] = state.resolveVariables(in: stringValue)
                    } else if let dictValue = value as? [String: Any] {
                        payload[key] = resolveVariablesInDictionary(dictValue, state: state)
                    } else {
                        payload[key] = value
                    }
                }
            }
        }

        // Add field mappings if provided
        if !fieldMappings.isEmpty {
            payload["fieldMappings"] = fieldMappings
        }

        // Build standardized execute-integration payload
        let nodeId = nodeData["id"] as? String ?? nodeData["nodeId"] as? String ?? ""
        let integrationPayload: [String: Any] = [
            "nodeType": Self.nodeType,
            "nodeId": nodeId,
            "nodeData": nodeData,
            "chatSessionId": state.chatSessionId,
            "chatbotId": state.botId,
            "workspaceId": state.getValue(forKey: "_workspaceId") ?? "",
            "answerVariables": state.getValue(forKey: "_answerVariables") ?? [],
        ]

        // Emit socket event for server processing
        state.emitSocketEvent("execute-integration", data: integrationPayload)

        debugLog("Google Drive \(operation) event emitted for server processing")
        return .proceed
    }
}


// MARK: - 22. Notion Handler

/// Handles Notion integration nodes
/// Server-side processing - emits socket event for server to perform operations on Notion databases and pages
public final class NotionHandler: BaseIntegrationHandler {
    public override class var nodeType: String { NodeTypes.Integration.notion }

    public override func handle(nodeData: [String: Any], state: NodeState) async -> NodeHandlerResult {
        debugLog("Processing Notion node")

        guard state.isSocketConnected else {
            return .error(.socketNotConnected)
        }

        // Extract operation type (createPage, updatePage, queryDatabase, createDatabase, etc.)
        let operation = nodeData["operation"] as? String ?? "createPage"

        // Extract database/page configuration
        let databaseId = (nodeData["databaseId"] as? String).map { state.resolveVariables(in: $0) }
        let pageId = (nodeData["pageId"] as? String).map { state.resolveVariables(in: $0) }

        // Extract page properties with variable resolution
        var properties: [String: Any] = [:]
        if let props = nodeData["properties"] as? [String: Any] {
            properties = resolveVariablesInDictionary(props, state: state)
        }

        // Extract property mappings (maps conversation variables to Notion properties)
        if let mappings = nodeData["propertyMappings"] as? [[String: Any]] {
            for mapping in mappings {
                if let notionProperty = mapping["notionProperty"] as? String,
                   let variableName = mapping["variableName"] as? String {
                    // Get value from state variables
                    if let value = state.getValue(forKey: variableName) {
                        // Determine property type and format appropriately
                        let propertyType = mapping["propertyType"] as? String ?? "text"
                        properties[notionProperty] = formatPropertyValue(value, type: propertyType)
                    } else if let defaultValue = mapping["defaultValue"] {
                        let propertyType = mapping["propertyType"] as? String ?? "text"
                        properties[notionProperty] = formatPropertyValue(defaultValue, type: propertyType)
                    }
                }
            }
        }

        // Extract content blocks for page content
        var contentBlocks: [[String: Any]] = []
        if let blocks = nodeData["content"] as? [[String: Any]] {
            contentBlocks = blocks.map { resolveVariablesInDictionary($0, state: state) }
        }

        // Extract page title with variable resolution
        let pageTitle = (nodeData["title"] as? String).map { state.resolveVariables(in: $0) }

        // Extract parent configuration for creating new pages/databases
        var parentConfig: [String: Any]?
        if let parent = nodeData["parent"] as? [String: Any] {
            parentConfig = resolveVariablesInDictionary(parent, state: state)
        }

        // Extract filter for database queries
        var queryFilter: [String: Any]?
        if let filter = nodeData["filter"] as? [String: Any] {
            queryFilter = resolveVariablesInDictionary(filter, state: state)
        }

        // Extract sort configuration for database queries
        var sorts: [[String: Any]]?
        if let sortConfig = nodeData["sorts"] as? [[String: Any]] {
            sorts = sortConfig.map { resolveVariablesInDictionary($0, state: state) }
        }

        // Extract response variable name for storing results
        let responseVariable = nodeData["responseVariable"] as? String ?? "notion_response"

        // Extract icon and cover for page creation
        let icon = (nodeData["icon"] as? String).map { state.resolveVariables(in: $0) }
        let cover = (nodeData["cover"] as? String).map { state.resolveVariables(in: $0) }

        // Build payload for server processing
        var payload: [String: Any] = [
            "chatSessionId": state.chatSessionId,
            "botId": state.botId,
            "nodeType": "notion",
            "operation": operation,
            "responseVariable": responseVariable,
            "variables": state.variables
        ]

        // Add optional fields based on operation
        if let dbId = databaseId { payload["databaseId"] = dbId }
        if let pgId = pageId { payload["pageId"] = pgId }
        if !properties.isEmpty { payload["properties"] = properties }
        if !contentBlocks.isEmpty { payload["content"] = contentBlocks }
        if let title = pageTitle { payload["title"] = title }
        if let parent = parentConfig { payload["parent"] = parent }
        if let filter = queryFilter { payload["filter"] = filter }
        if let sortConfig = sorts { payload["sorts"] = sortConfig }
        if let iconValue = icon { payload["icon"] = iconValue }
        if let coverValue = cover { payload["cover"] = coverValue }

        // Add include/exclude archived option for queries
        if let includeArchived = nodeData["includeArchived"] as? Bool {
            payload["includeArchived"] = includeArchived
        }

        // Add page size for paginated queries
        if let pageSize = nodeData["pageSize"] as? Int {
            payload["pageSize"] = pageSize
        }

        // Add start cursor for pagination
        if let startCursor = nodeData["startCursor"] as? String {
            payload["startCursor"] = state.resolveVariables(in: startCursor)
        }

        // Build standardized execute-integration payload
        let nodeId = nodeData["id"] as? String ?? nodeData["nodeId"] as? String ?? ""
        let integrationPayload: [String: Any] = [
            "nodeType": Self.nodeType,
            "nodeId": nodeId,
            "nodeData": nodeData,
            "chatSessionId": state.chatSessionId,
            "chatbotId": state.botId,
            "workspaceId": state.getValue(forKey: "_workspaceId") ?? "",
            "answerVariables": state.getValue(forKey: "_answerVariables") ?? [],
        ]

        // Emit socket event for server processing
        state.emitSocketEvent("execute-integration", data: integrationPayload)

        debugLog("Notion \(operation) event emitted for server processing")
        return .proceed
    }

    /// Format a value according to the Notion property type
    private func formatPropertyValue(_ value: Any, type: String) -> Any {
        switch type.lowercased() {
        case "title", "rich_text", "text":
            // Text-based properties need to be wrapped in a specific format
            if let stringValue = value as? String {
                return ["type": "text", "value": stringValue]
            }
            return ["type": "text", "value": String(describing: value)]

        case "number":
            // Number properties
            if let numValue = value as? Double {
                return numValue
            }
            if let numValue = value as? Int {
                return Double(numValue)
            }
            if let strValue = value as? String, let num = Double(strValue) {
                return num
            }
            return value

        case "select":
            // Select properties need the option name
            if let stringValue = value as? String {
                return ["name": stringValue]
            }
            return value

        case "multi_select":
            // Multi-select can be an array of option names
            if let arrayValue = value as? [String] {
                return arrayValue.map { ["name": $0] }
            }
            if let stringValue = value as? String {
                // Support comma-separated values
                let options = stringValue.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                return options.map { ["name": $0] }
            }
            return value

        case "date":
            // Date properties
            if let stringValue = value as? String {
                return ["start": stringValue]
            }
            return value

        case "checkbox":
            // Boolean properties
            if let boolValue = value as? Bool {
                return boolValue
            }
            if let stringValue = value as? String {
                return stringValue.lowercased() == "true" || stringValue == "1"
            }
            if let intValue = value as? Int {
                return intValue != 0
            }
            return value

        case "url":
            // URL properties
            if let stringValue = value as? String {
                return stringValue
            }
            return String(describing: value)

        case "email":
            // Email properties
            if let stringValue = value as? String {
                return stringValue
            }
            return String(describing: value)

        case "phone_number":
            // Phone number properties
            if let stringValue = value as? String {
                return stringValue
            }
            return String(describing: value)

        case "relation":
            // Relation properties expect page IDs
            if let arrayValue = value as? [String] {
                return arrayValue.map { ["id": $0] }
            }
            if let stringValue = value as? String {
                return [["id": stringValue]]
            }
            return value

        default:
            // Return as-is for unknown types
            return value
        }
    }
}

// MARK: - 24. Stripe Payment Handler

/// Result of a Stripe payment operation
public struct StripePaymentResult {
    public let success: Bool
    public let paymentUrl: String?
    public let error: String?
    public let data: [String: Any]?

    public init(success: Bool, paymentUrl: String? = nil, error: String? = nil, data: [String: Any]? = nil) {
        self.success = success
        self.paymentUrl = paymentUrl
        self.error = error
        self.data = data
    }
}

/// Handles Stripe payment integration nodes
/// Creates payment links/checkout sessions via server-side integration
/// Fixes the Android bug by properly waiting for the payment URL from the server
public final class StripeHandler: BaseIntegrationHandler {
    public override class var nodeType: String { NodeTypes.Integration.stripe }

    /// Timeout for waiting for payment URL response (in seconds)
    private let paymentUrlTimeout: TimeInterval = 30.0

    public override func handle(nodeData: [String: Any], state: NodeState) async -> NodeHandlerResult {
        debugLog("Processing Stripe node")

        guard state.isSocketConnected else {
            return .error(.socketNotConnected)
        }

        // Extract operation type
        let operation = nodeData["operation"] as? String ?? "createPaymentLink"

        // Extract payment details
        let amount = extractAmount(from: nodeData)
        let currency = (nodeData["currency"] as? String)?.uppercased() ?? "USD"
        let description = (nodeData["description"] as? String).map { state.resolveVariables(in: $0) }

        // Extract product information
        let productName = (nodeData["productName"] as? String).map { state.resolveVariables(in: $0) }
        let productDescription = (nodeData["productDescription"] as? String).map { state.resolveVariables(in: $0) }
        let productImage = nodeData["productImage"] as? String

        // Extract customer information from state
        let customerEmail = (nodeData["customerEmail"] as? String).map { state.resolveVariables(in: $0) }
            ?? state.getValue(forKey: "email") as? String
        let customerName = (nodeData["customerName"] as? String).map { state.resolveVariables(in: $0) }
            ?? state.getValue(forKey: "name") as? String

        // Extract success/cancel URLs for checkout session
        let successUrl = (nodeData["successUrl"] as? String).map { state.resolveVariables(in: $0) }
        let cancelUrl = (nodeData["cancelUrl"] as? String).map { state.resolveVariables(in: $0) }

        // Extract metadata to attach to payment
        var metadata: [String: String] = [:]
        if let customMetadata = nodeData["metadata"] as? [String: Any] {
            for (key, value) in customMetadata {
                if let stringValue = value as? String {
                    metadata[key] = state.resolveVariables(in: stringValue)
                } else {
                    metadata[key] = String(describing: value)
                }
            }
        }
        // Add session info to metadata
        metadata["chatSessionId"] = state.chatSessionId
        metadata["botId"] = state.botId

        // Extract answer variable for storing payment result
        let answerVariable = nodeData["answerVariable"] as? String ?? "stripe_payment"

        // Build socket payload
        var payload: [String: Any] = [
            "chatSessionId": state.chatSessionId,
            "botId": state.botId,
            "nodeType": "stripe",
            "operation": operation,
            "currency": currency,
            "metadata": metadata,
            "answerVariable": answerVariable,
            "variables": state.variables
        ]

        // Add amount (convert to cents for Stripe)
        if let amountValue = amount {
            payload["amount"] = amountValue
            // Also include display amount
            payload["displayAmount"] = Double(amountValue) / 100.0
        }

        // Add optional fields
        if let desc = description { payload["description"] = desc }
        if let prodName = productName { payload["productName"] = prodName }
        if let prodDesc = productDescription { payload["productDescription"] = prodDesc }
        if let prodImage = productImage { payload["productImage"] = prodImage }
        if let email = customerEmail { payload["customerEmail"] = email }
        if let name = customerName { payload["customerName"] = name }
        if let success = successUrl { payload["successUrl"] = success }
        if let cancel = cancelUrl { payload["cancelUrl"] = cancel }

        // For payment operations, we need to wait for the payment URL from server
        if operation == "createPaymentLink" || operation == "createCheckoutSession" {
            let paymentNodeId = nodeData["id"] as? String ?? nodeData["nodeId"] as? String ?? ""
            let paymentIntegrationPayload: [String: Any] = [
                "nodeType": Self.nodeType,
                "nodeId": paymentNodeId,
                "nodeData": nodeData,
                "chatSessionId": state.chatSessionId,
                "chatbotId": state.botId,
                "workspaceId": state.getValue(forKey: "_workspaceId") ?? "",
                "answerVariables": state.getValue(forKey: "_answerVariables") ?? [],
            ]
            return await handlePaymentOperation(
                payload: paymentIntegrationPayload,
                state: state,
                amount: amount,
                currency: currency,
                description: description,
                answerVariable: answerVariable
            )
        }

        // For non-payment operations (createCustomer, listProducts, etc.)
        // Build standardized execute-integration payload
        let nodeId = nodeData["id"] as? String ?? nodeData["nodeId"] as? String ?? ""
        let integrationPayload: [String: Any] = [
            "nodeType": Self.nodeType,
            "nodeId": nodeId,
            "nodeData": nodeData,
            "chatSessionId": state.chatSessionId,
            "chatbotId": state.botId,
            "workspaceId": state.getValue(forKey: "_workspaceId") ?? "",
            "answerVariables": state.getValue(forKey: "_answerVariables") ?? [],
        ]
        state.emitSocketEvent("execute-integration", data: integrationPayload)
        debugLog("Stripe \(operation) event emitted for server processing")
        return .proceed
    }

    /// Handle payment operations that require waiting for URL response
    private func handlePaymentOperation(
        payload: [String: Any],
        state: NodeState,
        amount: Int?,
        currency: String,
        description: String?,
        answerVariable: String
    ) async -> NodeHandlerResult {
        debugLog("Emitting execute-integration and waiting for payment URL response")

        // Create a continuation to wait for the socket response
        return await withCheckedContinuation { continuation in
            var hasResumed = false
            let resumeLock = NSLock()

            // Set up timeout
            let timeoutTask = DispatchWorkItem { [weak state] in
                resumeLock.lock()
                defer { resumeLock.unlock() }

                guard !hasResumed else { return }
                hasResumed = true

                // Remove listener
                state?.removeSocketListener(SocketEvents.stripePaymentUrlResponse)

                self.debugLog("Timeout waiting for Stripe payment URL")
                continuation.resume(returning: .error(.timeout))
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + paymentUrlTimeout, execute: timeoutTask)

            // Set up listener for payment URL response
            state.onSocketEvent(SocketEvents.stripePaymentUrlResponse) { [weak self, weak state] data in
                guard let self = self else { return }

                resumeLock.lock()
                defer { resumeLock.unlock() }

                guard !hasResumed else { return }
                hasResumed = true

                // Cancel timeout
                timeoutTask.cancel()

                // Remove listener
                state?.removeSocketListener(SocketEvents.stripePaymentUrlResponse)

                // Parse response
                guard let responseData = data.first as? [String: Any] else {
                    self.debugLog("Invalid Stripe response format")
                    continuation.resume(returning: .error(.invalidResponse))
                    return
                }

                // Check if this response is for our session
                let responseSessionId = responseData["chatSessionId"] as? String
                if let currentSessionId = state?.chatSessionId, responseSessionId != currentSessionId {
                    // Not our response, ignore and wait for correct one
                    hasResumed = false
                    return
                }

                // Check for error
                if let error = responseData["error"] as? String {
                    self.debugLog("Stripe error: \(error)")
                    continuation.resume(returning: .error(.serverError(error)))
                    return
                }

                // Extract payment URL
                guard let paymentUrl = responseData["url"] as? String, !paymentUrl.isEmpty else {
                    self.debugLog("No payment URL in response")
                    continuation.resume(returning: .error(.serverError("Payment URL not received from server")))
                    return
                }

                self.debugLog("Received payment URL: \(paymentUrl)")

                // Store payment info in state
                let paymentInfo: [String: Any] = [
                    "url": paymentUrl,
                    "amount": amount as Any,
                    "currency": currency,
                    "status": "pending"
                ]
                state?.setValue(paymentInfo, forKey: answerVariable)

                // Return display UI with payment information
                let displayAmount = amount.flatMap { Double($0) / 100.0 }

                let uiData: [String: Any] = [
                    "paymentUrl": paymentUrl,
                    "amount": displayAmount as Any,
                    "currency": currency,
                    "description": description as Any,
                    "answerVariable": answerVariable
                ]

                continuation.resume(returning: .displayUI(type: .externalLink, data: uiData))
            }

            // Emit the socket event to trigger payment URL generation
            state.emitSocketEvent("execute-integration", data: payload)
        }
    }

    /// Extract amount from node data, converting to cents if necessary
    private func extractAmount(from nodeData: [String: Any]) -> Int? {
        // Try customAmount first (from node data)
        if let customAmount = nodeData["customAmount"] {
            return convertToCents(customAmount)
        }

        // Try amount field
        if let amount = nodeData["amount"] {
            return convertToCents(amount)
        }

        // Try price field
        if let price = nodeData["price"] {
            return convertToCents(price)
        }

        return nil
    }

    /// Convert various amount formats to cents (integer)
    private func convertToCents(_ value: Any) -> Int? {
        switch value {
        case let intValue as Int:
            // Assume already in cents if > 1000, otherwise convert
            return intValue > 1000 ? intValue : intValue * 100
        case let doubleValue as Double:
            // Assume in dollars, convert to cents
            return Int(doubleValue * 100)
        case let stringValue as String:
            // Try to parse as double first (dollars)
            if let doubleValue = Double(stringValue) {
                return Int(doubleValue * 100)
            }
            // Try to parse as int (cents)
            if let intValue = Int(stringValue) {
                return intValue > 1000 ? intValue : intValue * 100
            }
            return nil
        default:
            return nil
        }
    }
}

// MARK: - NodeState Socket Event Extensions

extension NodeState {
    /// Register a one-time listener for a socket event
    func onSocketEvent(_ event: String, handler: @escaping ([Any]) -> Void) {
        // This needs to be implemented in the concrete NodeState implementation
        // For DefaultNodeState, we'll add socket listening capability
    }

    /// Remove a socket event listener
    func removeSocketListener(_ event: String) {
        // This needs to be implemented in the concrete NodeState implementation
    }
}

// MARK: - Integration Handler Registry

/// Registry for managing and accessing integration node handlers.
/// This registry uses the IntegrationNodeHandler protocol for handler lookup
/// and can also vend handlers as NodeHandler for use with NodeHandlerRegistry.
public final class IntegrationHandlerRegistry {

    /// Shared singleton instance
    public static let shared = IntegrationHandlerRegistry()

    /// Map of node types to handlers (BaseIntegrationHandler conforms to both protocols)
    private var handlers: [String: BaseIntegrationHandler] = [:]

    private init() {
        registerDefaultHandlers()
    }

    /// Register default integration handlers
    private func registerDefaultHandlers() {
        // Register all integration handlers
        register(WebhookHandler())
        register(GoogleSheetsHandler())
        register(SendEmailHandler())
        register(CalendlyHandler())
        register(GoogleMeetHandler())
        register(GoogleCalendarHandler())
        register(HubspotHandler())
        register(SalesforceHandler())
        register(ZendeskHandler())
        register(SlackHandler())
        register(DiscordHandler())
        register(ZapierHandler())
        register(DialogflowHandler())
        register(OpenAIHandler())
        register(GeminiHandler())
        register(PerplexityHandler())
        register(ClaudeHandler())
        register(GroqHandler())
        register(CustomLLMHandler())
        register(HumanHandoverHandler())
        register(AirtableHandler())
        register(ZohoCRMHandler())
        register(NotionHandler())
        register(GoogleDocsHandler())
        register(GoogleDriveHandler())
        register(StripeHandler())
    }

    /// Register a handler
    public func register(_ handler: BaseIntegrationHandler) {
        handlers[type(of: handler).nodeType] = handler
    }

    /// Get handler for a node type (as IntegrationNodeHandler)
    public func handler(for nodeType: String) -> BaseIntegrationHandler? {
        return handlers[nodeType]
    }

    /// Get handler for a node type as NodeHandler (for use with NodeHandlerRegistry)
    public func nodeHandler(for nodeType: String) -> NodeHandler? {
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

    /// Handle a node with the appropriate handler using IntegrationNodeHandler protocol
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

// MARK: - ChatState to NodeState Adapter

/// Bridges ChatState (used by NodeHandler) to NodeState (used by IntegrationNodeHandler)
/// so that integration handlers can operate on the standard ChatState.
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public class ChatStateNodeStateAdapter: NodeState {

    private let chatState: ChatState
    private weak var socketClient: SocketClient?

    public init(chatState: ChatState, socketClient: SocketClient? = nil) {
        self.chatState = chatState
        self.socketClient = socketClient
    }

    public var chatSessionId: String {
        return chatState.sessionId ?? chatState.getVariable(name: "_sessionId") as? String ?? ""
    }

    public var botId: String {
        return chatState.record["botId"] as? String ?? ""
    }

    public var variables: [String: Any] {
        get { chatState.variables }
        set {
            for (key, value) in newValue {
                chatState.setVariable(name: key, value: value)
            }
        }
    }

    public func resolveVariables(in text: String) -> String {
        return chatState.resolveVariables(text: text)
    }

    public func setValue(_ value: Any, forKey key: String) {
        chatState.setVariable(name: key, value: value)
    }

    public func getValue(forKey key: String) -> Any? {
        return chatState.getVariable(name: key)
    }

    public func emitSocketEvent(_ event: String, data: [String: Any]) {
        guard let socketClient = socketClient else {
            #if DEBUG
            print("[ChatStateNodeStateAdapter] emitSocketEvent called for '\(event)' but no SocketClient available")
            #endif
            return
        }
        socketClient.emit(event: event, data: data)
    }

    public var isSocketConnected: Bool {
        return socketClient?.isConnected ?? false
    }
}

// MARK: - NodeHandlerResult to NodeResult Conversion

extension NodeHandlerResult {

    /// Convert an IntegrationNodeHandler result to the main NodeResult type
    /// used by the flow engine.
    /// - Parameter node: The original node dictionary (used to extract nextNodeId)
    func toNodeResult(node: [String: Any]) -> NodeResult {
        switch self {
        case .proceed:
            let nextNodeId = Self.extractNextNodeId(from: node)
            return .proceed(nextNodeId, nil)

        case .proceedTo(let nodeId):
            return .jumpTo(nodeId)

        case .waitForResponse:
            return .displayUI(.loading)

        case .displayUI(let type, let data):
            switch type {
            case .humanHandover:
                let message = data["message"] as? String
                return .displayUI(.humanHandover(message: message))
            case .calendlyEmbed, .calendlyLink, .externalLink:
                let url = data["url"] as? String ?? data["paymentUrl"] as? String ?? ""
                let text = data["text"] as? String ?? data["description"] as? String
                if !url.isEmpty {
                    return .displayUI(.link(url: url, text: text))
                }
                let nextNodeId = Self.extractNextNodeId(from: node)
                return .proceed(nextNodeId, data)
            }

        case .error(let integrationError):
            return .error(integrationError.localizedDescription)
        }
    }

    /// Extract the next node ID from a node dictionary
    private static func extractNextNodeId(from node: [String: Any]) -> String? {
        if let data = node["data"] as? [String: Any] {
            return data["nextNodeId"] as? String ?? data["next"] as? String
        }
        return node["nextNodeId"] as? String ?? node["next"] as? String
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
