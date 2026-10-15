//
//  NodeHandlerRegistry.swift
//  Conferbot
//
//  Registry for managing node handlers
//

import Foundation

/// Registry for node handlers, managing handler lookup and registration
public final class NodeHandlerRegistry {

    // MARK: - Shared Instance

    /// Shared singleton instance, with every built-in step registered.
    public static let shared: NodeHandlerRegistry = {
        let registry = NodeHandlerRegistry()
        registry.registerAllHandlers()
        return registry
    }()

    // MARK: - Properties

    /// Dictionary mapping node types to their handlers
    private var handlers: [String: NodeHandler] = [:]

    /// Lock for thread-safe access
    private let lock = NSLock()

    /// Socket client reference for integration handlers that need to emit events.
    /// Set during ConferBot initialization.
    public weak var socketClient: SocketClient?

    // MARK: - Initialization

    public init() {}

    // MARK: - Registration

    /// Register a handler for its node type
    /// - Parameter handler: The handler to register
    public func register(_ handler: NodeHandler) {
        lock.lock()
        defer { lock.unlock() }
        handlers[handler.nodeType] = handler
    }

    /// Register multiple handlers at once
    /// - Parameter handlers: Array of handlers to register
    public func register(_ handlers: [NodeHandler]) {
        lock.lock()
        defer { lock.unlock() }
        for handler in handlers {
            self.handlers[handler.nodeType] = handler
        }
    }

    /// Unregister a handler for a node type
    /// - Parameter nodeType: The node type to unregister
    public func unregister(_ nodeType: String) {
        lock.lock()
        defer { lock.unlock() }
        handlers.removeValue(forKey: nodeType)
    }

    // MARK: - Lookup

    /// Get the handler for a specific node type
    /// - Parameter nodeType: The type of node to get handler for
    /// - Returns: The registered handler, or nil if not found
    public func getHandler(for nodeType: String) -> NodeHandler? {
        lock.lock()
        defer { lock.unlock() }
        return handlers[nodeType]
    }

    /// Check if a handler is registered for a node type
    /// - Parameter nodeType: The node type to check
    /// - Returns: True if a handler is registered
    public func hasHandler(for nodeType: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return handlers[nodeType] != nil
    }

    /// Get all registered node types
    /// - Returns: Array of registered node type strings
    public var registeredTypes: [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(handlers.keys)
    }

    /// Get the count of registered handlers
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return handlers.count
    }

    // MARK: - Convenience Methods

    /// Process a node using the appropriate handler
    /// - Parameters:
    ///   - node: The node data dictionary
    ///   - state: Current chat state
    /// - Returns: The result of processing the node
    public func process(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let nodeType = node["type"] as? String else {
            return .error("Node missing type field")
        }

        guard let handler = getHandler(for: nodeType) else {
            #if DEBUG
            print("[NodeHandlerRegistry] WARNING: No handler registered for node type: \(nodeType) - skipping node")
            #endif
            // Gracefully skip unhandled node types instead of returning an error.
            // Extract nextNodeId so the flow can continue.
            let data = node["data"] as? [String: Any]
            let nextNodeId = data?["nextNodeId"] as? String
                ?? data?["next"] as? String
                ?? node["nextNodeId"] as? String
                ?? node["next"] as? String
            return .proceed(nextNodeId, nil)
        }

        return await handler.handle(node: node, state: state)
    }

    /// Clear all registered handlers
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        handlers.removeAll()
    }

    /// Back to every built-in step (registerAllHandlers).
    public func reset() {
        clear()
        registerAllHandlers()
    }
}

// MARK: - All handlers

public extension NodeHandlerRegistry {

    /// Registers every step this SDK runs (82 node types of the flow-node
    /// spec, as the web widget runs them; the React Native SDK's
    /// registerAllHandlers).
    func registerAllHandlers() {
        register(DisplayNodeHandlers.all)
        register(AskNodeHandlers.all)
        register(ChoiceNodeHandlers.all)
        register(AdvancedInputHandlers.all)
        register(LegacyNodeHandlers.all)
        register(LogicNodeHandlers.all)
        register(IntegrationNodeHandlers.all)
        register(SpecialNodeHandlers.all)
        register(RichNodeHandlers.all)
    }
}
