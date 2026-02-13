//
//  MissingNodeHandlers.swift
//  Conferbot
//
//  Implements all 19 missing node handlers to match the server's 58 node types.
//  Ported from Android SDK reference implementations (ChoiceNodeHandlers.kt,
//  LegacyNodeHandlers.kt, LogicNodeHandlers.kt, DisplayNodeHandlers.kt,
//  IntegrationNodeHandlers.kt).
//

import Foundation

// MARK: - Legacy Display Handlers (7 types)

// MARK: TwoChoicesNodeHandler

/// Handler for two-choices-node (legacy)
/// Displays 2 choice buttons with port-based routing
public final class TwoChoicesNodeHandler: BaseNodeHandler {

    public override var nodeType: String { NodeTypes.Display.twoChoices }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("Two choices node missing data")
        }

        let nodeId = getNodeId(node) ?? UUID().uuidString
        let choice1 = getString(data, "choice1") ?? "Option 1"
        let choice2 = getString(data, "choice2") ?? "Option 2"
        let disableSecond = getBool(data, "disableSecondChoice") ?? false

        var options: [ChoiceOption] = [
            ChoiceOption(id: "0", label: stripHtml(choice1), value: stripHtml(choice1))
        ]

        if !disableSecond {
            options.append(
                ChoiceOption(id: "1", label: stripHtml(choice2), value: stripHtml(choice2))
            )
        }

        return .displayUI(.singleChoice(options: options, nodeId: nodeId))
    }

    private func stripHtml(_ text: String) -> String {
        return text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }
}

// MARK: ThreeChoicesNodeHandler

/// Handler for three-choices-node (legacy)
/// Displays 3 choice buttons with port-based routing
public final class ThreeChoicesNodeHandler: BaseNodeHandler {

    public override var nodeType: String { NodeTypes.Display.threeChoices }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("Three choices node missing data")
        }

        let nodeId = getNodeId(node) ?? UUID().uuidString
        let choice1 = getString(data, "choice1") ?? "Option 1"
        let choice2 = getString(data, "choice2") ?? "Option 2"
        let choice3 = getString(data, "choice3") ?? "Option 3"

        let options: [ChoiceOption] = [
            ChoiceOption(id: "0", label: stripHtml(choice1), value: stripHtml(choice1)),
            ChoiceOption(id: "1", label: stripHtml(choice2), value: stripHtml(choice2)),
            ChoiceOption(id: "2", label: stripHtml(choice3), value: stripHtml(choice3))
        ]

        return .displayUI(.singleChoice(options: options, nodeId: nodeId))
    }

    private func stripHtml(_ text: String) -> String {
        return text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }
}

// MARK: SelectOptionNodeHandler

/// Handler for select-option-node (legacy)
/// Displays dropdown/option selection (up to 5 options)
public final class SelectOptionNodeHandler: BaseNodeHandler {

    public override var nodeType: String { NodeTypes.Display.selectOption }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("Select option node missing data")
        }

        let nodeId = getNodeId(node) ?? UUID().uuidString

        // Build options from option1..option5
        var options: [ChoiceOption] = []
        for i in 1...5 {
            let optionKey = "option\(i)"
            let disableKey = "disableOption\(i)"

            if getBool(data, disableKey) == true { continue }

            if let optionText = getString(data, optionKey), !optionText.isEmpty {
                options.append(ChoiceOption(
                    id: "\(i - 1)",
                    label: stripHtml(optionText),
                    value: stripHtml(optionText)
                ))
            }
        }

        return .displayUI(.singleChoice(options: options, nodeId: nodeId))
    }

    private func stripHtml(_ text: String) -> String {
        return text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }
}

// MARK: UserRatingNodeHandler

/// Handler for user-rating-node (legacy)
/// Displays a simple 5-star rating
public final class UserRatingNodeHandler: BaseNodeHandler {

    public override var nodeType: String { NodeTypes.Display.userRating }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        let nodeId = getNodeId(node) ?? UUID().uuidString
        return .displayUI(.rating(max: 5, style: .stars, nodeId: nodeId))
    }
}

