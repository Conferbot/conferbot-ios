//
//  FileUploadService.swift
//  Conferbot
//
//  Service for uploading files to the Conferbot server with multipart form data,
//  progress tracking, and proper error handling.
//

import Foundation
import Combine

// MARK: - File Upload Error

/// Errors that can occur during file upload
public enum FileUploadError: LocalizedError {
    case fileTooLarge(maxSize: Int)
    case invalidFileType(allowed: [String])
    case networkError(Error)
    case invalidResponse
    case serverError(statusCode: Int, message: String?)
    case uploadFailed(reason: String)
    case cancelled
    case noData

    public var errorDescription: String? {
        switch self {
        case .fileTooLarge(let maxSize):
            let mbSize = maxSize / (1024 * 1024)
            return "File exceeds maximum size of \(mbSize)MB"
        case .invalidFileType(let allowed):
            return "Invalid file type. Allowed types: \(allowed.joined(separator: ", "))"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid server response"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message ?? "Unknown error")"
        case .uploadFailed(let reason):
            return "Upload failed: \(reason)"
        case .cancelled:
            return "Upload was cancelled"
        case .noData:
            return "No data received from server"
        }
    }
}

// MARK: - Upload Progress

/// Tracks the progress of a file upload
public struct UploadProgress {
    /// Progress value from 0.0 to 1.0
    public let progress: Double

    /// Bytes uploaded so far
    public let bytesUploaded: Int64

    /// Total bytes to upload
    public let totalBytes: Int64

    /// Estimated time remaining in seconds
    public let estimatedTimeRemaining: TimeInterval?

    public init(
        progress: Double,
        bytesUploaded: Int64,
        totalBytes: Int64,
        estimatedTimeRemaining: TimeInterval? = nil
    ) {
        self.progress = progress
        self.bytesUploaded = bytesUploaded
        self.totalBytes = totalBytes
        self.estimatedTimeRemaining = estimatedTimeRemaining
    }

    /// Formatted progress as percentage string
    public var percentageString: String {
        return String(format: "%.0f%%", progress * 100)
    }

    /// Formatted bytes uploaded (e.g., "2.5 MB / 10 MB")
    public var formattedProgress: String {
        let uploaded = ByteCountFormatter.string(fromByteCount: bytesUploaded, countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        return "\(uploaded) / \(total)"
    }
}

// MARK: - Upload Result

/// Result of a successful file upload
public struct UploadResult {
    /// The URL where the file was uploaded
    public let url: String

    /// Original filename
    public let filename: String

    /// MIME type of the uploaded file
    public let mimeType: String

    /// Size of the uploaded file in bytes
    public let fileSize: Int64

    /// Server-provided file ID (if any)
    public let fileId: String?

    public init(url: String, filename: String, mimeType: String, fileSize: Int64, fileId: String? = nil) {
        self.url = url
        self.filename = filename
        self.mimeType = mimeType
        self.fileSize = fileSize
        self.fileId = fileId
    }
}

// MARK: - File Upload Service

/// Service for handling file uploads to the Conferbot server
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public final class FileUploadService: NSObject {

    // MARK: - Properties

    private let apiKey: String
    private let botId: String
    private let baseURL: String
    private var uploadSession: URLSession?
    private var progressSubject = PassthroughSubject<UploadProgress, Never>()

    /// Publisher for upload progress updates
    public var progressPublisher: AnyPublisher<UploadProgress, Never> {
        progressSubject.eraseToAnyPublisher()
    }

    /// Current upload task (for cancellation)
    private var currentTask: URLSessionUploadTask?

    /// Upload start time for progress estimation
    private var uploadStartTime: Date?

    /// Continuation for async/await support
    private var uploadContinuation: CheckedContinuation<UploadResult, Error>?

    // MARK: - Initialization

    /// Initialize the file upload service
    /// - Parameters:
    ///   - apiKey: The API key for authentication
    ///   - botId: The bot identifier
    ///   - baseURL: Base URL for the API (defaults to Conferbot API)
    public init(
        apiKey: String,
        botId: String,
        baseURL: String = ConferBotConstants.defaultApiBaseURL
    ) {
        self.apiKey = apiKey
        self.botId = botId
        self.baseURL = baseURL
        super.init()

        // Create upload session with delegate for progress tracking
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120 // 2 minute timeout for uploads
        config.timeoutIntervalForResource = 300 // 5 minute total timeout
        uploadSession = URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }

    // MARK: - Public Methods

    /// Upload a file to the server
    /// - Parameters:
    ///   - data: The file data to upload
    ///   - filename: The original filename
    ///   - mimeType: The MIME type of the file
    ///   - sessionId: Optional chat session ID for association
    /// - Returns: The URL of the uploaded file
    /// - Throws: FileUploadError if upload fails
    public func uploadFile(
        data: Data,
        filename: String,
        mimeType: String,
        sessionId: String? = nil
    ) async throws -> String {
        let result = try await uploadFileWithResult(data: data, filename: filename, mimeType: mimeType, sessionId: sessionId)
        return result.url
    }

    /// Upload a file and get detailed result
    /// - Parameters:
    ///   - data: The file data to upload
    ///   - filename: The original filename
    ///   - mimeType: The MIME type of the file
    ///   - sessionId: Optional chat session ID for association
    /// - Returns: UploadResult with URL and metadata
    /// - Throws: FileUploadError if upload fails
    public func uploadFileWithResult(
        data: Data,
        filename: String,
        mimeType: String,
        sessionId: String? = nil
    ) async throws -> UploadResult {
        // Validate file size (max 10MB)
        let maxSize = ConferBotConstants.maxFileSize
        guard data.count <= maxSize else {
            throw FileUploadError.fileTooLarge(maxSize: maxSize)
        }

        // Create multipart form data
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()

        // Add file data
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)

        // Add session ID if provided
        if let sessionId = sessionId {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"sessionId\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(sessionId)\r\n".data(using: .utf8)!)
        }

