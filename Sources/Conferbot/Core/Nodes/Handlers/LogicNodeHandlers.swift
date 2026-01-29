//
//  LogicNodeHandlers.swift
//  Conferbot
//
//  Node handlers for all 7 logic node types:
//  - redirect_url
//  - set_variable
//  - javascript_function
//  - conditional
//  - ab_test
//  - split_conversation
//  - delay
//

import Foundation

// MARK: - Redirect URL Handler

/// Handler for redirect_url nodes
/// Extracts URL from node data and returns proceed with redirect action
public final class RedirectUrlHandler: BaseNodeHandler {

    public override var nodeType: String { NodeTypes.Logic.redirectUrl }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("Redirect URL node missing data")
        }

        guard let url = getString(data, "url") ?? getString(data, "redirectUrl") else {
            return .error("Redirect URL node missing URL")
        }

        // Resolve any variables in the URL
        let resolvedUrl = state.resolveVariables(text: url)

        // Return proceed with redirect action data
        // The SDK layer will handle opening the URL
        let redirectData: [String: Any] = [
            "action": "redirect",
            "url": resolvedUrl
        ]

        let nextNodeId = getNextNodeId(node)
        return .proceed(nextNodeId, redirectData)
    }
}

// MARK: - Set Variable Handler

/// Handler for set_variable nodes
/// Sets a variable in the chat state and proceeds immediately
public final class SetVariableHandler: BaseNodeHandler {

    public override var nodeType: String { NodeTypes.Logic.setVariable }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("Set variable node missing data")
        }

        // Extract variable name from various possible keys
        guard let variableName = getString(data, "variableName")
            ?? getString(data, "name")
            ?? getString(data, "variable") else {
            return .error("Set variable node missing variable name")
        }

        // Extract variable value from various possible keys
        let rawValue = data["variableValue"]
            ?? data["value"]
            ?? ""

        // Resolve any variables in the value if it's a string
        let resolvedValue: Any
        if let stringValue = rawValue as? String {
            resolvedValue = state.resolveVariables(text: stringValue)
        } else {
            resolvedValue = rawValue
        }

        // Set the variable in state
        state.setVariable(name: variableName, value: resolvedValue)

        let nextNodeId = getNextNodeId(node)
        return .proceed(nextNodeId, nil)
    }
}

// MARK: - JavaScript Function Handler

/// Handler for javascript_function nodes
/// On mobile, JavaScript cannot execute natively, so this logs a warning and proceeds
public final class JavaScriptFunctionHandler: BaseNodeHandler {

    public override var nodeType: String { NodeTypes.Logic.javascriptFunction }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        let data = getNodeData(node)

        // Extract function name for logging purposes
        let functionName = data.flatMap { getString($0, "functionName") }
            ?? data.flatMap { getString($0, "name") }
            ?? "unknown"

        // Log warning that JavaScript cannot execute on mobile
        #if DEBUG
        print("[Conferbot] Warning: JavaScript function '\(functionName)' cannot execute natively on iOS. Proceeding to next node.")
        #endif

        let nextNodeId = getNextNodeId(node)
        return .proceed(nextNodeId, nil)
    }
}

// MARK: - Conditional Handler

/// Operators supported for conditional evaluation
public enum ConditionalOperator: String {
    case equals = "equals"
    case notEquals = "not_equals"
    case contains = "contains"
    case notContains = "not_contains"
    case greaterThan = "greater_than"
    case lessThan = "less_than"
    case isEmpty = "is_empty"
    case isNotEmpty = "is_not_empty"

    /// Initialize from string, handling various formats
    init?(from string: String) {
        let normalized = string.lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        switch normalized {
        case "equals", "equal", "eq", "==":
            self = .equals
        case "not_equals", "not_equal", "ne", "neq", "!=":
            self = .notEquals
        case "contains", "include", "includes":
            self = .contains
        case "not_contains", "not_contain", "not_include", "not_includes":
            self = .notContains
        case "greater_than", "gt", ">":
            self = .greaterThan
        case "less_than", "lt", "<":
            self = .lessThan
        case "is_empty", "empty":
            self = .isEmpty
        case "is_not_empty", "not_empty":
            self = .isNotEmpty
        default:
            return nil
        }
    }
}

/// Logic type for combining multiple conditions
public enum ConditionalLogic: String {
    case and = "and"
    case or = "or"

    init?(from string: String) {
        switch string.lowercased() {
        case "and", "&&":
            self = .and
        case "or", "||":
            self = .or
        default:
            return nil
        }
    }
}

