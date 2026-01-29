//
//  FilePickerView.swift
//  Conferbot
//
//  A comprehensive file picker component that supports:
//  - Document picker (UIDocumentPickerViewController)
//  - Image picker (PHPickerViewController)
//  - Camera capture
//  - File type filtering based on node config
//  - File size validation (max 10MB)
//  - Upload progress indicator
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import AVFoundation
import Combine

// MARK: - File Picker Configuration

/// Configuration for the file picker
@available(iOS 14.0, *)
public struct FilePickerConfiguration {
    /// Allowed MIME types or extensions
    public let allowedTypes: [String]?

    /// Maximum file size in bytes (default 10MB)
    public let maxSizeBytes: Int

    /// Whether to allow camera capture
    public let allowCamera: Bool

    /// Whether to allow photo library access
    public let allowPhotos: Bool

    /// Whether to allow document picker
    public let allowDocuments: Bool

    /// Custom title for the picker
    public let title: String?

    /// Selection limit (for photos only, 1 = single selection)
    public let selectionLimit: Int

    public init(
        allowedTypes: [String]? = nil,
        maxSizeBytes: Int = ConferBotConstants.maxFileSize,
        allowCamera: Bool = true,
        allowPhotos: Bool = true,
        allowDocuments: Bool = true,
        title: String? = nil,
        selectionLimit: Int = 1
    ) {
        self.allowedTypes = allowedTypes
        self.maxSizeBytes = maxSizeBytes
        self.allowCamera = allowCamera
        self.allowPhotos = allowPhotos
        self.allowDocuments = allowDocuments
        self.title = title
        self.selectionLimit = selectionLimit
    }

    /// Check if the configuration allows image types
    public var allowsImages: Bool {
        guard let types = allowedTypes else { return true }
        return types.isEmpty || types.contains { type in
            let lower = type.lowercased()
            return lower.contains("image") ||
                   lower == "jpg" || lower == "jpeg" ||
                   lower == "png" || lower == "gif" ||
                   lower == "heic" || lower == "webp" ||
                   lower == "*/*"
        }
    }

    /// Get UTTypes for document picker
    public var documentContentTypes: [UTType] {
        guard let types = allowedTypes, !types.isEmpty else {
            return [.item]
        }

        var utTypes: [UTType] = []

        for type in types {
            let lower = type.lowercased()

            // Handle MIME types
            if lower.contains("/") {
                if lower.hasPrefix("image/") {
                    if lower == "image/*" {
                        utTypes.append(.image)
                    } else if let ut = UTType(mimeType: lower) {
                        utTypes.append(ut)
                    }
                } else if lower.hasPrefix("video/") {
                    if lower == "video/*" {
                        utTypes.append(.movie)
                    } else if let ut = UTType(mimeType: lower) {
                        utTypes.append(ut)
                    }
                } else if lower.hasPrefix("audio/") {
                    if lower == "audio/*" {
                        utTypes.append(.audio)
                    } else if let ut = UTType(mimeType: lower) {
                        utTypes.append(ut)
                    }
                } else if lower == "application/pdf" {
                    utTypes.append(.pdf)
                } else if lower == "*/*" {
                    utTypes.append(.item)
                } else if let ut = UTType(mimeType: lower) {
                    utTypes.append(ut)
                }
            } else {
                // Handle extensions
                let ext = lower.replacingOccurrences(of: ".", with: "")
                if let ut = UTType(filenameExtension: ext) {
                    utTypes.append(ut)
                }
            }
        }

        return utTypes.isEmpty ? [.item] : utTypes
    }

    /// Get PHPicker filter for photos
    public var photoFilter: PHPickerFilter? {
        guard let types = allowedTypes, !types.isEmpty else {
            return .any(of: [.images, .videos])
        }

        var filters: [PHPickerFilter] = []

        for type in types {
            let lower = type.lowercased()
            if lower.contains("image") || lower == "jpg" || lower == "jpeg" ||
               lower == "png" || lower == "gif" || lower == "heic" || lower == "webp" {
                if !filters.contains(.images) {
                    filters.append(.images)
                }
            }
            if lower.contains("video") || lower == "mp4" || lower == "mov" || lower == "avi" {
                if !filters.contains(.videos) {
                    filters.append(.videos)
                }
            }
        }

        if filters.isEmpty {
            return .any(of: [.images, .videos])
        } else if filters.count == 1 {
            return filters.first
        } else {
            return .any(of: filters)
        }
    }
}

