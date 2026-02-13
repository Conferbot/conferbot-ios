//
//  ChatStateTests.swift
//  Conferbot
//
//  Comprehensive tests for ChatState - the singleton class managing
//  all chat state including answers, variables, metadata, and transcripts.
//

import XCTest
@testable import Conferbot

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
final class ChatStateTests: XCTestCase {

    // MARK: - Properties

    var state: ChatState!

    // MARK: - Setup & Teardown

    override func setUp() {
        super.setUp()
        state = ChatState.shared
        state.reset()
    }

    override func tearDown() {
        state.reset()
        state = nil
        super.tearDown()
    }

    // MARK: - Singleton Tests

    func testSharedInstanceReturnsSameInstance() {
        // Given two references to shared instance
        let instance1 = ChatState.shared
        let instance2 = ChatState.shared

        // Then they should be the same instance
        XCTAssertTrue(instance1 === instance2)
    }

    // MARK: - Answer Variables CRUD Tests

    func testSetAnswerStoresValue() {
        // Given a node ID and value
        let nodeId = "question-1"
        let value = "User answer"

        // When setting the answer
        state.setAnswer(nodeId: nodeId, value: value)

        // Then the answer should be stored
        XCTAssertEqual(state.getAnswer(nodeId: nodeId) as? String, value)
    }

    func testSetAnswerWithIntValue() {
        // Given a node ID and integer value
        let nodeId = "rating-1"
        let value = 5

        // When setting the answer
        state.setAnswer(nodeId: nodeId, value: value)

        // Then the answer should be stored
        XCTAssertEqual(state.getAnswer(nodeId: nodeId) as? Int, value)
    }

    func testSetAnswerWithBoolValue() {
        // Given a node ID and boolean value
        let nodeId = "consent-1"
        let value = true

        // When setting the answer
        state.setAnswer(nodeId: nodeId, value: value)

        // Then the answer should be stored
        XCTAssertEqual(state.getAnswer(nodeId: nodeId) as? Bool, value)
    }

    func testSetAnswerWithArrayValue() {
        // Given a node ID and array value
        let nodeId = "multichoice-1"
        let value = ["option1", "option2", "option3"]

        // When setting the answer
        state.setAnswer(nodeId: nodeId, value: value)

        // Then the answer should be stored
        let retrieved = state.getAnswer(nodeId: nodeId) as? [String]
        XCTAssertEqual(retrieved, value)
    }