/// Handler for conditional nodes
/// Evaluates conditions and branches to appropriate node based on result
public final class ConditionalHandler: BaseNodeHandler {

    public override var nodeType: String { NodeTypes.Logic.conditional }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("Conditional node missing data")
        }

        // Extract conditions array
        guard let conditions = getArray(data, "conditions") else {
            return .error("Conditional node missing conditions")
        }

        // Determine logic type (AND/OR), default to AND
        let logicString = getString(data, "logic") ?? getString(data, "logicType") ?? "and"
        let logic = ConditionalLogic(from: logicString) ?? .and

        // Evaluate all conditions
        let result = evaluateConditions(conditions, logic: logic, state: state)

        // Extract branch node IDs from edges or data
        let trueNodeId = extractTrueNodeId(from: node, data: data)
        let falseNodeId = extractFalseNodeId(from: node, data: data)

        if result {
            if let trueNodeId = trueNodeId {
                return .jumpTo(trueNodeId)
            } else {
                // No true branch defined, just proceed
                let nextNodeId = getNextNodeId(node)
                return .proceed(nextNodeId, nil)
            }
        } else {
            if let falseNodeId = falseNodeId {
                return .jumpTo(falseNodeId)
            } else {
                // No false branch defined, just proceed
                let nextNodeId = getNextNodeId(node)
                return .proceed(nextNodeId, nil)
            }
        }
    }

    /// Evaluates multiple conditions using the specified logic
    private func evaluateConditions(_ conditions: [[String: Any]], logic: ConditionalLogic, state: ChatState) -> Bool {
        if conditions.isEmpty {
            return true
        }

        switch logic {
        case .and:
            return conditions.allSatisfy { evaluateSingleCondition($0, state: state) }
        case .or:
            return conditions.contains { evaluateSingleCondition($0, state: state) }
        }
    }

    /// Evaluates a single condition
    private func evaluateSingleCondition(_ condition: [String: Any], state: ChatState) -> Bool {
        // Extract variable name
        guard let variableName = getString(condition, "variable")
            ?? getString(condition, "variableName")
            ?? getString(condition, "field") else {
            return false
        }

        // Extract operator
        guard let operatorString = getString(condition, "operator")
            ?? getString(condition, "op")
            ?? getString(condition, "comparison"),
              let op = ConditionalOperator(from: operatorString) else {
            return false
        }

        // Get the actual value from state
        let actualValue = state.getVariable(name: variableName)
            ?? state.getAnswer(nodeId: variableName)
            ?? state.getMetadata(key: variableName)

        // Extract comparison value
        let comparisonValue = condition["value"] ?? condition["compareValue"] ?? ""

        return evaluateOperation(actualValue: actualValue, operator: op, comparisonValue: comparisonValue, state: state)
    }

    /// Evaluates a single operation
    private func evaluateOperation(actualValue: Any?, operator op: ConditionalOperator, comparisonValue: Any, state: ChatState) -> Bool {
        // Handle isEmpty and isNotEmpty first
        switch op {
        case .isEmpty:
            return isValueEmpty(actualValue)
        case .isNotEmpty:
            return !isValueEmpty(actualValue)
        default:
            break
        }

        // Convert values to comparable strings/numbers
        let actualString = stringValue(from: actualValue)
        var comparisonString = stringValue(from: comparisonValue)

        // Resolve variables in comparison value
        comparisonString = state.resolveVariables(text: comparisonString)

        switch op {
        case .equals:
            // Try numeric comparison first
            if let actualNum = doubleValue(from: actualValue),
               let compareNum = doubleValue(from: comparisonValue) {
                return actualNum == compareNum
            }
            return actualString.lowercased() == comparisonString.lowercased()

        case .notEquals:
            if let actualNum = doubleValue(from: actualValue),
               let compareNum = doubleValue(from: comparisonValue) {
                return actualNum != compareNum
            }
            return actualString.lowercased() != comparisonString.lowercased()

        case .contains:
            return actualString.lowercased().contains(comparisonString.lowercased())

        case .notContains:
            return !actualString.lowercased().contains(comparisonString.lowercased())

        case .greaterThan:
            if let actualNum = doubleValue(from: actualValue),
               let compareNum = doubleValue(from: comparisonValue) {
                return actualNum > compareNum
            }
            return actualString > comparisonString

        case .lessThan:
            if let actualNum = doubleValue(from: actualValue),
               let compareNum = doubleValue(from: comparisonValue) {
                return actualNum < compareNum
            }
            return actualString < comparisonString

        case .isEmpty, .isNotEmpty:
            // Already handled above
            return false
        }
    }

    /// Checks if a value is empty
    private func isValueEmpty(_ value: Any?) -> Bool {
        guard let value = value else { return true }

        if let string = value as? String {
            return string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if let array = value as? [Any] {
            return array.isEmpty
        }
        if let dict = value as? [String: Any] {
            return dict.isEmpty
        }
        return false
    }

    /// Converts any value to string
    private func stringValue(from value: Any?) -> String {
        guard let value = value else { return "" }

        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        case let bool as Bool:
            return bool ? "true" : "false"
        default:
            return String(describing: value)
        }
    }

    /// Attempts to extract double value
    private func doubleValue(from value: Any?) -> Double? {
        guard let value = value else { return nil }

        if let double = value as? Double {
            return double
        }
        if let int = value as? Int {
            return Double(int)
        }
        if let string = value as? String {
            return Double(string)
        }
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        return nil
    }

    /// Extracts true branch node ID from edges or data
    private func extractTrueNodeId(from node: [String: Any], data: [String: Any]) -> String? {
        // Check data first
        if let trueNodeId = getString(data, "trueNodeId") ?? getString(data, "trueBranch") {
            return trueNodeId
        }

        // Check edges array
        if let edges = node["edges"] as? [[String: Any]] {
            for edge in edges {
                let label = getString(edge, "label") ?? getString(edge, "type") ?? ""
                if label.lowercased() == "true" || label.lowercased() == "yes" {
                    return getString(edge, "target") ?? getString(edge, "targetNodeId")
                }
            }
        }

        return nil
    }

    /// Extracts false branch node ID from edges or data
    private func extractFalseNodeId(from node: [String: Any], data: [String: Any]) -> String? {
        // Check data first
        if let falseNodeId = getString(data, "falseNodeId") ?? getString(data, "falseBranch") {
            return falseNodeId
        }

        // Check edges array
        if let edges = node["edges"] as? [[String: Any]] {
            for edge in edges {
                let label = getString(edge, "label") ?? getString(edge, "type") ?? ""
                if label.lowercased() == "false" || label.lowercased() == "no" {
                    return getString(edge, "target") ?? getString(edge, "targetNodeId")
                }
            }
        }

        return nil
    }
}

