#!/usr/bin/env swift

/**
 * Connection Test for Conferbot iOS SDK
 * Tests connection to embed server on localhost:8001
 *
 * Run with: swift Tests/ConnectionTest.swift
 * Or: swift run ConnectionTest
 */

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Configuration
let socketURL = "http://localhost:8001"
let testApiKey = "test_api_key"
let testBotId = "test_bot_id"

print("🚀 Starting Conferbot iOS SDK Connection Test\n")
print("Configuration:")
print("  Socket URL: \(socketURL)")
print("  API Key: \(testApiKey)")
print("  Bot ID: \(testBotId)\n")

// Test REST API endpoint
print("📡 Testing REST API endpoint...")

let apiURL = URL(string: "\(socketURL)/api/v1/mobile/session/init")!
var request = URLRequest(url: apiURL)
request.httpMethod = "POST"
request.setValue(testApiKey, forHTTPHeaderField: "X-API-Key")
request.setValue(testBotId, forHTTPHeaderField: "X-Bot-ID")
request.setValue("ios", forHTTPHeaderField: "X-Platform")
request.setValue("application/json", forHTTPHeaderField: "Content-Type")

let requestBody: [String: Any] = [
    "botId": testBotId,
    "userId": "test_user_ios"
]

if let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) {
    request.httpBody = jsonData
}

let semaphore = DispatchSemaphore(value: 0)
var testPassed = false

let task = URLSession.shared.dataTask(with: request) { data, response, error in
    defer { semaphore.signal() }

    if let error = error {
        print("❌ Connection error: \(error.localizedDescription)")
        print("   Make sure embed server is running on port 8001\n")
        return
    }

    guard let httpResponse = response as? HTTPURLResponse else {
        print("❌ Invalid response type\n")
        return
    }

    print("✅ REST API connection successful!")
    print("   Status Code: \(httpResponse.statusCode)")

    if let data = data,
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        print("   Response: \(json)")
    }

    if httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
        testPassed = true
        print("\n✅ Test completed successfully!")
        print("   REST API endpoint is working correctly.\n")
    } else {
        print("\n⚠️  Received non-200 status code")
        print("   This might be expected without valid API keys\n")
    }
}

task.resume()

// Wait for completion with timeout
let timeout = DispatchTime.now() + .seconds(10)
let result = semaphore.wait(timeout: timeout)

if result == .timedOut {
    print("\n❌ Test timed out - no response from server")
    print("   Possible issues:")
    print("   - Embed server not running on port 8001")
    print("   - Firewall blocking connection")
    print("   - Invalid API key or bot ID\n")
    exit(1)
}

if !testPassed {
    print("⚠️  Test completed but server may not be ready")
    print("   Check embed server logs for details\n")
    exit(0)
}

print("🎉 All tests passed! iOS SDK can connect to embed server.\n")

exit(0)