        // Add bot ID
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"botId\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(botId)\r\n".data(using: .utf8)!)

        // Close boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        // Create request
        guard let url = URL(string: "\(baseURL)/upload") else {
            throw FileUploadError.uploadFailed(reason: "Invalid upload URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: ConferBotConstants.headerApiKey)
        request.setValue(botId, forHTTPHeaderField: ConferBotConstants.headerBotId)
        request.setValue(ConferBotConstants.platformIdentifier, forHTTPHeaderField: ConferBotConstants.headerPlatform)

        // Start upload with progress tracking
        uploadStartTime = Date()

        return try await withCheckedThrowingContinuation { continuation in
            self.uploadContinuation = continuation

            guard let session = uploadSession else {
                continuation.resume(throwing: FileUploadError.uploadFailed(reason: "Upload session not available"))
                return
            }

            let task = session.uploadTask(with: request, from: body) { [weak self] responseData, response, error in
                self?.handleUploadCompletion(
                    data: responseData,
                    response: response,
                    error: error,
                    filename: filename,
                    mimeType: mimeType,
                    fileSize: Int64(data.count)
                )
            }

            currentTask = task
            task.resume()
        }
    }

    /// Upload a file from a URL
    /// - Parameters:
    ///   - fileURL: The local file URL
    ///   - sessionId: Optional chat session ID
    /// - Returns: The URL of the uploaded file
    /// - Throws: FileUploadError if upload fails
    public func uploadFile(
        from fileURL: URL,
        sessionId: String? = nil
    ) async throws -> String {
        // Start accessing security-scoped resource
        let accessing = fileURL.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        // Read file data
        let data = try Data(contentsOf: fileURL)
        let filename = fileURL.lastPathComponent
        let mimeType = mimeType(for: fileURL)

        return try await uploadFile(data: data, filename: filename, mimeType: mimeType, sessionId: sessionId)
    }

    /// Cancel the current upload
    public func cancelUpload() {
        currentTask?.cancel()
        currentTask = nil
        uploadContinuation?.resume(throwing: FileUploadError.cancelled)
        uploadContinuation = nil
    }

    // MARK: - Private Methods

    private func handleUploadCompletion(
        data: Data?,
        response: URLResponse?,
        error: Error?,
        filename: String,
        mimeType: String,
        fileSize: Int64
    ) {
        defer {
            currentTask = nil
            uploadContinuation = nil
        }

        if let error = error {
            if (error as NSError).code == NSURLErrorCancelled {
                uploadContinuation?.resume(throwing: FileUploadError.cancelled)
            } else {
                uploadContinuation?.resume(throwing: FileUploadError.networkError(error))
            }
            return
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            uploadContinuation?.resume(throwing: FileUploadError.invalidResponse)
            return
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            var message: String?
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                message = json["error"] as? String ?? json["message"] as? String
            }
            uploadContinuation?.resume(throwing: FileUploadError.serverError(statusCode: httpResponse.statusCode, message: message))
            return
        }

        guard let data = data else {
            uploadContinuation?.resume(throwing: FileUploadError.noData)
            return
        }

        // Parse response
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw FileUploadError.invalidResponse
            }

            // Try to get URL from response
            let uploadedUrl: String
            if let dataDict = json["data"] as? [String: Any] {
                uploadedUrl = dataDict["url"] as? String ?? dataDict["fileUrl"] as? String ?? ""
            } else {
                uploadedUrl = json["url"] as? String ?? json["fileUrl"] as? String ?? ""
            }

            guard !uploadedUrl.isEmpty else {
                throw FileUploadError.uploadFailed(reason: "No URL in response")
            }

            // Get file ID if present
            var fileId: String?
            if let dataDict = json["data"] as? [String: Any] {
                fileId = dataDict["fileId"] as? String ?? dataDict["id"] as? String
            } else {
                fileId = json["fileId"] as? String ?? json["id"] as? String
            }

            let result = UploadResult(
                url: uploadedUrl,
                filename: filename,
                mimeType: mimeType,
                fileSize: fileSize,
                fileId: fileId
            )

            uploadContinuation?.resume(returning: result)

        } catch {
            uploadContinuation?.resume(throwing: error)
        }
    }

    /// Get MIME type for a file URL
    private func mimeType(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()

        switch ext {
        // Images
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "gif":
            return "image/gif"
        case "webp":
            return "image/webp"
        case "heic":
            return "image/heic"
        case "svg":
            return "image/svg+xml"

        // Documents
        case "pdf":
            return "application/pdf"
        case "doc":
            return "application/msword"
        case "docx":
            return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "xls":
            return "application/vnd.ms-excel"
        case "xlsx":
            return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "ppt":
            return "application/vnd.ms-powerpoint"
        case "pptx":
            return "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        case "txt":
            return "text/plain"
        case "csv":
            return "text/csv"
        case "rtf":
            return "application/rtf"

        // Audio
        case "mp3":
            return "audio/mpeg"
        case "wav":
            return "audio/wav"
        case "m4a":
            return "audio/mp4"
        case "aac":
            return "audio/aac"

        // Video
        case "mp4":
            return "video/mp4"
        case "mov":
            return "video/quicktime"
        case "avi":
            return "video/x-msvideo"
        case "webm":
            return "video/webm"

        // Archives
        case "zip":
            return "application/zip"
        case "rar":
            return "application/vnd.rar"
        case "7z":
            return "application/x-7z-compressed"

        // Code/Data
        case "json":
            return "application/json"
        case "xml":
            return "application/xml"
        case "html":
            return "text/html"
        case "css":
            return "text/css"
        case "js":
            return "application/javascript"

        default:
            return "application/octet-stream"
        }
    }
}

