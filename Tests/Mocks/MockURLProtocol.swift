//
//  MockURLProtocol.swift
//  ConferbotTests
//
//  Mock URL protocol for intercepting and mocking network requests in tests.
//

import Foundation

/// Mock URL Protocol for intercepting network requests in tests
class MockURLProtocol: URLProtocol {

    /// Handler to provide mock responses
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data?))?

    /// Captured requests for verification
    static var capturedRequests: [URLRequest] = []

    /// Reset all state
    static func reset() {
        requestHandler = nil
        capturedRequests = []
    }

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        MockURLProtocol.capturedRequests.append(request)

        guard let handler = MockURLProtocol.requestHandler else {
            let error = NSError(
                domain: "MockURLProtocol",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No request handler set"]
            )
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if let data = data {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        // No-op
    }
}

/// Creates a URLSession configured to use MockURLProtocol
func createMockURLSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

/// Helper to create mock HTTP responses
func mockHTTPResponse(url: String, statusCode: Int) -> HTTPURLResponse {
    return HTTPURLResponse(
        url: URL(string: url)!,
        statusCode: statusCode,
        httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": "application/json"]
    )!
}

/// Helper to create mock JSON data
func mockJSONData(_ dictionary: [String: Any]) -> Data {
    return try! JSONSerialization.data(withJSONObject: dictionary)
}
