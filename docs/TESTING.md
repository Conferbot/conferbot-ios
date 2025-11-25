# iOS SDK Testing

## Connection Test

The `ConnectionTest.swift` file tests the connection to the Conferbot embed server.

### Prerequisites

- Xcode installed with Swift compiler
- Embed server running on `localhost:8001`

### Run the Test

**Option 1: Using Swift directly**
```bash
swift Tests/ConnectionTest.swift
```

**Option 2: Using Xcode**
1. Open the package in Xcode
2. Select the test target
3. Press Cmd+U to run tests

**Option 3: Using Swift Package Manager**
```bash
swift test
```

### Expected Output

**Success:**
```
🚀 Starting Conferbot iOS SDK Connection Test

Configuration:
  Socket URL: http://localhost:8001
  API Key: test_api_key
  Bot ID: test_bot_id

📡 Testing REST API endpoint...
✅ REST API connection successful!
   Status Code: 200
   Response: {...}

✅ Test completed successfully!
   REST API endpoint is working correctly.

🎉 All tests passed! iOS SDK can connect to embed server.
```

**Failure (server not running):**
```
❌ Connection error: Could not connect to the server
   Make sure embed server is running on port 8001
```

## Unit Tests

Run the full test suite with:
```bash
swift test
```

Or in Xcode:
```bash
xcodebuild test -scheme Conferbot
```