// MARK: - Selected File

/// Represents a selected file
@available(iOS 14.0, *)
public struct SelectedFile: Identifiable {
    public let id = UUID()
    public let data: Data
    public let filename: String
    public let mimeType: String
    public let fileSize: Int64
    public let thumbnail: UIImage?

    public init(data: Data, filename: String, mimeType: String, thumbnail: UIImage? = nil) {
        self.data = data
        self.filename = filename
        self.mimeType = mimeType
        self.fileSize = Int64(data.count)
        self.thumbnail = thumbnail
    }

    /// Formatted file size string
    public var formattedSize: String {
        return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    /// File extension
    public var fileExtension: String {
        return (filename as NSString).pathExtension.lowercased()
    }

    /// Whether this is an image file
    public var isImage: Bool {
        return mimeType.hasPrefix("image/")
    }

    /// Whether this is a video file
    public var isVideo: Bool {
        return mimeType.hasPrefix("video/")
    }
}

// MARK: - File Picker View

/// Main file picker view with multiple source options
@available(iOS 14.0, *)
public struct FilePickerView: View {
    let configuration: FilePickerConfiguration
    let onFileSelected: (SelectedFile) -> Void
    let onCancel: () -> Void
    let onError: (Error) -> Void

    @Environment(\.presentationMode) private var presentationMode
    @State private var showActionSheet = false
    @State private var showDocumentPicker = false
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var errorMessage: String?

    public init(
        configuration: FilePickerConfiguration = FilePickerConfiguration(),
        onFileSelected: @escaping (SelectedFile) -> Void,
        onCancel: @escaping () -> Void = {},
        onError: @escaping (Error) -> Void = { _ in }
    ) {
        self.configuration = configuration
        self.onFileSelected = onFileSelected
        self.onCancel = onCancel
        self.onError = onError
    }

    public var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text(configuration.title ?? "Select File")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    onCancel()
                    presentationMode.wrappedValue.dismiss()
                }
            }
            .padding(.horizontal)
            .padding(.top)

            // Error message
            if let error = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
            }

            // File size info
            Text("Maximum file size: \(ByteCountFormatter.string(fromByteCount: Int64(configuration.maxSizeBytes), countStyle: .file))")
                .font(.caption)
                .foregroundColor(.secondary)

            // Source options
            VStack(spacing: 12) {
                if configuration.allowDocuments {
                    SourceOptionButton(
                        icon: "doc.fill",
                        title: "Choose File",
                        subtitle: "Browse documents"
                    ) {
                        showDocumentPicker = true
                    }
                }

                if configuration.allowPhotos && configuration.allowsImages {
                    SourceOptionButton(
                        icon: "photo.on.rectangle",
                        title: "Photo Library",
                        subtitle: "Select from photos"
                    ) {
                        showPhotoPicker = true
                    }
                }

                if configuration.allowCamera && configuration.allowsImages {
                    SourceOptionButton(
                        icon: "camera.fill",
                        title: "Take Photo",
                        subtitle: "Use camera"
                    ) {
                        checkCameraPermission()
                    }
                }
            }
            .padding(.horizontal)

            Spacer()
        }
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPickerRepresentable(
                contentTypes: configuration.documentContentTypes,
                maxSize: configuration.maxSizeBytes
            ) { result in
                handleResult(result)
            }
        }
        .sheet(isPresented: $showPhotoPicker) {
            PhotoPickerRepresentable(
                filter: configuration.photoFilter,
                selectionLimit: configuration.selectionLimit,
                maxSize: configuration.maxSizeBytes
            ) { result in
                handleResult(result)
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPickerRepresentable(maxSize: configuration.maxSizeBytes) { result in
                handleResult(result)
            }
        }
    }

    private func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        showCamera = true
                    } else {
                        errorMessage = "Camera access denied. Please enable in Settings."
                    }
                }
            }
        case .denied, .restricted:
            errorMessage = "Camera access denied. Please enable in Settings."
        @unknown default:
            errorMessage = "Camera not available"
        }
    }

    private func handleResult(_ result: Result<SelectedFile, Error>) {
        switch result {
        case .success(let file):
            onFileSelected(file)
            presentationMode.wrappedValue.dismiss()
        case .failure(let error):
            if case FileUploadError.cancelled = error {
                // User cancelled, don't show error
                return
            }
            errorMessage = error.localizedDescription
            onError(error)
        }
    }
}