// MARK: UserInputNodeHandler

/// Handler for user-input-node (legacy)
/// Multi-purpose input handler: name, email, number, url, phone, file, date
public final class UserInputNodeHandler: BaseNodeHandler {

    public override var nodeType: String { NodeTypes.Display.userInput }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("User input node missing data")
        }

        let nodeId = getNodeId(node) ?? UUID().uuidString
        let inputType = (getString(data, "type") ?? "text").lowercased()

        switch inputType {
        case "name":
            return .displayUI(.textInput(
                placeholder: "Enter your name",
                validation: nil,
                nodeId: nodeId
            ))
        case "email":
            return .displayUI(.textInput(
                placeholder: "Enter your email",
                validation: .email,
                nodeId: nodeId
            ))
        case "number":
            return .displayUI(.textInput(
                placeholder: "Enter a number",
                validation: .number,
                nodeId: nodeId
            ))
        case "url":
            return .displayUI(.textInput(
                placeholder: "Enter a URL",
                validation: .url,
                nodeId: nodeId
            ))
        case "mobile", "phone":
            return .displayUI(.textInput(
                placeholder: "Enter phone number",
                validation: .phone,
                nodeId: nodeId
            ))
        case "file":
            return .displayUI(.fileUpload(
                allowedTypes: ["*/*"],
                maxSize: 5 * 1024 * 1024,
                nodeId: nodeId
            ))
        case "date":
            return .displayUI(.calendar(mode: .date, nodeId: nodeId))
        default:
            return .displayUI(.textInput(
                placeholder: "Type here...",
                validation: nil,
                nodeId: nodeId
            ))
        }
    }
}

// MARK: UserRangeNodeHandler

/// Handler for user-range-node (legacy)
/// Displays a range slider
public final class UserRangeNodeHandler: BaseNodeHandler {

    public override var nodeType: String { NodeTypes.Display.userRange }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("User range node missing data")
        }

        let nodeId = getNodeId(node) ?? UUID().uuidString
        let minVal = getInt(data, "minVal") ?? 0
        let maxVal = getInt(data, "maxVal") ?? 100

        // Display as an opinion scale since iOS SDK has no dedicated range slider UI
        return .displayUI(.opinionScale(
            min: minVal,
            max: maxVal,
            minLabel: "\(minVal)",
            maxLabel: "\(maxVal)",
            nodeId: nodeId
        ))
    }
}

// MARK: QuizNodeHandler

/// Handler for quiz-node (legacy)
/// Displays a quiz question with correct/incorrect branching
public final class QuizNodeHandler: BaseNodeHandler {

    public override var nodeType: String { NodeTypes.Display.quiz }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("Quiz node missing data")
        }

        let nodeId = getNodeId(node) ?? UUID().uuidString

        // Build options from option1..option5
        var options: [ChoiceOption] = []
        for i in 1...5 {
            let optionKey = "option\(i)"
            let disableKey = "disableOption\(i)"

            if getBool(data, disableKey) == true { continue }

            if let optionText = getString(data, optionKey), !optionText.isEmpty {
                options.append(ChoiceOption(
                    id: "\(i - 1)",
                    label: stripHtml(optionText),
                    value: stripHtml(optionText)
                ))
            }
        }

        // Quiz uses singleChoice UI; the correct answer index is stored in data
        // for response-time validation
        return .displayUI(.singleChoice(options: options, nodeId: nodeId))
    }

    private func stripHtml(_ text: String) -> String {
        return text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }
}

// MARK: - Ask/Choice Display Handlers (5 types)

// MARK: AskMultipleQuestionsNodeHandler

/// Handler for ask-multiple-questions-node
/// Displays multiple questions in sequence (form-like)
public final class AskMultipleQuestionsNodeHandler: BaseNodeHandler {