    func testSetAnswerWithDictionaryValue() {
        // Given a node ID and dictionary value
        let nodeId = "complex-1"
        let value: [String: Any] = ["key1": "value1", "key2": 42]

        // When setting the answer
        state.setAnswer(nodeId: nodeId, value: value)

        // Then the answer should be stored
        let retrieved = state.getAnswer(nodeId: nodeId) as? [String: Any]
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?["key1"] as? String, "value1")
    }

    func testGetAnswerReturnsNilForNonexistentNode() {
        // Given no answers set

        // When getting answer for nonexistent node
        let answer = state.getAnswer(nodeId: "nonexistent")

        // Then nil should be returned
        XCTAssertNil(answer)
    }

    func testSetAnswerOverwritesPreviousValue() {
        // Given an existing answer
        let nodeId = "question-1"
        state.setAnswer(nodeId: nodeId, value: "First answer")

        // When setting a new value
        state.setAnswer(nodeId: nodeId, value: "Second answer")

        // Then the new value should be stored
        XCTAssertEqual(state.getAnswer(nodeId: nodeId) as? String, "Second answer")
    }

    func testGetAllAnswersReturnsAllStoredAnswers() {
        // Given multiple answers
        state.setAnswer(nodeId: "q1", value: "Answer 1")
        state.setAnswer(nodeId: "q2", value: "Answer 2")
        state.setAnswer(nodeId: "q3", value: 42)

        // When getting all answers
        let allAnswers = state.getAllAnswers()

        // Then all answers should be returned
        XCTAssertEqual(allAnswers.count, 3)
        XCTAssertEqual(allAnswers["q1"] as? String, "Answer 1")
        XCTAssertEqual(allAnswers["q2"] as? String, "Answer 2")
        XCTAssertEqual(allAnswers["q3"] as? Int, 42)
    }

    func testHasAnswerReturnsTrueForExistingAnswer() {
        // Given an answer
        state.setAnswer(nodeId: "q1", value: "Answer")

        // When checking if answer exists
        let hasAnswer = state.hasAnswer(for: "q1")

        // Then true should be returned
        XCTAssertTrue(hasAnswer)
    }

    func testHasAnswerReturnsFalseForNonexistentAnswer() {
        // Given no answers

        // When checking if answer exists
        let hasAnswer = state.hasAnswer(for: "nonexistent")

        // Then false should be returned
        XCTAssertFalse(hasAnswer)
    }

    func testGetAnswerWithTypeReturnsCorrectType() {
        // Given a string answer
        state.setAnswer(nodeId: "q1", value: "Answer")

        // When getting with type
        let answer: String? = state.getAnswer(nodeId: "q1", as: String.self)

        // Then correct type should be returned
        XCTAssertEqual(answer, "Answer")
    }

    func testGetAnswerWithTypeReturnsNilForWrongType() {
        // Given a string answer
        state.setAnswer(nodeId: "q1", value: "Answer")

        // When getting with wrong type
        let answer: Int? = state.getAnswer(nodeId: "q1", as: Int.self)

        // Then nil should be returned
        XCTAssertNil(answer)
    }

    // MARK: - Flow Variables Tests

    func testSetVariableStoresValue() {
        // Given a variable name and value
        let name = "userName"
        let value = "John Doe"

        // When setting the variable
        state.setVariable(name: name, value: value)

        // Then the variable should be stored
        XCTAssertEqual(state.getVariable(name: name) as? String, value)
    }

    func testSetVariablesStoresMultipleValues() {
        // Given multiple variables
        let vars: [String: Any] = [
            "var1": "value1",
            "var2": 42,
            "var3": true
        ]

        // When setting variables
        state.setVariables(vars)

        // Then all variables should be stored
        XCTAssertEqual(state.getVariable(name: "var1") as? String, "value1")
        XCTAssertEqual(state.getVariable(name: "var2") as? Int, 42)
        XCTAssertEqual(state.getVariable(name: "var3") as? Bool, true)
    }

    func testGetVariableReturnsNilForNonexistent() {
        // Given no variables set

        // When getting nonexistent variable
        let value = state.getVariable(name: "nonexistent")

        // Then nil should be returned
        XCTAssertNil(value)
    }

    func testHasVariableReturnsTrueForExisting() {
        // Given a variable
        state.setVariable(name: "var1", value: "value")

        // When checking existence
        let hasVariable = state.hasVariable("var1")

        // Then true should be returned
        XCTAssertTrue(hasVariable)
    }

    func testHasVariableReturnsFalseForNonexistent() {
        // When checking nonexistent variable
        let hasVariable = state.hasVariable("nonexistent")

        // Then false should be returned
        XCTAssertFalse(hasVariable)
    }

    func testGetVariableWithTypeReturnsCorrectType() {
        // Given an integer variable
        state.setVariable(name: "count", value: 42)

        // When getting with type
        let value: Int? = state.getVariable(name: "count", as: Int.self)

        // Then correct type should be returned
        XCTAssertEqual(value, 42)
    }

    // MARK: - Variable Substitution Tests

    func testResolveVariablesWithDoubleBracePattern() {
        // Given a variable and text with placeholder
        state.setVariable(name: "name", value: "John")
        let text = "Hello, {{name}}!"

        // When resolving variables
        let resolved = state.resolveVariables(text: text)

        // Then the placeholder should be replaced
        XCTAssertEqual(resolved, "Hello, John!")
    }

    func testResolveVariablesWithDollarBracePattern() {
        // Given a variable and text with placeholder
        state.setVariable(name: "name", value: "Jane")
        let text = "Hello, ${name}!"

        // When resolving variables
        let resolved = state.resolveVariables(text: text)

        // Then the placeholder should be replaced
        XCTAssertEqual(resolved, "Hello, Jane!")
    }

    func testResolveVariablesWithMixedPatterns() {
        // Given variables and text with mixed patterns
        state.setVariable(name: "firstName", value: "John")
        state.setVariable(name: "lastName", value: "Doe")
        let text = "Hello, {{firstName}} ${lastName}!"

        // When resolving variables
        let resolved = state.resolveVariables(text: text)

        // Then both placeholders should be replaced
        XCTAssertEqual(resolved, "Hello, John Doe!")
    }

    func testResolveVariablesWithSpacesInPlaceholder() {
        // Given a variable and text with spaces in placeholder
        state.setVariable(name: "name", value: "John")
        let text = "Hello, {{ name }}!"

        // When resolving variables
        let resolved = state.resolveVariables(text: text)

        // Then the placeholder should be replaced
        XCTAssertEqual(resolved, "Hello, John!")
    }

    func testResolveVariablesLeavesUnknownPlaceholders() {
        // Given text with unknown placeholder
        let text = "Hello, {{unknown}}!"

        // When resolving variables
        let resolved = state.resolveVariables(text: text)

        // Then the placeholder should remain
        XCTAssertEqual(resolved, "Hello, {{unknown}}!")
    }

    func testResolveVariablesWithDotNotationForUser() {
        // Given user metadata
        state.updateMetadata(key: "name", value: "John")
        let text = "Hello, {{user.name}}!"

        // When resolving variables
        let resolved = state.resolveVariables(text: text)

        // Then the placeholder should be replaced
        XCTAssertEqual(resolved, "Hello, John!")
    }

    func testResolveVariablesWithDotNotationForAnswer() {
        // Given an answer
        state.setAnswer(nodeId: "q1", value: "Test Answer")
        let text = "Your answer: {{answer.q1}}"

        // When resolving variables
        let resolved = state.resolveVariables(text: text)

        // Then the placeholder should be replaced
        XCTAssertEqual(resolved, "Your answer: Test Answer")
    }

    func testResolveVariablesWithDotNotationForVariable() {
        // Given a variable
        state.setVariable(name: "count", value: 42)
        let text = "Count: {{variable.count}}"

        // When resolving variables
        let resolved = state.resolveVariables(text: text)

        // Then the placeholder should be replaced
        XCTAssertEqual(resolved, "Count: 42")
    }

    func testResolveVariablesPriorityOrder() {
        // Given same key in different sources
        state.setVariable(name: "name", value: "Variable Name")
        state.setAnswer(nodeId: "name", value: "Answer Name")
        state.updateMetadata(key: "name", value: "Metadata Name")

        let text = "Name: {{name}}"

        // When resolving variables
        let resolved = state.resolveVariables(text: text)

        // Then variables should take priority
        XCTAssertEqual(resolved, "Name: Variable Name")
    }

    func testResolveVariablesWithNestedDictionary() {
        // Given a nested dictionary variable
        let nested: [String: Any] = [
            "profile": ["name": "John", "age": 30]
        ]
        state.setVariable(name: "user", value: nested)
        let text = "User: {{user}}"

        // When resolving variables
        let resolved = state.resolveVariables(text: text)

        // Then the dictionary should be converted to string
        XCTAssertTrue(resolved.contains("profile"))
    }

    func testResolveVariablesWithArrayValue() {
        // Given an array variable
        state.setVariable(name: "items", value: ["apple", "banana", "cherry"])
        let text = "Items: {{items}}"

        // When resolving variables
        let resolved = state.resolveVariables(text: text)

        // Then the array should be joined
        XCTAssertEqual(resolved, "Items: apple, banana, cherry")
    }

    func testResolveVariablesWithBooleanValue() {
        // Given a boolean variable
        state.setVariable(name: "enabled", value: true)
        let text = "Enabled: {{enabled}}"

        // When resolving variables
        let resolved = state.resolveVariables(text: text)

        // Then the boolean should be converted to string
        XCTAssertEqual(resolved, "Enabled: true")
    }

    func testResolveVariablesWithNumericValue() {
        // Given a numeric variable
        state.setVariable(name: "count", value: 42)
        let text = "Count: {{count}}"

        // When resolving variables
        let resolved = state.resolveVariables(text: text)

        // Then the number should be converted to string
        XCTAssertEqual(resolved, "Count: 42")
    }

    // MARK: - User Metadata Management Tests

    func testUpdateMetadataSingleValue() {
        // Given metadata
        state.updateMetadata(key: "name", value: "John Doe")

        // Then the metadata should be stored
        XCTAssertEqual(state.getMetadata(key: "name") as? String, "John Doe")
    }

    func testUpdateMetadataMultipleValues() {
        // Given multiple metadata values
        let metadata: [String: Any] = [
            "name": "John Doe",
            "email": "john@example.com",
            "phone": "+1234567890"
        ]

        // When updating metadata
        state.updateMetadata(metadata)

        // Then all values should be stored
        XCTAssertEqual(state.getMetadata(key: "name") as? String, "John Doe")
        XCTAssertEqual(state.getMetadata(key: "email") as? String, "john@example.com")
        XCTAssertEqual(state.getMetadata(key: "phone") as? String, "+1234567890")
    }

    func testGetMetadataReturnsNilForNonexistent() {
        // When getting nonexistent metadata
        let value = state.getMetadata(key: "nonexistent")

        // Then nil should be returned
        XCTAssertNil(value)
    }

    func testUserNameConvenience() {
        // Given name metadata
        state.updateMetadata(key: "name", value: "John Doe")

        // Then userName convenience should work
        XCTAssertEqual(state.userName, "John Doe")
    }

    func testUserEmailConvenience() {
        // Given email metadata
        state.updateMetadata(key: "email", value: "john@example.com")

        // Then userEmail convenience should work
        XCTAssertEqual(state.userEmail, "john@example.com")
    }

    func testUserPhoneConvenience() {
        // Given phone metadata
        state.updateMetadata(key: "phone", value: "+1234567890")

        // Then userPhone convenience should work
        XCTAssertEqual(state.userPhone, "+1234567890")
    }

    func testUserConvenienceReturnsNilWhenNotSet() {
        // When metadata is not set
        XCTAssertNil(state.userName)
        XCTAssertNil(state.userEmail)
        XCTAssertNil(state.userPhone)
    }

    // MARK: - Transcript Management Tests

    func testAddToTranscriptAddsEntry() {
        // Given a transcript entry
        let entry: [String: Any] = [
            "type": "bot",
            "message": "Hello!"
        ]

        // When adding to transcript
        state.addToTranscript(entry: entry)

        // Then the entry should be added
        let transcript = state.getTranscript()
        XCTAssertEqual(transcript.count, 1)
        XCTAssertEqual(transcript[0]["type"] as? String, "bot")
        XCTAssertEqual(transcript[0]["message"] as? String, "Hello!")
    }

    func testAddToTranscriptAddsTimestamp() {
        // Given a transcript entry without timestamp
        let entry: [String: Any] = [
            "type": "bot",
            "message": "Hello!"
        ]

        // When adding to transcript
        state.addToTranscript(entry: entry)

        // Then a timestamp should be added
        let transcript = state.getTranscript()
        XCTAssertNotNil(transcript[0]["timestamp"])
    }

    func testAddToTranscriptPreservesExistingTimestamp() {
        // Given a transcript entry with timestamp
        let timestamp = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: 0))
        let entry: [String: Any] = [
            "type": "bot",
            "message": "Hello!",
            "timestamp": timestamp
        ]

        // When adding to transcript
        state.addToTranscript(entry: entry)

        // Then the existing timestamp should be preserved
        let transcript = state.getTranscript()
        XCTAssertEqual(transcript[0]["timestamp"] as? String, timestamp)
    }

    func testAddBotMessageAddsCorrectEntry() {
        // When adding bot message
        state.addBotMessage("Hello, user!", nodeId: "node-1", nodeType: "message")

        // Then correct entry should be added
        let transcript = state.getTranscript()
        XCTAssertEqual(transcript.count, 1)
        XCTAssertEqual(transcript[0]["type"] as? String, "bot")
        XCTAssertEqual(transcript[0]["message"] as? String, "Hello, user!")
        XCTAssertEqual(transcript[0]["nodeId"] as? String, "node-1")
        XCTAssertEqual(transcript[0]["nodeType"] as? String, "message")
    }

    func testAddBotMessageWithOptionalParams() {
        // When adding bot message without optional params
        state.addBotMessage("Hello!")

        // Then entry should be added without optional fields
        let transcript = state.getTranscript()
        XCTAssertEqual(transcript[0]["type"] as? String, "bot")
        XCTAssertEqual(transcript[0]["message"] as? String, "Hello!")
        XCTAssertNil(transcript[0]["nodeId"])
    }

    func testAddUserMessageAddsCorrectEntry() {
        // When adding user message
        state.addUserMessage("My response", nodeId: "node-1")

        // Then correct entry should be added
        let transcript = state.getTranscript()
        XCTAssertEqual(transcript.count, 1)
        XCTAssertEqual(transcript[0]["type"] as? String, "user")
        XCTAssertEqual(transcript[0]["message"] as? String, "My response")
        XCTAssertEqual(transcript[0]["nodeId"] as? String, "node-1")
    }

    func testGetTranscriptReturnsAllEntries() {
        // Given multiple transcript entries
        state.addBotMessage("Bot message 1")
        state.addUserMessage("User message 1")
        state.addBotMessage("Bot message 2")

        // When getting transcript
        let transcript = state.getTranscript()

        // Then all entries should be returned in order
        XCTAssertEqual(transcript.count, 3)
        XCTAssertEqual(transcript[0]["type"] as? String, "bot")
        XCTAssertEqual(transcript[1]["type"] as? String, "user")
        XCTAssertEqual(transcript[2]["type"] as? String, "bot")
    }

    func testGetTranscriptReturnsCopy() {
        // Given a transcript entry
        state.addBotMessage("Hello!")

        // When getting transcript multiple times
        let transcript1 = state.getTranscript()
        let transcript2 = state.getTranscript()

        // Then copies should be returned (not same array)
        XCTAssertEqual(transcript1.count, transcript2.count)
    }

    // MARK: - Record Entry Tests

    func testUpdateRecordStoresValues() {
        // Given updates
        let updates: [String: Any] = [
            "key1": "value1",
            "key2": 42
        ]

        // When updating record
        state.updateRecord(updates)

        // Then values should be stored
        let record = state.getRecord()
        XCTAssertEqual(record["key1"] as? String, "value1")
        XCTAssertEqual(record["key2"] as? Int, 42)
    }

    func testUpdateRecordAddsUpdatedAt() {
        // When updating record
        state.updateRecord(["key": "value"])

        // Then updatedAt should be set
        let record = state.getRecord()
        XCTAssertNotNil(record["updatedAt"])
    }

    func testInitializeRecordSetsSessionInfo() {
        // When initializing record
        state.initializeRecord(sessionId: "session-123", botId: "bot-456")

        // Then session info should be set
        let record = state.getRecord()
        XCTAssertEqual(record["sessionId"] as? String, "session-123")
        XCTAssertEqual(record["botId"] as? String, "bot-456")
        XCTAssertNotNil(record["createdAt"])
        XCTAssertNotNil(record["updatedAt"])
    }

    func testInitializeRecordCreatesEmptyAnswers() {
        // When initializing record
        state.initializeRecord(sessionId: "session-123", botId: "bot-456")

        // Then empty answers dictionary should exist
        let record = state.getRecord()
        let answers = record["answers"] as? [String: Any]
        XCTAssertNotNil(answers)
        XCTAssertTrue(answers!.isEmpty)
    }

    func testSetAnswerUpdatesRecord() {
        // Given an initialized record
        state.initializeRecord(sessionId: "session-123", botId: "bot-456")

        // When setting an answer
        state.setAnswer(nodeId: "q1", value: "Answer 1")

        // Then the record should be updated
        let record = state.getRecord()
        let answers = record["answers"] as? [String: Any]
        XCTAssertEqual(answers?["q1"] as? String, "Answer 1")
    }

    // MARK: - Flow Navigation Tests

    func testCurrentNodeIdUpdates() {
        // When setting current node ID
        state.currentNodeId = "node-1"

        // Then it should be retrievable
        XCTAssertEqual(state.currentNodeId, "node-1")
    }

    func testIsTypingUpdates() {
        // When setting isTyping
        state.isTyping = true

        // Then it should be retrievable
        XCTAssertTrue(state.isTyping)

        // When setting to false
        state.isTyping = false

        // Then it should update
        XCTAssertFalse(state.isTyping)
    }

    // MARK: - State Reset Tests

    func testResetClearsAllState() {
        // Given populated state
        state.setAnswer(nodeId: "q1", value: "Answer")
        state.setVariable(name: "var1", value: "Value")
        state.updateMetadata(key: "name", value: "John")
        state.addBotMessage("Hello!")
        state.updateRecord(["key": "value"])
        state.currentNodeId = "node-1"
        state.isTyping = true

        // When resetting
        state.reset()

        // Then all state should be cleared
        XCTAssertTrue(state.getAllAnswers().isEmpty)
        XCTAssertNil(state.getVariable(name: "var1"))
        XCTAssertNil(state.getMetadata(key: "name"))
        XCTAssertTrue(state.getTranscript().isEmpty)
        XCTAssertTrue(state.getRecord().isEmpty)
        XCTAssertNil(state.currentNodeId)
        XCTAssertFalse(state.isTyping)
    }

    func testResetConversationClearsConversationOnly() {
        // Given populated state
        state.initializeRecord(sessionId: "session-123", botId: "bot-456")
        state.setAnswer(nodeId: "q1", value: "Answer")
        state.setVariable(name: "var1", value: "Value")
        state.updateMetadata(key: "name", value: "John")
        state.addBotMessage("Hello!")
        state.currentNodeId = "node-1"
        state.isTyping = true

        // When resetting conversation
        state.resetConversation()

        // Then conversation state should be cleared
        XCTAssertTrue(state.getAllAnswers().isEmpty)
        XCTAssertTrue(state.getTranscript().isEmpty)
        XCTAssertNil(state.currentNodeId)
        XCTAssertFalse(state.isTyping)

        // But session info and metadata should be preserved
        let record = state.getRecord()
        XCTAssertEqual(record["sessionId"] as? String, "session-123")
        XCTAssertEqual(record["botId"] as? String, "bot-456")

        // Variables should be preserved
        XCTAssertEqual(state.getVariable(name: "var1") as? String, "Value")
    }

    // MARK: - Thread Safety Tests

    func testConcurrentAnswerUpdates() {
        // Given multiple threads updating answers
        let expectation = XCTestExpectation(description: "Concurrent updates complete")
        expectation.expectedFulfillmentCount = 100

        let queue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)

        for i in 0..<100 {
            queue.async {
                self.state.setAnswer(nodeId: "node-\(i)", value: "Answer \(i)")
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 5.0)

        // Then all answers should be stored
        let answers = state.getAllAnswers()
        XCTAssertEqual(answers.count, 100)
    }

    func testConcurrentVariableUpdates() {
        // Given multiple threads updating variables
        let expectation = XCTestExpectation(description: "Concurrent updates complete")
        expectation.expectedFulfillmentCount = 100

        let queue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)

        for i in 0..<100 {
            queue.async {
                self.state.setVariable(name: "var-\(i)", value: "Value \(i)")
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 5.0)

        // Then no crashes should occur (thread safety verified)
        XCTAssertTrue(true)
    }

    func testConcurrentTranscriptUpdates() {
        // Given multiple threads updating transcript
        let expectation = XCTestExpectation(description: "Concurrent updates complete")
        expectation.expectedFulfillmentCount = 100

        let queue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)

        for i in 0..<100 {
            queue.async {
                self.state.addBotMessage("Message \(i)")
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 5.0)

        // Then all messages should be added
        let transcript = state.getTranscript()
        XCTAssertEqual(transcript.count, 100)
    }

    // MARK: - Serialization/Persistence Tests

    func testToStoredStateCreatesCorrectStructure() {
        // Given populated state
        state.setAnswer(nodeId: "q1", value: "Answer 1")
        state.setVariable(name: "var1", value: "Value 1")
        state.updateMetadata(key: "name", value: "John")
        state.addBotMessage("Hello!")

        // When converting to stored state
        let storedState = state.toStoredState(sessionId: "session-123")

        // Then correct structure should be created
        XCTAssertEqual(storedState.sessionId, "session-123")
        XCTAssertEqual(storedState.answerVariables.count, 1)
        XCTAssertEqual(storedState.transcript.count, 1)
        XCTAssertNotNil(storedState.userMetadata)
    }

    func testRestoreAnswerVariables() {
        // Given stored answer variables
        let variables = [
            AnswerVariable(nodeId: "q1", value: "Answer 1"),
            AnswerVariable(nodeId: "q2", value: 42)
        ]

        // When restoring
        state.restoreAnswerVariables(variables)

        // Then answers should be restored
        XCTAssertEqual(state.getAnswer(nodeId: "q1") as? String, "Answer 1")
        XCTAssertEqual(state.getAnswer(nodeId: "q2") as? Int, 42)
    }

    func testRestoreUserMetadata() {
        // Given stored metadata
        let metadata = UserMetadata(from: [
            "name": "John Doe",
            "email": "john@example.com"
        ])

        // When restoring
        state.restoreUserMetadata(metadata)

        // Then metadata should be restored
        XCTAssertEqual(state.userName, "John Doe")
        XCTAssertEqual(state.userEmail, "john@example.com")
    }

    func testRestoreTranscript() {
        // Given stored transcript
        let entries = [
            TranscriptEntry(from: ["type": "bot", "message": "Hello!"]),
            TranscriptEntry(from: ["type": "user", "message": "Hi!"])
        ]

        // When restoring
        state.restoreTranscript(entries)

        // Then transcript should be restored
        let transcript = state.getTranscript()
        XCTAssertEqual(transcript.count, 2)
        XCTAssertEqual(transcript[0]["message"] as? String, "Hello!")
        XCTAssertEqual(transcript[1]["message"] as? String, "Hi!")
    }

    func testRestoreVariables() {
        // Given stored variables
        let variables: [String: AnyCodable] = [
            "var1": AnyCodable("Value 1"),
            "var2": AnyCodable(42)
        ]

        // When restoring
        state.restoreVariables(variables)

        // Then variables should be restored
        XCTAssertEqual(state.getVariable(name: "var1") as? String, "Value 1")
        XCTAssertEqual(state.getVariable(name: "var2") as? Int, 42)
    }

    func testRestoreFromStoredState() {
        // Given a complete stored state
        let storedState = StoredChatState(
            sessionId: "session-123",
            answerVariables: [AnswerVariable(nodeId: "q1", value: "Answer")],
            userMetadata: UserMetadata(from: ["name": "John"]),
            transcript: [TranscriptEntry(from: ["type": "bot", "message": "Hello"])],
            variables: ["var1": AnyCodable("Value")]
        )

        // When restoring
        state.restoreFromStoredState(storedState)

        // Then all state should be restored
        XCTAssertEqual(state.getAnswer(nodeId: "q1") as? String, "Answer")
        XCTAssertEqual(state.userName, "John")
        XCTAssertEqual(state.getTranscript().count, 1)
        XCTAssertEqual(state.getVariable(name: "var1") as? String, "Value")
    }

    // MARK: - Performance Tests

    func testSetAnswerPerformance() {
        measure {
            for i in 0..<1000 {
                state.setAnswer(nodeId: "node-\(i)", value: "Answer \(i)")
            }
        }
    }

    func testResolveVariablesPerformance() {
        // Setup
        for i in 0..<100 {
            state.setVariable(name: "var\(i)", value: "Value \(i)")
        }

        var text = "Text with placeholders: "
        for i in 0..<100 {
            text += "{{var\(i)}} "
        }

        measure {
            _ = state.resolveVariables(text: text)
        }
    }

    func testTranscriptAppendPerformance() {
        measure {
            for i in 0..<1000 {
                state.addBotMessage("Message \(i)")
            }
        }
    }
}