// MARK: - URLSessionTaskDelegate

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension FileUploadService: URLSessionTaskDelegate {

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        let progress = totalBytesExpectedToSend > 0
            ? Double(totalBytesSent) / Double(totalBytesExpectedToSend)
            : 0

        // Calculate estimated time remaining
        var estimatedTime: TimeInterval?
        if let startTime = uploadStartTime, progress > 0 {
            let elapsed = Date().timeIntervalSince(startTime)
            let totalEstimated = elapsed / progress
            estimatedTime = totalEstimated - elapsed
        }

        let uploadProgress = UploadProgress(
            progress: progress,
            bytesUploaded: totalBytesSent,
            totalBytes: totalBytesExpectedToSend,
            estimatedTimeRemaining: estimatedTime
        )

        progressSubject.send(uploadProgress)
    }
}

// MARK: - Convenience Extension

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public extension FileUploadService {

    /// Validate file before upload
    /// - Parameters:
    ///   - data: File data
    ///   - filename: Filename
    ///   - allowedTypes: Optional array of allowed MIME types or extensions
    ///   - maxSizeBytes: Maximum file size in bytes (defaults to 10MB)
    /// - Throws: FileUploadError if validation fails
    static func validateFile(
        data: Data,
        filename: String,
        allowedTypes: [String]? = nil,
        maxSizeBytes: Int = ConferBotConstants.maxFileSize
    ) throws {
        // Check file size
        guard data.count <= maxSizeBytes else {
            throw FileUploadError.fileTooLarge(maxSize: maxSizeBytes)
        }

        // Check file type if restrictions are specified
        if let allowed = allowedTypes, !allowed.isEmpty {
            let ext = (filename as NSString).pathExtension.lowercased()
            let matches = allowed.contains { type in
                // Check if it's a MIME type pattern
                if type.contains("/") {
                    // For simplicity, check if extension matches the subtype
                    let subtype = type.components(separatedBy: "/").last ?? ""
                    if subtype == "*" {
                        return true
                    }
                    return ext == subtype || filename.hasSuffix(".\(subtype)")
                } else {
                    // It's an extension
                    return ext == type.lowercased().replacingOccurrences(of: ".", with: "")
                }
            }

            if !matches && !allowed.contains("*/*") {
                throw FileUploadError.invalidFileType(allowed: allowed)
            }
        }
    }

    /// Get file size as formatted string
    static func formattedFileSize(_ bytes: Int64) -> String {
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