    public override var nodeType: String { NodeTypes.Display.askMultipleQuestions }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("Ask multiple questions node missing data")
        }

        let nodeId = getNodeId(node) ?? UUID().uuidString

        // Extract the questions array
        guard let questions = getArray(data, "questions"), !questions.isEmpty else {
            // Fallback to basic text input if no questions defined
            return .displayUI(.textInput(
                placeholder: "Type your answer...",
                validation: nil,
                nodeId: nodeId
            ))
        }

        // For mobile, we display the first question and let the engine
        // iterate through questions via response handling
        let firstQuestion = questions[0]
        let questionType = (firstQuestion["type"] as? String ?? "text").lowercased()
        let placeholder = firstQuestion["placeholder"] as? String

        switch questionType {
        case "email":
            return .displayUI(.textInput(
                placeholder: placeholder ?? "Enter your email",
                validation: .email,
                nodeId: nodeId
            ))
        case "phone":
            return .displayUI(.textInput(
                placeholder: placeholder ?? "Enter your phone number",
                validation: .phone,
                nodeId: nodeId
            ))
        case "number":
            return .displayUI(.textInput(
                placeholder: placeholder ?? "Enter a number",
                validation: .number,
                nodeId: nodeId
            ))
        case "url":
            return .displayUI(.textInput(
                placeholder: placeholder ?? "Enter a URL",
                validation: .url,
                nodeId: nodeId
            ))
        default:
            return .displayUI(.textInput(
                placeholder: placeholder ?? "Type your answer...",
                validation: nil,
                nodeId: nodeId
            ))
        }
    }
}

// MARK: NSelectOptionNodeHandler

/// Handler for n-select-option-node
/// Displays a dropdown with dynamic options
public final class NSelectOptionNodeHandler: BaseNodeHandler {

    public override var nodeType: String { NodeTypes.Display.nSelectOption }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("N select option node missing data")
        }

        let nodeId = getNodeId(node) ?? UUID().uuidString

        guard let optionsData = getArray(data, "options"), !optionsData.isEmpty else {
            return .error("N select option node missing options")
        }

        let options: [ChoiceOption] = optionsData.map { option in
            let id = option["id"] as? String ?? ""
            let text = option["optionText"] as? String ?? option["text"] as? String ?? ""
            return ChoiceOption(
                id: id,
                label: stripHtml(text),
                value: stripHtml(text)
            )
        }

        return .displayUI(.singleChoice(options: options, nodeId: nodeId))
    }

    private func stripHtml(_ text: String) -> String {
        return text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }
}

// MARK: NCheckOptionsNodeHandler

/// Handler for n-check-options-node
/// Displays multi-checkbox selection
public final class NCheckOptionsNodeHandler: BaseNodeHandler {

    public override var nodeType: String { NodeTypes.Display.nCheckOptions }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("N check options node missing data")
        }

        let nodeId = getNodeId(node) ?? UUID().uuidString

        guard let optionsData = getArray(data, "options"), !optionsData.isEmpty else {
            return .error("N check options node missing options")
        }

        let options: [ChoiceOption] = optionsData.map { option in
            let id = option["id"] as? String ?? ""
            let text = option["optionText"] as? String ?? option["text"] as? String ?? ""
            return ChoiceOption(
                id: id,
                label: stripHtml(text),
                value: stripHtml(text)
            )
        }

        return .displayUI(.multiChoice(options: options, nodeId: nodeId))
    }

    private func stripHtml(_ text: String) -> String {
        return text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }
}

// MARK: ImageChoiceNodeHandler

/// Handler for image-choice-node
/// Displays image grid selection
public final class ImageChoiceNodeHandler: BaseNodeHandler {

    public override var nodeType: String { NodeTypes.Display.imageChoice }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("Image choice node missing data")
        }

        let nodeId = getNodeId(node) ?? UUID().uuidString

        guard let imagesData = getArray(data, "images"), !imagesData.isEmpty else {
            return .error("Image choice node missing images")
        }

        let options: [ChoiceOption] = imagesData.map { image in
            let id = image["id"] as? String ?? ""
            let label = image["label"] as? String ?? ""
            let imageUrl = image["image"] as? String ?? image["imageUrl"] as? String
            return ChoiceOption(
                id: id,
                label: label,
                value: label,
                imageUrl: imageUrl
            )
        }

        // Use singleChoice with image URLs for now
        return .displayUI(.singleChoice(options: options, nodeId: nodeId))
    }
}

