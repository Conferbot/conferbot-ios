//
//  AgentHandover.swift
//  Conferbot
//
//  The initiate-handover payload for an AI agent bot's silent start, as the
//  web widget sends it (conferbot-widget buildAllMetaData +
//  _handleHumanHandoverNode, with silentStart).
//

import Foundation

public enum AgentHandover {

    public static func payload(state: ChatState, chatSessionId: String, botId: String, nodeData: [String: Any], extra: [String: Any] = [:]) -> [String: Any] {
        let workspaceId = state.workspaceId ?? (state.getVariable(name: "_workspaceId") as? String) ?? ""
        let botName = state.getVariable(name: "_botName") as? String ?? ""
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let now = formatter.string(from: Date())
        let device = "iOS/\(ProcessInfo.processInfo.operatingSystemVersionString)"
        let location = TimeZone.current.identifier

        let chatMetaData: [String: Any] = [
            "version": "v2",
            "workspaceId": workspaceId,
            "chatSessionId": chatSessionId,
            "botId": botId,
            "botName": botName,
            "chatDate": now,
            "deviceInfo": device,
            "location": location,
            "record": state.getServerRecord(),
            "answerVariables": state.getAnswerVariablesList(),
            "transcript": state.getTranscript()
        ]
        let metaData: [String: Any] = [
            "visitorId": state.visitorId ?? chatSessionId,
            "chatDate": now,
            "deviceInfo": device,
            "location": location
        ]
        var payload: [String: Any] = [
            "workspaceId": workspaceId,
            "chatbotId": botId,
            "chatbotName": botName,
            "chatSessionId": chatSessionId,
            "chatMetaData": chatMetaData,
            "metaData": metaData,
            "priority": nodeData["priority"] as? String ?? "normal",
            "maxWaitTime": LiveChat.waitMinutes(nodeData["maxWaitTime"]),
            "assignmentType": nodeData["assignmentType"] as? String ?? "auto",
            "assignmentStrategy": nodeData["agentAssignmentStrategy"] as? String ?? "",
            "assignedAgents": nodeData["assignedAgents"] as? [String] ?? [],
            "assignedAIAgents": nodeData["assignedAIAgents"] as? [String] ?? []
        ]
        stepSettings(nodeData).forEach { payload[$0.key] = $0.value }
        extra.forEach { payload[$0.key] = $0.value }
        return payload
    }

    /// The handover step's own settings, as the web widget sends them with
    /// initiate-handover: the team's email (an explicit false is what keeps
    /// it off), the sound, and the assignment overrides only when the step
    /// has them (a step that follows the workspace sends what it always did).
    public static func stepSettings(_ nodeData: [String: Any]) -> [String: Any] {
        var out: [String: Any] = [:]
        for key in ["enableHandoverEmail", "enableHandoverSound", "checkedSoundTab", "selectedSound", "customHandoverSoundUrl"] {
            if let v = nodeData[key], !(v is NSNull) { out[key] = v }
        }
        if let method = nodeData["assignmentMethod"] as? String, !method.isEmpty, method != "workspace" {
            out["assignmentMethod"] = method
        }
        if let skills = nodeData["requiredSkills"] as? [Any], !skills.isEmpty {
            out["requiredSkills"] = skills
        }
        return out
    }
}