// MARK: - AB Test Handler

/// Handler for ab_test nodes
/// Randomly selects a variant based on percentage weights
public final class ABTestHandler: BaseNodeHandler {

    public override var nodeType: String { NodeTypes.Logic.abTest }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("AB test node missing data")
        }

        // Extract variants array
        guard let variants = getArray(data, "variants") ?? getArray(data, "options") else {
            return .error("AB test node missing variants")
        }

        guard !variants.isEmpty else {
            return .error("AB test node has no variants")
        }

        // Select variant based on weights
        let selectedVariant = selectVariantByWeight(variants)

        // Extract variant details
        let variantId = getString(selectedVariant, "id") ?? getString(selectedVariant, "variantId") ?? UUID().uuidString
        let variantName = getString(selectedVariant, "name") ?? getString(selectedVariant, "label") ?? variantId
        let variantNodeId = getString(selectedVariant, "nodeId")
            ?? getString(selectedVariant, "targetNodeId")
            ?? getString(selectedVariant, "next")

        // Store selected variant in state for analytics
        let testId = getString(data, "testId") ?? getString(data, "id") ?? getNodeId(node) ?? UUID().uuidString
        state.setVariable(name: "abTest_\(testId)", value: variantId)
        state.setVariable(name: "abTest_\(testId)_name", value: variantName)

        if let variantNodeId = variantNodeId {
            return .jumpTo(variantNodeId)
        } else {
            // No target node, proceed to default next
            let nextNodeId = getNextNodeId(node)
            return .proceed(nextNodeId, ["selectedVariant": variantId])
        }
    }

    /// Selects a variant based on percentage weights
    private func selectVariantByWeight(_ variants: [[String: Any]]) -> [String: Any] {
        // Calculate total weight
        var totalWeight: Double = 0
        var variantWeights: [(variant: [String: Any], weight: Double)] = []

        for variant in variants {
            let weight = getDouble(variant, "percentage")
                ?? getDouble(variant, "weight")
                ?? 100.0 / Double(variants.count) // Default to equal distribution
            variantWeights.append((variant, weight))
            totalWeight += weight
        }

        // Generate random number between 0 and total weight
        let randomValue = Double.random(in: 0..<totalWeight)

        // Find the selected variant
        var cumulativeWeight: Double = 0
        for (variant, weight) in variantWeights {
            cumulativeWeight += weight
            if randomValue < cumulativeWeight {
                return variant
            }
        }

        // Fallback to last variant
        return variants.last ?? [:]
    }
}