// MARK: YesOrNoChoiceNodeHandler

/// Handler for yes-or-no-choice-node
/// Displays binary Yes/No choice buttons
public final class YesOrNoChoiceNodeHandler: BaseNodeHandler {

    public override var nodeType: String { NodeTypes.Display.yesOrNoChoice }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        let data = getNodeData(node)
        let nodeId = getNodeId(node) ?? UUID().uuidString

        // Check if custom options are provided
        var options: [ChoiceOption] = []

        if let optionsData = data.flatMap({ getArray($0, "options") }), !optionsData.isEmpty {
            options = optionsData.map { option in
                let id = option["id"] as? String ?? ""
                let label = option["label"] as? String ?? option["text"] as? String ?? ""
                return ChoiceOption(id: id, label: label, value: label)
            }
        } else {
            // Default Yes/No options
            options = [
                ChoiceOption(id: "yes", label: "Yes", value: "Yes"),
                ChoiceOption(id: "no", label: "No", value: "No")
            ]
        }

        return .displayUI(.singleChoice(options: options, nodeId: nodeId))
    }
}

// MARK: - Special Display Handler (1 type)

// MARK: NavigateNodeHandler

/// Handler for navigate-node
/// In-app navigation / internal redirect
public final class NavigateNodeHandler: BaseNodeHandler {

    public override var nodeType: String { NodeTypes.Display.navigate }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("Navigate node missing data")
        }

        guard let url = getString(data, "url") ?? getString(data, "href") else {
            return .error("Navigate node missing URL")
        }

        // Resolve any variables in the URL
        let resolvedUrl = state.resolveVariables(text: url)

        // Return as a link for the UI layer to handle as in-app navigation
        return .displayUI(.link(url: resolvedUrl, text: nil))
    }
}

// MARK: - Logic Handlers (4 types)

// MARK: BooleanLogicNodeHandler

/// Handler for boolean-logic-node
/// Performs boolean operations (AND/OR/NOT/XOR/NAND/NOR/XNOR)
public final class BooleanLogicNodeHandler: BaseNodeHandler {

    public override var nodeType: String { NodeTypes.Logic.booleanLogic }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("Boolean logic node missing data")
        }

        let leftValue = getString(data, "leftValue") ?? "false"
        let rightValue = getString(data, "rightValue") ?? "false"
        let operatorStr = getString(data, "operator") ?? "AND"

        // Resolve and convert to boolean
        let left = toBoolean(state.resolveVariables(text: leftValue), state: state)
        let right = toBoolean(state.resolveVariables(text: rightValue), state: state)

        let result: Bool
        switch operatorStr.uppercased() {
        case "AND":
            result = left && right
        case "OR":
            result = left || right
        case "NOT":
            result = left && !right
        case "XOR":
            result = left != right
        case "NAND":
            result = !(left && right)
        case "NOR":
            result = !(left || right)
        case "XNOR":
            result = left == right
        default:
            result = left && right
        }

        // Port-based routing: source-0 for true, source-1 for false
        // This maps to edge-based routing in the flow engine
        if result {
            // True branch
            let trueNodeId = extractPortNodeId(from: node, port: "source-0")
            if let targetId = trueNodeId {
                return .jumpTo(targetId)
            }
            return .proceed(getNextNodeId(node), ["result": true])
        } else {
            // False branch
            let falseNodeId = extractPortNodeId(from: node, port: "source-1")
            if let targetId = falseNodeId {
                return .jumpTo(targetId)
            }
            return .proceed(getNextNodeId(node), ["result": false])
        }
    }

    private func toBoolean(_ value: Any, state: ChatState) -> Bool {
        if let boolVal = value as? Bool { return boolVal }
        if let numVal = value as? NSNumber { return numVal.doubleValue != 0.0 }
        if let strVal = value as? String {
            let resolved = state.resolveVariables(text: strVal)
            let lower = resolved.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            return ["true", "yes", "1"].contains(lower)
        }
        return false
    }

    /// Extracts the target node ID for a specific port from the node's edges
    private func extractPortNodeId(from node: [String: Any], port: String) -> String? {
        if let edges = node["edges"] as? [[String: Any]] {
            for edge in edges {
                let sourceHandle = edge["sourceHandle"] as? String ?? edge["source_handle"] as? String ?? ""
                if sourceHandle == port {
                    return edge["target"] as? String ?? edge["targetNodeId"] as? String
                }
            }
        }
        return nil
    }
}

