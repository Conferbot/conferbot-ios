//
//  LogicNodeHandlers.swift
//  Conferbot
//
//  The logic steps: condition, boolean-logic, math-operation, variable,
//  random-flow, jump-to and business-hours. They show nothing and route at
//  once. The rules are the web widget's, ported in Core/Flow/FlowLogic.swift
//  (handlers/conditionEval.ts, handlers/logicValues.ts); the routing is
//  handlers/logical.ts (as the React Native SDK's LogicNodeHandlers.ts):
//
//  - condition / boolean: true leaves by source-0, false by source-1;
//  - business hours: open source-0, closed source-1;
//  - random split: "source-" + the picked branch id (legacy: its position);
//    no wired branch ends the chat;
//  - math and variable save by name and take the first edge;
//  - jump-to: data.nodeId, else targetNodeId, else jumpTo; a missing target
//    ends the chat.
//

import Foundation

/// A variable read the way the web logic steps read it: the answers, first
/// entry by name; null when there is none (JavaScript's Number(null) is 0).
func answerLookup(_ state: ChatState) -> VariableLookup {
    { key in state.hasAnswerVariable(key) ? (state.answerValue(key) ?? NSNull()) : NSNull() }
}

/// condition-node: true -> source-0, false -> source-1.
public final class ConditionNodeHandler: BaseNodeHandler {
    public override var nodeType: String { "condition-node" }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        .port(FlowLogic.evaluateCondition(FlowKit.data(node), answerLookup(state)) ? "source-0" : "source-1")
    }
}

/// boolean-logic-node: "No", "off", "0" and empty are false; true -> source-0.
public final class BooleanLogicNodeHandler: BaseNodeHandler {
    public override var nodeType: String { "boolean-logic-node" }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        .port(FlowLogic.booleanResult(FlowKit.data(node), answerLookup(state)) ? "source-0" : "source-1")
    }
}

/// math-operation-node: leftValue op rightValue, saved by name (answerVariable, default "math_operations").
public final class MathOperationNodeHandler: BaseNodeHandler {
    public override var nodeType: String { "math-operation-node" }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        let data = FlowKit.data(node)
        state.saveVariableByName(FlowLogic.mathVariableName(data), value: FlowLogic.mathResult(data, answerLookup(state)), nodeId: FlowKit.id(node))
        return .next
    }
}

/// random-flow-node: a wired branch by weight, leaving by "source-" + its id.
public final class RandomFlowNodeHandler: BaseNodeHandler {
    public override var nodeType: String { "random-flow-node" }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        let ctx = ctxOf(node, state)
        let handles = ctx.edges().map { $0["sourceHandle"] as? String }
        return .port(FlowLogic.pickRandomHandle(FlowKit.data(node)["branches"], handles, ctx.random()) ?? FlowLogic.noPath)
    }
}

/// variable-node: data.value ({x} filled; a number with isNumber), saved by data.name.
public final class VariableNodeHandler: BaseNodeHandler {
    public override var nodeType: String { "variable-node" }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        let data = FlowKit.data(node)
        let name = JS.text(data["name"]).trimmed
        let value = FlowLogic.variableValue(data, answerLookup(state))
        if !name.isEmpty {
            state.saveVariableByName(name, value: value, nodeId: FlowKit.id(node))
            state.setVariable(name: name, value: value)
        }
        return .next
    }
}

/// jump-to-node: to data.nodeId / targetNodeId / jumpTo; a missing target ends the chat.
public final class JumpToNodeHandler: BaseNodeHandler {
    public override var nodeType: String { "jump-to-node" }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        .jumpTo(FlowLogic.jumpTarget(FlowKit.data(node)))
    }
}

/// business-hours-node: open now on the owner's clock -> source-0, closed -> source-1.
public final class BusinessHoursNodeHandler: BaseNodeHandler {
    public override var nodeType: String { "business-hours-node" }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        let ctx = ctxOf(node, state)
        let open = FlowLogic.isWithinBusinessHours(FlowKit.data(node), now: ctx.now(), fallbackZone: ctx.visitorTimeZone)
        return .port(open ? "source-0" : "source-1")
    }
}

/// The logic steps.
enum LogicNodeHandlers {
    static var all: [NodeHandler] {
        [ConditionNodeHandler(), BooleanLogicNodeHandler(), MathOperationNodeHandler(), RandomFlowNodeHandler(),
         VariableNodeHandler(), JumpToNodeHandler(), BusinessHoursNodeHandler()]
    }
}