// MARK: - Source Option Button

@available(iOS 14.0, *)
private struct SourceOptionButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.accentColor)
                    .frame(width: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Document Picker Representable

@available(iOS 14.0, *)
struct DocumentPickerRepresentable: UIViewControllerRepresentable {
    let contentTypes: [UTType]
    let maxSize: Int
    let completion: (Result<SelectedFile, Error>) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(maxSize: maxSize, completion: completion)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let maxSize: Int
        let completion: (Result<SelectedFile, Error>) -> Void

        init(maxSize: Int, completion: @escaping (Result<SelectedFile, Error>) -> Void) {
            self.maxSize = maxSize
            self.completion = completion
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                completion(.failure(FileUploadError.noData))
                return
            }

            // Start accessing security-scoped resource
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let data = try Data(contentsOf: url)

                // Check file size
                guard data.count <= maxSize else {
                    throw FileUploadError.fileTooLarge(maxSize: maxSize)
                }

                let filename = url.lastPathComponent
                let mimeType = getMimeType(for: url)

                // Generate thumbnail for images
                var thumbnail: UIImage?
                if mimeType.hasPrefix("image/"), let image = UIImage(data: data) {
                    thumbnail = image.preparingThumbnail(of: CGSize(width: 100, height: 100))
                }

                let file = SelectedFile(
                    data: data,
                    filename: filename,
                    mimeType: mimeType,
                    thumbnail: thumbnail
                )

                completion(.success(file))

            } catch {
                completion(.failure(error))
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            completion(.failure(FileUploadError.cancelled))
        }

        private func getMimeType(for url: URL) -> String {
            let ext = url.pathExtension.lowercased()
            if let utType = UTType(filenameExtension: ext), let mimeType = utType.preferredMIMEType {
                return mimeType
            }
            return "application/octet-stream"
        }
    }
}

// MARK: - Photo Picker Representable

@available(iOS 14.0, *)
struct PhotoPickerRepresentable: UIViewControllerRepresentable {
    let filter: PHPickerFilter?
    let selectionLimit: Int
    let maxSize: Int
    let completion: (Result<SelectedFile, Error>) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = selectionLimit
        config.filter = filter ?? .any(of: [.images, .videos])

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(maxSize: maxSize, completion: completion)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let maxSize: Int
        let completion: (Result<SelectedFile, Error>) -> Void

        init(maxSize: Int, completion: @escaping (Result<SelectedFile, Error>) -> Void) {
            self.maxSize = maxSize
            self.completion = completion
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)

            guard let result = results.first else {
                completion(.failure(FileUploadError.cancelled))
                return
            }

            let itemProvider = result.itemProvider