// MARK: MathOperationNodeHandler

/// Handler for math-operation-node
/// Performs mathematical operations (+, -, *, /, %)
public final class MathOperationNodeHandler: BaseNodeHandler {

    public override var nodeType: String { NodeTypes.Logic.mathOperation }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("Math operation node missing data")
        }

        let leftValue = getString(data, "leftValue") ?? "0"
        let rightValue = getString(data, "rightValue") ?? "0"
        let operatorStr = getString(data, "operator") ?? "+"

        // Resolve variable values
        let resolvedLeft = state.resolveVariables(text: leftValue)
        let resolvedRight = state.resolveVariables(text: rightValue)

        let left = Double(resolvedLeft) ?? 0.0
        let right = Double(resolvedRight) ?? 0.0

        let result: Double
        switch operatorStr {
        case "+":
            result = left + right
        case "-":
            result = left - right
        case "*":
            result = left * right
        case "/":
            result = right != 0 ? left / right : 0.0
        case "%":
            result = right != 0 ? left.truncatingRemainder(dividingBy: right) : 0.0
        default:
            result = left + right
        }

        // Store result in answer variable
        let nodeId = getNodeId(node) ?? UUID().uuidString
        state.setAnswer(nodeId: nodeId, value: result)

        let nextNodeId = getNextNodeId(node)
        return .proceed(nextNodeId, ["result": result])
    }
}

// MARK: JumpToNodeHandler

/// Handler for jump-to-node
/// Jumps to a specific node by ID
public final class JumpToNodeHandler: BaseNodeHandler {

    public override var nodeType: String { NodeTypes.Logic.jumpTo }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("Jump to node missing data")
        }

        let targetNodeId = getString(data, "targetNodeId")
            ?? getString(data, "nodeId")
            ?? getString(data, "target")

        guard let target = targetNodeId, !target.isEmpty else {
            return .error("Jump to node missing target node ID")
        }

        return .jumpTo(target)
    }
}

// MARK: BusinessHoursNodeHandler

/// Handler for business-hours-node
/// Routes based on current time vs configured business hours
public final class BusinessHoursNodeHandler: BaseNodeHandler {

