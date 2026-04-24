//
//  NodeFlowEngine.swift
//  Conferbot
//
//  Core orchestration engine that processes chatbot flows.
//  Uses Combine framework for reactive state management.
//

import Foundation
import Combine

/// NodeFlowEngine is the core orchestration engine that processes chatbot flows.
/// It manages node execution, edge routing, and state transitions using reactive patterns.
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public final class NodeFlowEngine: ObservableObject {

    // MARK: - Published Properties (Reactive State)

    /// The current UI state to render
    @Published public private(set) var currentUIState: NodeUIState?

    /// Indicates whether the engine is currently processing a node
    @Published public private(set) var isProcessing: Bool = false

    /// Current error message, if any
    @Published public private(set) var errorMessage: String?

    /// Indicates whether the flow has completed
    @Published public private(set) var isFlowComplete: Bool = false

    /// The ID of the currently active node
    @Published public private(set) var currentNodeId: String?

    // MARK: - Private Properties

    /// The full flow definition dictionary
    private var flow: [String: Any]?

    /// Array of node definitions from the flow
    private var nodes: [[String: Any]] = []

    /// Array of edge definitions connecting nodes
    private var edges: [[String: Any]] = []

    /// Reference to the shared chat state
    private let state: ChatState

    /// Reference to the node handler registry
    private let registry: NodeHandlerRegistry

    /// Cancellables for Combine subscriptions
    private var cancellables = Set<AnyCancellable>()

    /// Tracks visited nodes for infinite loop detection
    private var visitedNodes: Set<String> = []

    /// Maximum number of node visits before detecting a cycle
    private let maxNodeVisits = 100

    /// Lock for thread-safe state modifications
    private let lock = NSLock()

    // MARK: - Initialization

    /// Creates a new NodeFlowEngine instance
    /// - Parameters:
    ///   - state: The chat state to use (defaults to shared instance)
    ///   - registry: The handler registry to use (defaults to shared instance)
    public init(state: ChatState = .shared, registry: NodeHandlerRegistry = .shared) {
        self.state = state
        self.registry = registry
    }

    // MARK: - Flow Loading

    /// Loads a flow definition and prepares the engine for execution
    /// - Parameter flowData: The flow definition dictionary containing nodes and edges
    public func loadFlow(_ flowData: [String: Any]) {
        lock.lock()
        defer { lock.unlock() }

        // Store the full flow definition
        self.flow = flowData

        // Extract nodes array
        if let nodesArray = flowData["nodes"] as? [[String: Any]] {
            self.nodes = nodesArray
        } else if let flowNodes = flowData["flow"] as? [String: Any],
                  let nodesArray = flowNodes["nodes"] as? [[String: Any]] {
            // Handle nested flow structure
            self.nodes = nodesArray
        } else {
            self.nodes = []
        }

        // Extract edges array
        if let edgesArray = flowData["edges"] as? [[String: Any]] {
            self.edges = edgesArray
        } else if let flowEdges = flowData["flow"] as? [String: Any],
                  let edgesArray = flowEdges["edges"] as? [[String: Any]] {
            // Handle nested flow structure
            self.edges = edgesArray
        } else if let connections = flowData["connections"] as? [[String: Any]] {
            // Alternative key name
            self.edges = connections
        } else {
            self.edges = []
        }

        // Reset state for new flow
        resetFlowState()

        // Log flow info for debugging
        ConferBotLogger.info("[NodeFlowEngine] Loaded flow with \(nodes.count) nodes and \(edges.count) edges")
    }

    /// Resets the flow state without clearing the loaded flow
    private func resetFlowState() {
        currentUIState = nil
        isProcessing = false
        errorMessage = nil
        isFlowComplete = false
        currentNodeId = nil
        visitedNodes.removeAll()
        state.resetConversation()
    }

    // MARK: - Flow Execution

    /// Starts the flow execution from the beginning
    public func startFlow() {
        guard !nodes.isEmpty else {
            setError("No nodes loaded in flow")
            return
        }

        // Find the start node
        guard let startNode = findStartNode() else {
            setError("Could not find start node in flow")
            return
        }

        // Get the start node ID
        guard let startNodeId = startNode["id"] as? String else {
            setError("Start node missing ID")
            return
        }

        // Clear any previous error
        clearError()

        // Begin processing from start node
        Task { @MainActor in
            await processNode(startNodeId)
        }
    }

    /// Restarts the flow from the beginning
    public func restartFlow() {
        resetFlowState()
        startFlow()
    }

    /// Processes a specific node by ID
    /// - Parameter nodeId: The ID of the node to process
    @MainActor
    public func processNode(_ nodeId: String) async {
        // FIX 3: Infinite loop protection
        guard visitedNodes.count < maxNodeVisits else {
            ConferBotLogger.error("Flow cycle detected after \(maxNodeVisits) nodes")
            setError("Flow cycle detected")
            isProcessing = false
            state.isTyping = false
            return
        }
        visitedNodes.insert(nodeId)

        // Find the node
        guard let node = findNodeById(nodeId) else {
            setError("Node not found: \(nodeId)")
            return
        }

        // Get the node type
        guard let nodeType = node["type"] as? String else {
            setError("Node missing type: \(nodeId)")
            return
        }

        // Update current state
        currentNodeId = nodeId
        isProcessing = true
        clearError()

        // Update chat state
        state.currentNodeId = nodeId
        state.isTyping = true

        ConferBotLogger.debug("[NodeFlowEngine] Processing node: \(nodeId) (type: \(nodeType))")

        // Check for end/goal nodes
        if isEndNode(nodeType) {
            await handleFlowCompletion(node: node)
            return
        }

        // Get handler for this node type
        let handler = registry.getHandler(for: nodeType)

        // FIX 2: Execute the handler with a 30-second timeout
        let result: NodeResult
        if let handler = handler {
            result = await withTaskGroup(of: NodeResult?.self) { group in
                group.addTask {
                    return await handler.handle(node: node, state: self.state)
                }
                group.addTask {
                    try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                    return nil // timeout sentinel
                }
                let first = await group.next() ?? nil
                group.cancelAll()
                return first ?? nil
            } ?? .error("Node processing timed out for node: \(nodeId)")
        } else {
            // No handler registered - try to proceed to next node
            ConferBotLogger.warning("[NodeFlowEngine] No handler for node type: \(nodeType), attempting to proceed")
            result = .proceed(nil, nil)
        }

        // Handle the result
        await handleNodeResult(result, fromNode: node)
    }

    /// Handles the result of node processing
    /// - Parameters:
    ///   - result: The result from the node handler
    ///   - fromNode: The node that produced this result
    @MainActor
    private func handleNodeResult(_ result: NodeResult, fromNode node: [String: Any]) async {
        let nodeId = node["id"] as? String ?? "unknown"

        switch result {
        case .displayUI(let uiState):
            // Display UI and wait for user interaction
            isProcessing = false
            state.isTyping = false
            currentUIState = uiState

            // Add to transcript for message types
            if case .message(let text, _) = uiState {
                state.addBotMessage(text, nodeId: nodeId, nodeType: node["type"] as? String)
            }

            // Push bot message to server record (matching web widget format)
            let nodeType = node["type"] as? String ?? "unknown"
            let nodeData = node["data"] as? [String: Any]
            let displayText: String? = {
                switch uiState {
                case .message(let text, _): return text
                case .textInput(let placeholder, _, _): return placeholder
                case .humanHandover(let message): return message
                case .liveChat(let message): return message
                default: return nil
                }
            }()
            state.pushBotRecord(nodeId: nodeId, nodeType: nodeType, nodeData: nodeData, text: displayText)

            ConferBotLogger.debug("[NodeFlowEngine] Displaying UI for node: \(nodeId)")

        case .proceed(let nextNodeId, let data):
            // Continue to next node
            isProcessing = false
            state.isTyping = false
            currentUIState = nil

            // Extract port hint before storing data as variables
            // Support both _port (standard) and __targetPort (legacy choice handlers)
            let portHint = data?["_port"] as? String ?? data?["__targetPort"] as? String

            // Store any data passed forward (skip internal keys)
            if let data = data {
                for (key, value) in data {
                    if key.hasPrefix("_") { continue } // skip internal hints like _port
                    state.setVariable(name: key, value: value)
                }
            }

            // Find next node - use port hint for edge-based routing if provided
            let targetNodeId: String?
            if let port = portHint {
                targetNodeId = nextNodeId ?? getNextNodeId(from: nodeId, port: port)
            } else {
                targetNodeId = nextNodeId ?? getNextNodeId(from: nodeId)
            }

            if let targetNodeId = targetNodeId {
                // Process next node
                await processNode(targetNodeId)
            } else {
                // No next node - flow is complete
                await handleFlowCompletion(node: node)
            }

        case .delayedProceed(let delay, let nextNodeId):
            // Wait for delay, then proceed
            isProcessing = true
            state.isTyping = true

            ConferBotLogger.debug("[NodeFlowEngine] Delaying \(delay)s before proceeding")

            // Wait for the specified delay
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            isProcessing = false
            state.isTyping = false

            // Find next node
            let targetNodeId = nextNodeId ?? getNextNodeId(from: nodeId)

            if let targetNodeId = targetNodeId {
                await processNode(targetNodeId)
            } else {
                await handleFlowCompletion(node: node)
            }

        case .jumpTo(let targetNodeId):
            // Jump to a specific node
            isProcessing = false
            state.isTyping = false
            currentUIState = nil

            ConferBotLogger.debug("[NodeFlowEngine] Jumping to node: \(targetNodeId)")

            await processNode(targetNodeId)

        case .error(let message):
            // Handle error
            setError(message)
            isProcessing = false
            state.isTyping = false
        }
    }

    /// Handles flow completion
    /// - Parameter node: The final node in the flow
    @MainActor
    private func handleFlowCompletion(node: [String: Any]) async {
        isProcessing = false
        state.isTyping = false
        isFlowComplete = true
        currentUIState = .none

        // Update record to mark completion
        state.updateRecord([
            "completed": true,
            "completedAt": ISO8601DateFormatter().string(from: Date()),
            "finalNodeId": node["id"] as? String ?? "unknown"
        ])

        ConferBotLogger.info("[NodeFlowEngine] Flow completed")
    }

    // MARK: - User Input Handling

    /// Handles user input for a specific node
    /// - Parameters:
    ///   - input: The user's input value
    ///   - forNodeId: The ID of the node this input is for
    @MainActor
    public func handleUserInput(_ input: Any, forNodeId nodeId: String) async {
        guard let node = findNodeById(nodeId) else {
            setError("Node not found for input: \(nodeId)")
            return
        }

        // Store the answer in state
        state.setAnswer(nodeId: nodeId, value: input)

        // Add user message to transcript
        let inputString = stringValue(from: input)
        state.addUserMessage(inputString, nodeId: nodeId)

        ConferBotLogger.debug("[NodeFlowEngine] Received input for node \(nodeId): \(inputString)")

        // Validate input if needed
        if !validateInput(input, forNode: node) {
            // Validation failed - error message is already set
            return
        }

        // Determine next node based on input type and value
        let port = determineOutputPort(from: input, forNode: node)
        let nextNodeId = getNextNodeId(from: nodeId, port: port)

        // Clear current UI state
        currentUIState = nil

        if let nextNodeId = nextNodeId {
            // Continue to next node
            await processNode(nextNodeId)
        } else {
            // No next node - flow is complete
            await handleFlowCompletion(node: node)
        }
    }

    /// Handles button click input
    /// - Parameters:
    ///   - buttonId: The ID of the clicked button
    ///   - forNodeId: The ID of the node containing the button
    @MainActor
    public func handleButtonClick(buttonId: String, forNodeId nodeId: String) async {
        guard let node = findNodeById(nodeId) else {
            setError("Node not found for button click: \(nodeId)")
            return
        }

        // Find the button data
        let buttonValue = findButtonValue(buttonId: buttonId, inNode: node) ?? buttonId

        // Store the answer
        state.setAnswer(nodeId: nodeId, value: buttonValue)
        state.addUserMessage(buttonValue, nodeId: nodeId)

        // Track last user choice so downstream message-nodes can skip echo
        state.setVariable(name: "_lastUserChoice", value: buttonValue)

        ConferBotLogger.debug("[NodeFlowEngine] Button clicked: \(buttonId) for node \(nodeId)")

        // Clear current UI state
        currentUIState = nil

        // Use button ID as port for edge routing
        // Try buttonId directly first, then try "source-{buttonId}" format (legacy nodes)
        var nextNodeId = getNextNodeId(from: nodeId, port: buttonId)
        if nextNodeId == nil {
            nextNodeId = getNextNodeId(from: nodeId, port: "source-\(buttonId)")
        }

        if let nextNodeId = nextNodeId {
            await processNode(nextNodeId)
        } else {
            // Try default edge
            if let defaultNextId = getNextNodeId(from: nodeId) {
                await processNode(defaultNextId)
            } else {
                await handleFlowCompletion(node: node)
            }
        }
    }

    /// Handles choice selection input
    /// - Parameters:
    ///   - optionId: The ID of the selected option
    ///   - forNodeId: The ID of the node
    @MainActor
    public func handleChoiceSelection(optionId: String, forNodeId nodeId: String) async {
        guard let node = findNodeById(nodeId) else {
            setError("Node not found for choice: \(nodeId)")
            return
        }

        // Find the option data
        let optionValue = findOptionValue(optionId: optionId, inNode: node) ?? optionId

        // Store the answer
        state.setAnswer(nodeId: nodeId, value: optionValue)
        state.addUserMessage(optionValue, nodeId: nodeId)

        // Track last user choice so downstream message-nodes can skip echo
        state.setVariable(name: "_lastUserChoice", value: optionValue)

        ConferBotLogger.debug("[NodeFlowEngine] Choice selected: \(optionId) for node \(nodeId)")

        // Clear current UI state
        currentUIState = nil

        // Use option ID as port for edge routing
        // Try optionId directly first, then try "source-{optionId}" format (legacy nodes)
        var nextNodeId = getNextNodeId(from: nodeId, port: optionId)
        if nextNodeId == nil {
            nextNodeId = getNextNodeId(from: nodeId, port: "source-\(optionId)")
        }

        if let nextNodeId = nextNodeId {
            await processNode(nextNodeId)
        } else {
            // Try default edge
            if let defaultNextId = getNextNodeId(from: nodeId) {
                await processNode(defaultNextId)
            } else {
                await handleFlowCompletion(node: node)
            }
        }
    }

    // MARK: - Edge Routing

    /// Gets the next node ID based on edge connections
    /// - Parameters:
    ///   - currentNodeId: The source node ID
    ///   - port: Optional port/handle name for conditional routing
    /// - Returns: The target node ID, or nil if no matching edge
    public func getNextNodeId(from currentNodeId: String, port: String? = nil) -> String? {
        // Search for matching edge
        for edge in edges {
            guard let source = edge["source"] as? String,
                  source == currentNodeId else {
                continue
            }

            // If port is specified, match sourceHandle
            if let port = port {
                if let sourceHandle = edge["sourceHandle"] as? String {
                    if sourceHandle == port || sourceHandle.contains(port) {
                        return edge["target"] as? String
                    }
                }
            } else {
                // No port specified - return first matching edge
                // Prefer edges without sourceHandle (default path)
                let sourceHandle = edge["sourceHandle"] as? String
                if sourceHandle == nil || sourceHandle?.isEmpty == true {
                    return edge["target"] as? String
                }
            }
        }

        // If port was specified but no match found, try default edge
        if port != nil {
            for edge in edges {
                guard let source = edge["source"] as? String,
                      source == currentNodeId else {
                    continue
                }

                // Return first edge as fallback
                let sourceHandle = edge["sourceHandle"] as? String
                if sourceHandle == nil || sourceHandle?.isEmpty == true || sourceHandle == "default" {
                    return edge["target"] as? String
                }
            }

            // Last resort - return any matching edge
            for edge in edges {
                if let source = edge["source"] as? String, source == currentNodeId {
                    return edge["target"] as? String
                }
            }

            // FIX 5: Log when no edge is found for a specific port
            ConferBotLogger.warning("[NodeFlowEngine] No edge found for port: \(port ?? "nil") on node: \(currentNodeId)")
        }

        return nil
    }

    /// Gets all outgoing edges from a node
    /// - Parameter nodeId: The source node ID
    /// - Returns: Array of edge dictionaries
    public func getOutgoingEdges(from nodeId: String) -> [[String: Any]] {
        return edges.filter { edge in
            return edge["source"] as? String == nodeId
        }
    }

    // MARK: - Node Lookup

    /// Finds a node by its ID
    /// - Parameter id: The node ID to find
    /// - Returns: The node dictionary, or nil if not found
    private func findNodeById(_ id: String) -> [String: Any]? {
        return nodes.first { node in
            return node["id"] as? String == id
        }
    }

    /// Finds the start node in the flow
    /// - Returns: The start node dictionary, or nil if not found
    private func findStartNode() -> [String: Any]? {
        // Look for node with type "START" or "start"
        if let startNode = nodes.first(where: { node in
            let type = node["type"] as? String
            return type?.uppercased() == "START"
        }) {
            return startNode
        }

        // Look for node with isStart flag
        if let startNode = nodes.first(where: { node in
            if let isStart = node["isStart"] as? Bool {
                return isStart
            }
            if let data = node["data"] as? [String: Any],
               let isStart = data["isStart"] as? Bool {
                return isStart
            }
            return false
        }) {
            return startNode
        }

        // Look for node with position indicating start (if edges exist)
        if !edges.isEmpty {
            // Find nodes that are not targets of any edge (entry points)
            let targetNodeIds = Set(edges.compactMap { $0["target"] as? String })
            let entryNodes = nodes.filter { node in
                guard let nodeId = node["id"] as? String else { return false }
                return !targetNodeIds.contains(nodeId)
            }

            if let entryNode = entryNodes.first {
                return entryNode
            }
        }

        // Fallback to first node
        return nodes.first
    }

    // MARK: - Validation

    /// Validates user input for a node
    /// - Parameters:
    ///   - input: The input value to validate
    ///   - node: The node requiring validation
    /// - Returns: True if valid, false otherwise
    private func validateInput(_ input: Any, forNode node: [String: Any]) -> Bool {
        guard let data = node["data"] as? [String: Any] else {
            return true // No data means no validation required
        }

        // Get validation type
        guard let validationType = data["validation"] as? String ?? data["validationType"] as? String else {
            return true // No validation specified
        }

        let inputString = stringValue(from: input)

        // Create validation based on type
        let validation: InputValidation
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
            validation = .custom(validationType)
        }

        // Perform validation
        let isValid = validation.validate(inputString)

        if !isValid {
            setError(validation.errorMessage)
        }

        return isValid
    }

    // MARK: - Helper Methods

    /// Checks if a node type represents an end of flow
    /// - Parameter nodeType: The node type to check
    /// - Returns: True if this is an end node
    private func isEndNode(_ nodeType: String) -> Bool {
        let endTypes = ["end", "end_conversation", "goal", "END", "GOAL", "end-conversation-node", "goal-node"]
        return endTypes.contains(nodeType) || nodeType.lowercased().contains("end")
    }

    /// Determines the output port based on user input
    /// - Parameters:
    ///   - input: The user input
    ///   - node: The node
    /// - Returns: The port name for edge routing
    private func determineOutputPort(from input: Any, forNode node: [String: Any]) -> String? {
        // For button clicks, the input might be the button ID
        if let inputString = input as? String {
            // Check if this matches a button or option ID in the node
            if let data = node["data"] as? [String: Any] {
                // Check buttons
                if let buttons = data["buttons"] as? [[String: Any]] {
                    for button in buttons {
                        if let buttonId = button["id"] as? String, buttonId == inputString {
                            return buttonId
                        }
                        if let buttonValue = button["value"] as? String, buttonValue == inputString {
                            return button["id"] as? String ?? inputString
                        }
                    }
                }

                // Check options
                if let options = data["options"] as? [[String: Any]] {
                    for option in options {
                        if let optionId = option["id"] as? String, optionId == inputString {
                            return optionId
                        }
                        if let optionValue = option["value"] as? String, optionValue == inputString {
                            return option["id"] as? String ?? inputString
                        }
                    }
                }
            }
        }

        return nil
    }

    /// Finds the display value for a button
    /// - Parameters:
    ///   - buttonId: The button ID
    ///   - node: The node containing buttons
    /// - Returns: The button's label or value
    private func findButtonValue(buttonId: String, inNode node: [String: Any]) -> String? {
        guard let data = node["data"] as? [String: Any] else {
            return nil
        }

        if let buttons = data["buttons"] as? [[String: Any]] {
            for button in buttons {
                if let id = button["id"] as? String, id == buttonId {
                    return button["label"] as? String ?? button["value"] as? String ?? button["text"] as? String
                }
            }
        }

        // Also check legacy choice keys
        if let index = Int(buttonId) {
            let choiceKey = "choice\(index + 1)"
            if let choiceText = data[choiceKey] as? String {
                return choiceText.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            }
        }

        return nil
    }

    /// Finds the display value for an option
    /// - Parameters:
    ///   - optionId: The option ID
    ///   - node: The node containing options
    /// - Returns: The option's label or value
    private func findOptionValue(optionId: String, inNode node: [String: Any]) -> String? {
        guard let data = node["data"] as? [String: Any] else {
            return nil
        }

        // Check standard options/choices arrays
        if let options = data["options"] as? [[String: Any]] ?? data["choices"] as? [[String: Any]] {
            for option in options {
                if let id = option["id"] as? String, id == optionId {
                    return option["label"] as? String
                        ?? option["optionText"] as? String
                        ?? option["value"] as? String
                        ?? option["text"] as? String
                }
            }
        }

        // Check legacy choice keys (choice1, choice2, choice3 for two/three-choices-node)
        if let index = Int(optionId) {
            let choiceKey = "choice\(index + 1)"
            if let choiceText = data[choiceKey] as? String {
                // Strip HTML tags from legacy choice text
                return choiceText.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            }
        }

        // Check legacy select option keys (option1..option5 for select-option-node)
        if let index = Int(optionId) {
            let optionKey = "option\(index + 1)"
            if let optionText = data[optionKey] as? String {
                return optionText.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            }
        }

        return nil
    }

    /// Converts any value to a string representation
    /// - Parameter value: The value to convert
    /// - Returns: String representation
    private func stringValue(from value: Any) -> String {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        case let bool as Bool:
            return bool ? "Yes" : "No"
        case let array as [Any]:
            return array.compactMap { stringValue(from: $0) }.joined(separator: ", ")
        case let dict as [String: Any]:
            if let jsonData = try? JSONSerialization.data(withJSONObject: dict, options: []),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
            return String(describing: dict)
        default:
            return String(describing: value)
        }
    }

    // MARK: - Error Handling

    /// Sets an error message
    /// - Parameter message: The error message
    private func setError(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.errorMessage = message
        }
        ConferBotLogger.error("[NodeFlowEngine] \(message)")
    }

    /// Clears any existing error
    private func clearError() {
        DispatchQueue.main.async { [weak self] in
            self?.errorMessage = nil
        }
    }

    // MARK: - Flow Information

    /// Returns the total number of nodes in the flow
    public var nodeCount: Int {
        return nodes.count
    }

    /// Returns the total number of edges in the flow
    public var edgeCount: Int {
        return edges.count
    }

    /// Returns all node IDs in the flow
    public var allNodeIds: [String] {
        return nodes.compactMap { $0["id"] as? String }
    }

    /// Checks if the flow has been loaded
    public var isFlowLoaded: Bool {
        return flow != nil && !nodes.isEmpty
    }

    /// Gets information about a specific node
    /// - Parameter nodeId: The node ID
    /// - Returns: A summary dictionary with node info
    public func getNodeInfo(_ nodeId: String) -> [String: Any]? {
        guard let node = findNodeById(nodeId) else {
            return nil
        }

        return [
            "id": node["id"] as? String ?? "unknown",
            "type": node["type"] as? String ?? "unknown",
            "data": node["data"] as? [String: Any] ?? [:],
            "outgoingEdges": getOutgoingEdges(from: nodeId).count
        ]
    }
}