// MARK: - Split Conversation Handler

/// Handler for split_conversation nodes
/// Similar to AB test but for conversation branching
public final class SplitConversationHandler: BaseNodeHandler {

    public override var nodeType: String { NodeTypes.Logic.splitConversation }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("Split conversation node missing data")
        }

        // Extract branches array
        guard let branches = getArray(data, "branches")
            ?? getArray(data, "paths")
            ?? getArray(data, "variants") else {
            return .error("Split conversation node missing branches")
        }

        guard !branches.isEmpty else {
            return .error("Split conversation node has no branches")
        }

        // Select branch based on weights
        let selectedBranch = selectBranchByWeight(branches)

        // Extract branch details
        let branchId = getString(selectedBranch, "id") ?? getString(selectedBranch, "branchId") ?? UUID().uuidString
        let branchName = getString(selectedBranch, "name") ?? getString(selectedBranch, "label") ?? branchId
        let branchNodeId = getString(selectedBranch, "nodeId")
            ?? getString(selectedBranch, "targetNodeId")
            ?? getString(selectedBranch, "next")

        // Store selected branch in state
        let splitId = getString(data, "splitId") ?? getString(data, "id") ?? getNodeId(node) ?? UUID().uuidString
        state.setVariable(name: "split_\(splitId)", value: branchId)
        state.setVariable(name: "split_\(splitId)_name", value: branchName)

        if let branchNodeId = branchNodeId {
            return .jumpTo(branchNodeId)
        } else {
            // No target node, proceed to default next
            let nextNodeId = getNextNodeId(node)
            return .proceed(nextNodeId, ["selectedBranch": branchId])
        }
    }

    /// Selects a branch based on percentage weights
    private func selectBranchByWeight(_ branches: [[String: Any]]) -> [String: Any] {
        // Calculate total weight
        var totalWeight: Double = 0
        var branchWeights: [(branch: [String: Any], weight: Double)] = []

        for branch in branches {
            let weight = getDouble(branch, "percentage")
                ?? getDouble(branch, "weight")
                ?? 100.0 / Double(branches.count) // Default to equal distribution
            branchWeights.append((branch, weight))
            totalWeight += weight
        }

        // Generate random number between 0 and total weight
        let randomValue = Double.random(in: 0..<totalWeight)

        // Find the selected branch
        var cumulativeWeight: Double = 0
        for (branch, weight) in branchWeights {
            cumulativeWeight += weight
            if randomValue < cumulativeWeight {
                return branch
            }
        }

        // Fallback to last branch
        return branches.last ?? [:]
    }
}

// MARK: - Delay Handler

/// Handler for delay nodes
/// Returns delayedProceed with the specified delay time
public final class LogicDelayHandler: BaseNodeHandler {

    public override var nodeType: String { NodeTypes.Logic.delay }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        let data = getNodeData(node)

        // Extract delay in seconds from various possible keys
        var delaySeconds: TimeInterval = 1.0 // Default 1 second

        if let data = data {
            if let seconds = getDouble(data, "delaySeconds") ?? getDouble(data, "delay") ?? getDouble(data, "duration") ?? getDouble(data, "seconds") {
                delaySeconds = seconds
            } else if let milliseconds = getDouble(data, "delayMs") ?? getDouble(data, "milliseconds") {
                delaySeconds = milliseconds / 1000.0
            }
        }

        // Ensure delay is positive and reasonable (max 60 seconds)
        delaySeconds = max(0, min(delaySeconds, 60.0))

        let nextNodeId = getNextNodeId(node)
        return .delayedProceed(delaySeconds, nextNodeId)
    }
}

// MARK: - Handler Registration Extension

public extension NodeHandlerRegistry {

    /// Registers all logic node handlers
    func registerLogicHandlers() {
        register([
            RedirectUrlHandler(),
            SetVariableHandler(),
            JavaScriptFunctionHandler(),
            ConditionalHandler(),
            ABTestHandler(),
            SplitConversationHandler(),
            LogicDelayHandler()
        ])
    }
}