            // Try to load as image first
            if itemProvider.canLoadObject(ofClass: UIImage.self) {
                itemProvider.loadObject(ofClass: UIImage.self) { [weak self] object, error in
                    DispatchQueue.main.async {
                        if let error = error {
                            self?.completion(.failure(error))
                            return
                        }

                        guard let image = object as? UIImage else {
                            self?.completion(.failure(FileUploadError.noData))
                            return
                        }

                        self?.processImage(image, filename: result.itemProvider.suggestedName)
                    }
                }
            }
            // Try to load as video
            else if itemProvider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { [weak self] url, error in
                    DispatchQueue.main.async {
                        if let error = error {
                            self?.completion(.failure(error))
                            return
                        }

                        guard let url = url else {
                            self?.completion(.failure(FileUploadError.noData))
                            return
                        }

                        self?.processVideo(at: url, originalName: result.itemProvider.suggestedName)
                    }
                }
            } else {
                completion(.failure(FileUploadError.uploadFailed(reason: "Unsupported file type")))
            }
        }

        private func processImage(_ image: UIImage, filename: String?) {
            // Convert to JPEG data
            guard let data = image.jpegData(compressionQuality: 0.8) else {
                completion(.failure(FileUploadError.uploadFailed(reason: "Could not process image")))
                return
            }

            // Check size
            guard data.count <= maxSize else {
                // Try with more compression
                if let compressedData = image.jpegData(compressionQuality: 0.5), compressedData.count <= maxSize {
                    createFile(from: compressedData, filename: filename, mimeType: "image/jpeg", thumbnail: image)
                } else {
                    completion(.failure(FileUploadError.fileTooLarge(maxSize: maxSize)))
                }
                return
            }

            createFile(from: data, filename: filename, mimeType: "image/jpeg", thumbnail: image)
        }

        private func processVideo(at url: URL, originalName: String?) {
            do {
                let data = try Data(contentsOf: url)

                guard data.count <= maxSize else {
                    throw FileUploadError.fileTooLarge(maxSize: maxSize)
                }

                let filename = originalName ?? url.lastPathComponent
                let mimeType = "video/mp4"

                // Generate video thumbnail
                let asset = AVAsset(url: url)
                let imageGenerator = AVAssetImageGenerator(asset: asset)
                imageGenerator.appliesPreferredTrackTransform = true

                var thumbnail: UIImage?
                if let cgImage = try? imageGenerator.copyCGImage(at: .zero, actualTime: nil) {
                    thumbnail = UIImage(cgImage: cgImage)
                }

                let file = SelectedFile(data: data, filename: filename, mimeType: mimeType, thumbnail: thumbnail)
                completion(.success(file))

            } catch {
                completion(.failure(error))
            }
        }

        private func createFile(from data: Data, filename: String?, mimeType: String, thumbnail: UIImage?) {
            let finalFilename = filename ?? "image_\(Int(Date().timeIntervalSince1970)).jpg"
            let file = SelectedFile(
                data: data,
                filename: finalFilename,
                mimeType: mimeType,
                thumbnail: thumbnail?.preparingThumbnail(of: CGSize(width: 100, height: 100))
            )
            completion(.success(file))
        }
    }
}

// MARK: - Camera Picker Representable

@available(iOS 14.0, *)
struct CameraPickerRepresentable: UIViewControllerRepresentable {
    let maxSize: Int
    let completion: (Result<SelectedFile, Error>) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(maxSize: maxSize, completion: completion)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let maxSize: Int
        let completion: (Result<SelectedFile, Error>) -> Void