// MARK: - Publisher Extensions

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public extension NodeFlowEngine {

    /// Publisher for UI state changes
    var uiStatePublisher: AnyPublisher<NodeUIState?, Never> {
        $currentUIState.eraseToAnyPublisher()
    }

    /// Publisher for processing state changes
    var processingPublisher: AnyPublisher<Bool, Never> {
        $isProcessing.eraseToAnyPublisher()
    }

    /// Publisher for error messages
    var errorPublisher: AnyPublisher<String?, Never> {
        $errorMessage.eraseToAnyPublisher()
    }

    /// Publisher for flow completion
    var completionPublisher: AnyPublisher<Bool, Never> {
        $isFlowComplete.eraseToAnyPublisher()
    }

    /// Publisher for current node ID changes
    var currentNodePublisher: AnyPublisher<String?, Never> {
        $currentNodeId.eraseToAnyPublisher()
    }
}

// MARK: - Debugging Extensions

#if DEBUG
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public extension NodeFlowEngine {

    /// Prints the current flow structure for debugging
    func debugPrintFlow() {
        print("=== Flow Debug Info ===")
        print("Nodes: \(nodes.count)")
        for node in nodes {
            let id = node["id"] as? String ?? "unknown"
            let type = node["type"] as? String ?? "unknown"
            print("  - \(id) (type: \(type))")
        }

        print("\nEdges: \(edges.count)")
        for edge in edges {
            let source = edge["source"] as? String ?? "?"
            let target = edge["target"] as? String ?? "?"
            let handle = edge["sourceHandle"] as? String ?? "default"
            print("  - \(source) --[\(handle)]--> \(target)")
        }

        print("\nCurrent State:")
        print("  - Current Node: \(currentNodeId ?? "none")")
        print("  - Processing: \(isProcessing)")
        print("  - Complete: \(isFlowComplete)")
        print("  - Error: \(errorMessage ?? "none")")
        print("=======================")
    }

    /// Manually sets the current node for testing
    func debugSetCurrentNode(_ nodeId: String) {
        currentNodeId = nodeId
    }

    /// Manually triggers flow completion for testing
    func debugCompleteFlow() {
        isFlowComplete = true
        currentUIState = .none
    }
}
#endif