    public override var nodeType: String { NodeTypes.Logic.businessHours }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("Business hours node missing data")
        }

        let timezoneString = getString(data, "timezone") ?? TimeZone.current.identifier
        let timezone = TimeZone(identifier: timezoneString) ?? TimeZone.current

        // Get current calendar in specified timezone
        var calendar = Calendar.current
        calendar.timeZone = timezone
        let now = Date()

        // Check excluded dates (format: yyyy-MM-dd)
        if let excludeDates = data["excludeDates"] as? [String] {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            dateFormatter.timeZone = timezone
            let currentDate = dateFormatter.string(from: now)
            if excludeDates.contains(currentDate) {
                return outsideBusinessHours(node: node)
            }
        }

        // Check excluded days
        let dayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        let currentDayIndex = calendar.component(.weekday, from: now) - 1 // 0-indexed
        let currentDayName = dayNames[currentDayIndex]

        if let excludeDays = data["excludeDays"] as? [String] {
            if excludeDays.contains(where: { $0.caseInsensitiveCompare(currentDayName) == .orderedSame }) {
                return outsideBusinessHours(node: node)
            }
        }

        // Check weekly hours
        guard let weeklyHours = getArray(data, "weeklyHours") else {
            // No hours configured, assume available
            return withinBusinessHours(node: node)
        }

        let dayHours = weeklyHours.first { hours in
            let dayName = hours["dayName"] as? String ?? ""
            return dayName.caseInsensitiveCompare(currentDayName) == .orderedSame
        }

        guard let hours = dayHours else {
            return outsideBusinessHours(node: node)
        }

        // Check if available this day
        if getBool(hours, "available") == false {
            return outsideBusinessHours(node: node)
        }

        // Check time slots
        guard let slots = getArray(hours, "slots"), !slots.isEmpty else {
            return outsideBusinessHours(node: node)
        }

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        timeFormatter.timeZone = timezone
        let currentTime = timeFormatter.string(from: now)

        let withinSlot = slots.contains { slot in
            let start = slot["start"] as? String ?? "00:00"
            let end = slot["end"] as? String ?? "23:59"
            return currentTime >= start && currentTime <= end
        }

        if withinSlot {
            return self.withinBusinessHours(node: node)
        } else {
            return outsideBusinessHours(node: node)
        }
    }

    /// Returns result for within business hours (source-0 port)
    private func withinBusinessHours(node: [String: Any]) -> NodeResult {
        let targetId = extractPortNodeId(from: node, port: "source-0")
        if let id = targetId {
            return .jumpTo(id)
        }
        return .proceed(getNextNodeId(node), ["withinBusinessHours": true])
    }

    /// Returns result for outside business hours (source-1 port)
    private func outsideBusinessHours(node: [String: Any]) -> NodeResult {
        let targetId = extractPortNodeId(from: node, port: "source-1")
        if let id = targetId {
            return .jumpTo(id)
        }
        return .proceed(getNextNodeId(node), ["withinBusinessHours": false])
    }

    /// Extracts the target node ID for a specific port from the node's edges
    private func extractPortNodeId(from node: [String: Any], port: String) -> String? {
        if let edges = node["edges"] as? [[String: Any]] {
            for edge in edges {
                let sourceHandle = edge["sourceHandle"] as? String ?? edge["source_handle"] as? String ?? ""
                if sourceHandle == port {
                    return edge["target"] as? String ?? edge["targetNodeId"] as? String
                }
            }
        }
        return nil
    }
}

// MARK: - Integration Handlers (2 types)

// MARK: GptNodeHandler

/// Handler for gpt-node
/// AI/GPT integration - emits socket event for server-side AI processing
public final class GptNodeHandler: BaseNodeHandler {

    public override var nodeType: String { NodeTypes.Integration.gpt }

    /// Socket client for emitting events
    private weak var socketClient: SocketClient?

    public init(socketClient: SocketClient? = nil) {
        self.socketClient = socketClient
        super.init()
    }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("GPT node missing data")
        }

        let nodeId = getNodeId(node) ?? UUID().uuidString

        // Extract AI configuration
        let provider = getString(data, "provider") ?? "openai"
        let model = getString(data, "selectedModel") ?? getString(data, "model") ?? ""
        let systemContext = getString(data, "context")
        let temperature = getDouble(data, "temperature") ?? 0.7
        let maxTokens = getInt(data, "maxTokens") ?? 1024

        // Get session info
        let sessionId = state.sessionId ?? state.getVariable(name: "_sessionId") as? String ?? ""
        let botId = state.record["botId"] as? String ?? ""

        // Build socket payload for server-side processing
        var payload: [String: Any] = [
            "chatSessionId": sessionId,
            "botId": botId,
            "nodeId": nodeId,
            "nodeType": "gpt",
            "provider": provider,
            "model": model,
            "temperature": temperature,
            "maxTokens": maxTokens,
            "variables": state.variables
        ]

        if let context = systemContext {
            payload["context"] = state.resolveVariables(text: context)
        }

        // Include conversation transcript for context
        let transcript = state.getTranscript()
        let recentMessages = transcript.suffix(20).map { entry -> [String: String] in
            let type = entry["type"] as? String ?? "user"
            let text = entry["text"] as? String ?? entry["message"] as? String ?? ""
            let role = type == "bot" ? "assistant" : "user"
            return ["role": role, "content": text]
        }
        payload["messages"] = recentMessages

        // Emit socket event for server processing
        socketClient?.emit(SocketEvents.gptNodeTrigger, payload)

        #if DEBUG
        print("[Conferbot] GPT node event emitted for server processing (provider: \(provider))")
        #endif

        // Record in transcript
        state.addToTranscript(entry: [
            "type": "system",
            "nodeType": "gpt",
            "provider": provider,
            "nodeId": nodeId
        ])

        // Display loading state while waiting for server response
        return .displayUI(.loading)
    }
}