        init(maxSize: Int, completion: @escaping (Result<SelectedFile, Error>) -> Void) {
            self.maxSize = maxSize
            self.completion = completion
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            picker.dismiss(animated: true)

            if let image = info[.originalImage] as? UIImage {
                processImage(image)
            } else if let videoURL = info[.mediaURL] as? URL {
                processVideo(at: videoURL)
            } else {
                completion(.failure(FileUploadError.noData))
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
            completion(.failure(FileUploadError.cancelled))
        }

        private func processImage(_ image: UIImage) {
            guard let data = image.jpegData(compressionQuality: 0.8) else {
                completion(.failure(FileUploadError.uploadFailed(reason: "Could not process image")))
                return
            }

            guard data.count <= maxSize else {
                if let compressedData = image.jpegData(compressionQuality: 0.5), compressedData.count <= maxSize {
                    createImageFile(from: compressedData, thumbnail: image)
                } else {
                    completion(.failure(FileUploadError.fileTooLarge(maxSize: maxSize)))
                }
                return
            }

            createImageFile(from: data, thumbnail: image)
        }

        private func processVideo(at url: URL) {
            do {
                let data = try Data(contentsOf: url)

                guard data.count <= maxSize else {
                    throw FileUploadError.fileTooLarge(maxSize: maxSize)
                }

                let filename = "video_\(Int(Date().timeIntervalSince1970)).mp4"

                // Generate thumbnail
                let asset = AVAsset(url: url)
                let imageGenerator = AVAssetImageGenerator(asset: asset)
                imageGenerator.appliesPreferredTrackTransform = true

                var thumbnail: UIImage?
                if let cgImage = try? imageGenerator.copyCGImage(at: .zero, actualTime: nil) {
                    thumbnail = UIImage(cgImage: cgImage)
                }

                let file = SelectedFile(data: data, filename: filename, mimeType: "video/mp4", thumbnail: thumbnail)
                completion(.success(file))

            } catch {
                completion(.failure(error))
            }
        }

        private func createImageFile(from data: Data, thumbnail: UIImage) {
            let filename = "photo_\(Int(Date().timeIntervalSince1970)).jpg"
            let file = SelectedFile(
                data: data,
                filename: filename,
                mimeType: "image/jpeg",
                thumbnail: thumbnail.preparingThumbnail(of: CGSize(width: 100, height: 100))
            )
            completion(.success(file))
        }
    }
}

// MARK: - Upload Progress View

/// View showing upload progress
@available(iOS 14.0, *)
public struct UploadProgressView: View {
    let progress: UploadProgress?
    let filename: String
    let onCancel: (() -> Void)?

    @State private var isAnimating = false

    public init(progress: UploadProgress?, filename: String, onCancel: (() -> Void)? = nil) {
        self.progress = progress
        self.filename = filename
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "doc.fill")
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(filename)
                        .font(.subheadline)
                        .lineLimit(1)

                    if let progress = progress {
                        Text(progress.formattedProgress)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if let cancel = onCancel {
                    Button(action: cancel) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color(UIColor.systemGray5))
                        .frame(height: 4)
                        .cornerRadius(2)

                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: geometry.size.width * CGFloat(progress?.progress ?? 0), height: 4)
                        .cornerRadius(2)
                        .animation(.easeInOut(duration: 0.2), value: progress?.progress)
                }
            }
            .frame(height: 4)

            if let progress = progress {
                HStack {
                    Text(progress.percentageString)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    if let remaining = progress.estimatedTimeRemaining, remaining > 0 {
                        Text("~\(Int(remaining))s remaining")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - File Preview

/// Small preview for a selected file
@available(iOS 14.0, *)
public struct FilePreviewView: View {
    let file: SelectedFile
    let onRemove: (() -> Void)?

    public init(file: SelectedFile, onRemove: (() -> Void)? = nil) {
        self.file = file
        self.onRemove = onRemove
    }

    public var body: some View {
        HStack(spacing: 12) {
            // Thumbnail or icon
            Group {
                if let thumbnail = file.thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: iconForFile)
                        .font(.title2)
                        .foregroundColor(.accentColor)
                }
            }
            .frame(width: 44, height: 44)
            .background(Color(UIColor.systemGray6))
            .cornerRadius(8)
            .clipped()

            // File info
            VStack(alignment: .leading, spacing: 2) {
                Text(file.filename)
                    .font(.subheadline)
                    .lineLimit(1)

                Text(file.formattedSize)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Remove button
            if let remove = onRemove {
                Button(action: remove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }

    private var iconForFile: String {
        switch file.fileExtension {
        case "pdf": return "doc.fill"
        case "doc", "docx": return "doc.text.fill"
        case "xls", "xlsx": return "tablecells.fill"
        case "ppt", "pptx": return "doc.richtext.fill"
        case "zip", "rar", "7z": return "doc.zipper"
        case "mp3", "wav", "m4a": return "music.note"
        case "mp4", "mov", "avi": return "film.fill"
        default:
            if file.isImage { return "photo.fill" }
            if file.isVideo { return "film.fill" }
            return "doc.fill"
        }
    }
}