// MARK: GmailNodeHandler

/// Handler for gmail-node
/// Gmail integration - emits socket event for server-side email sending via Gmail
public final class GmailNodeHandler: BaseNodeHandler {

    public override var nodeType: String { NodeTypes.Integration.gmail }

    /// Socket client for emitting events
    private weak var socketClient: SocketClient?

    public init(socketClient: SocketClient? = nil) {
        self.socketClient = socketClient
        super.init()
    }

    public override func handle(node: [String: Any], state: ChatState) async -> NodeResult {
        guard let data = getNodeData(node) else {
            return .error("Gmail node missing data")
        }

        let nodeId = getNodeId(node) ?? UUID().uuidString

        // Extract email fields with variable resolution
        let to = getString(data, "to").map { state.resolveVariables(text: $0) }
        let subject = getString(data, "subject").map { state.resolveVariables(text: $0) }
        let body = getString(data, "body").map { state.resolveVariables(text: $0) }
        let cc = getString(data, "cc").map { state.resolveVariables(text: $0) }
        let bcc = getString(data, "bcc").map { state.resolveVariables(text: $0) }
        let isHtml = getBool(data, "isHtml") ?? false

        // Get session info
        let sessionId = state.sessionId ?? state.getVariable(name: "_sessionId") as? String ?? ""
        let botId = state.record["botId"] as? String ?? ""

        // Build socket payload
        var payload: [String: Any] = [
            "chatSessionId": sessionId,
            "botId": botId,
            "nodeId": nodeId,
            "nodeType": "gmail",
            "isHtml": isHtml,
            "variables": state.variables
        ]

        if let toEmail = to { payload["to"] = toEmail }
        if let subjectText = subject { payload["subject"] = subjectText }
        if let bodyText = body { payload["body"] = bodyText }
        if let ccEmail = cc { payload["cc"] = ccEmail }
        if let bccEmail = bcc { payload["bcc"] = bccEmail }

        // Emit socket event for server processing
        socketClient?.emit(SocketEvents.gmailNodeTrigger, payload)

        #if DEBUG
        print("[Conferbot] Gmail node event emitted for server processing")
        #endif

        // Record in transcript
        state.addToTranscript(entry: [
            "type": "system",
            "nodeType": "gmail",
            "operation": "send",
            "nodeId": nodeId,
            "to": to as Any
        ])

        let nextNodeId = getNextNodeId(node)
        return .proceed(nextNodeId, ["gmailSent": true])
    }
}

// MARK: - Handler Registration Extension

public extension NodeHandlerRegistry {

    /// Registers all 19 missing node handlers
    func registerMissingHandlers() {
        register([
            // Legacy display (7)
            TwoChoicesNodeHandler(),
            ThreeChoicesNodeHandler(),
            SelectOptionNodeHandler(),
            UserRatingNodeHandler(),
            UserInputNodeHandler(),
            UserRangeNodeHandler(),
            QuizNodeHandler(),

            // Ask/Choice display (5)
            AskMultipleQuestionsNodeHandler(),
            NSelectOptionNodeHandler(),
            NCheckOptionsNodeHandler(),
            ImageChoiceNodeHandler(),
            YesOrNoChoiceNodeHandler(),

            // Special display (1)
            NavigateNodeHandler(),

            // Logic (4)
            BooleanLogicNodeHandler(),
            MathOperationNodeHandler(),
            JumpToNodeHandler(),
            BusinessHoursNodeHandler(),

            // Integration (2)
            GptNodeHandler(),
            GmailNodeHandler()
        ])
    }
}
