//
//  ValidationUtils.swift
//  Conferbot
//
//  Created by Conferbot SDK
//

import Foundation

// MARK: - Input Validation Types

/// Input validation type enum matching web widget validation logic
public enum InputValidation {
    case email
    case phone
    case url
    case number(min: Double?, max: Double?)
    case date(format: String?)
    case time
    case dateTime
    case custom(pattern: String)
    case none
}

// MARK: - Validation Result

/// Result of a validation operation
public struct ValidationResult {
    public let isValid: Bool
    public let errorMessage: String?

    public init(isValid: Bool, errorMessage: String? = nil) {
        self.isValid = isValid
        self.errorMessage = errorMessage
    }

    /// Convenience for valid result
    public static let valid = ValidationResult(isValid: true, errorMessage: nil)

    /// Convenience for creating invalid result with message
    public static func invalid(_ message: String) -> ValidationResult {
        ValidationResult(isValid: false, errorMessage: message)
    }
}

// MARK: - Validation Error Messages

/// Localization-ready validation error messages
public struct ValidationErrorMessages {
    public static let invalidEmail = "Please enter a valid email address"
    public static let invalidPhone = "Please enter a valid phone number"
    public static let invalidUrl = "Please enter a valid URL"
    public static let invalidNumber = "Please enter a valid number"
    public static let invalidDate = "Please enter a valid date"
    public static let invalidTime = "Please enter a valid time"
    public static let invalidDateTime = "Please enter a valid date and time"
    public static let invalidInput = "Invalid input"

    public static func numberMinimum(_ min: Double) -> String {
        "Number must be at least \(formatNumber(min))"
    }

    public static func numberMaximum(_ max: Double) -> String {
        "Number must be at most \(formatNumber(max))"
    }

    public static func patternMismatch(_ pattern: String) -> String {
        "Input does not match required pattern"
    }

    private static func formatNumber(_ number: Double) -> String {
        if number.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", number)
        }
        return String(number)
    }
}

// MARK: - Validation Utils

/// Validation utilities for user input matching web widget validation logic
public struct ValidationUtils {

    // MARK: - Regex Patterns

    /// RFC 5322 compliant email regex pattern
    private static let emailPattern = "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$"

    /// International phone number pattern
    /// Supports: +, spaces, dashes, parentheses, minimum 10 digits
    private static let phonePattern = "^[\\+]?[(]?[0-9]{1,3}[)]?[-\\s\\.]?[(]?[0-9]{1,3}[)]?[-\\s\\.][0-9]{3,6}[-\\s\\.]?[0-9]{3,6}$"

    /// Time pattern for HH:mm or HH:mm:ss (24-hour format)
    private static let time24Pattern = "^([01]?[0-9]|2[0-3]):[0-5][0-9](:[0-5][0-9])?$"

    /// Time pattern for 12-hour format with AM/PM
    private static let time12Pattern = "^(0?[1-9]|1[0-2]):[0-5][0-9](:[0-5][0-9])?\\s*([AaPp][Mm])$"

    // MARK: - Email Validation

    /// Validates email address using RFC 5322 compliant regex
    /// - Parameter email: The email address to validate
    /// - Returns: True if the email is valid
    public static func isValidEmail(_ email: String) -> Bool {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty else { return false }

        return matchesPattern(trimmedEmail, pattern: emailPattern)
    }

    // MARK: - Phone Validation

    /// Validates phone number supporting international formats
    /// Allows +, spaces, dashes, parentheses with minimum 10 digits
    /// - Parameter phone: The phone number to validate
    /// - Returns: True if the phone number is valid
    public static func isValidPhone(_ phone: String) -> Bool {
        let trimmedPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPhone.isEmpty else { return false }

        // First check if it matches the pattern
        if matchesPattern(trimmedPhone, pattern: phonePattern) {
            return true
        }

        // Alternative: Check if it has at least 10 digits after removing non-digits
        let digitsOnly = trimmedPhone.filter { $0.isNumber }
        return digitsOnly.count >= 10 && digitsOnly.count <= 15
    }

    // MARK: - URL Validation

    /// Validates URL (HTTP/HTTPS)
    /// Also accepts URLs without protocol (adds https://)
    /// - Parameter url: The URL string to validate
    /// - Returns: True if the URL is valid
    public static func isValidUrl(_ url: String) -> Bool {
        let trimmedUrl = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUrl.isEmpty else { return false }

        var urlString = trimmedUrl

        // Add https:// if no protocol specified
        if !urlString.lowercased().hasPrefix("http://") &&
           !urlString.lowercased().hasPrefix("https://") {
            urlString = "https://" + urlString
        }

        // Use URL initializer for validation
        guard let parsedUrl = URL(string: urlString) else { return false }

        // Ensure it has a valid host
        guard let host = parsedUrl.host, !host.isEmpty else { return false }

        // Check for valid scheme
        guard let scheme = parsedUrl.scheme,
              scheme == "http" || scheme == "https" else { return false }

        // Basic domain validation (should have at least one dot for TLD)
        return host.contains(".")
    }

    // MARK: - Number Validation

    /// Validates if string is a valid number with optional min/max bounds
    /// - Parameters:
    ///   - value: The string value to validate
    ///   - min: Optional minimum value (inclusive)
    ///   - max: Optional maximum value (inclusive)
    /// - Returns: True if the value is a valid number within bounds
    public static func isValidNumber(_ value: String, min: Double? = nil, max: Double? = nil) -> Bool {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else { return false }

        // Try to parse as Double
        guard let number = Double(trimmedValue) else { return false }

        // Check minimum bound
        if let minValue = min, number < minValue {
            return false
        }

        // Check maximum bound
        if let maxValue = max, number > maxValue {
            return false
        }

        return true
    }

    // MARK: - Date Validation

    /// Validates date string with optional format
    /// Supports common date formats if no format specified
    /// - Parameters:
    ///   - date: The date string to validate
    ///   - format: Optional date format string (e.g., "yyyy-MM-dd")
    /// - Returns: True if the date is valid
    public static func isValidDate(_ date: String, format: String? = nil) -> Bool {
        let trimmedDate = date.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDate.isEmpty else { return false }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        if let customFormat = format {
            // Use custom format
            formatter.dateFormat = customFormat
            return formatter.date(from: trimmedDate) != nil
        }

        // Try common date formats
        let commonFormats = [
            "yyyy-MM-dd",
            "MM/dd/yyyy",
            "dd/MM/yyyy",
            "MM-dd-yyyy",
            "dd-MM-yyyy",
            "yyyy/MM/dd",
            "MMMM d, yyyy",
            "MMM d, yyyy",
            "d MMMM yyyy",
            "d MMM yyyy"
        ]

        for dateFormat in commonFormats {
            formatter.dateFormat = dateFormat
            if formatter.date(from: trimmedDate) != nil {
                return true
            }
        }

        return false
    }

    // MARK: - Time Validation

    /// Validates time string
    /// Supports HH:mm, HH:mm:ss (24-hour) and 12-hour with AM/PM
    /// - Parameter time: The time string to validate
    /// - Returns: True if the time is valid
    public static func isValidTime(_ time: String) -> Bool {
        let trimmedTime = time.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTime.isEmpty else { return false }

        // Check 24-hour format (HH:mm or HH:mm:ss)
        if matchesPattern(trimmedTime, pattern: time24Pattern) {
            return true
        }

        // Check 12-hour format with AM/PM
        if matchesPattern(trimmedTime, pattern: time12Pattern) {
            return true
        }

        // Try parsing with DateFormatter as fallback
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        let timeFormats = [
            "HH:mm",
            "HH:mm:ss",
            "h:mm a",
            "h:mm:ss a",
            "hh:mm a",
            "hh:mm:ss a"
        ]

        for timeFormat in timeFormats {
            formatter.dateFormat = timeFormat
            if formatter.date(from: trimmedTime) != nil {
                return true
            }
        }

        return false
    }

    // MARK: - DateTime Validation

    /// Validates datetime string
    /// Supports ISO 8601 and common datetime formats
    /// - Parameter dateTime: The datetime string to validate
    /// - Returns: True if the datetime is valid
    public static func isValidDateTime(_ dateTime: String) -> Bool {
        let trimmedDateTime = dateTime.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDateTime.isEmpty else { return false }

        // Try ISO 8601 first
        let iso8601Formatter = ISO8601DateFormatter()
        iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if iso8601Formatter.date(from: trimmedDateTime) != nil {
            return true
        }

        // Try without fractional seconds
        iso8601Formatter.formatOptions = [.withInternetDateTime]
        if iso8601Formatter.date(from: trimmedDateTime) != nil {
            return true
        }

        // Try common datetime formats
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        let dateTimeFormats = [
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "MM/dd/yyyy HH:mm:ss",
            "MM/dd/yyyy HH:mm",
            "dd/MM/yyyy HH:mm:ss",
            "dd/MM/yyyy HH:mm",
            "yyyy/MM/dd HH:mm:ss",
            "yyyy/MM/dd HH:mm",
            "MMMM d, yyyy h:mm a",
            "MMM d, yyyy h:mm a",
            "MMMM d, yyyy HH:mm",
            "MMM d, yyyy HH:mm"
        ]

        for dateTimeFormat in dateTimeFormats {
            formatter.dateFormat = dateTimeFormat
            if formatter.date(from: trimmedDateTime) != nil {
                return true
            }
        }

        return false
    }

    // MARK: - Custom Pattern Validation

    /// Validates string against a custom regex pattern
    /// - Parameters:
    ///   - value: The string value to validate
    ///   - pattern: The regex pattern to match
    /// - Returns: True if the value matches the pattern
    public static func isValidCustomPattern(_ value: String, pattern: String) -> Bool {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else { return false }

        return matchesPattern(trimmedValue, pattern: pattern)
    }

    // MARK: - Central Validation Method

    /// Central validation method that validates input based on type
    /// - Parameters:
    ///   - value: The string value to validate
    ///   - type: The type of validation to perform
    /// - Returns: ValidationResult with isValid and optional errorMessage
    public static func validate(_ value: String, type: InputValidation) -> ValidationResult {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)

        // Empty check for all types except .none
        if case .none = type {
            return .valid
        }

        switch type {
        case .email:
            if isValidEmail(trimmedValue) {
                return .valid
            }
            return .invalid(ValidationErrorMessages.invalidEmail)

        case .phone:
            if isValidPhone(trimmedValue) {
                return .valid
            }
            return .invalid(ValidationErrorMessages.invalidPhone)

        case .url:
            if isValidUrl(trimmedValue) {
                return .valid
            }
            return .invalid(ValidationErrorMessages.invalidUrl)

        case .number(let min, let max):
            // First check if it's a valid number
            guard let number = Double(trimmedValue) else {
                return .invalid(ValidationErrorMessages.invalidNumber)
            }

            // Check minimum bound
            if let minValue = min, number < minValue {
                return .invalid(ValidationErrorMessages.numberMinimum(minValue))
            }

            // Check maximum bound
            if let maxValue = max, number > maxValue {
                return .invalid(ValidationErrorMessages.numberMaximum(maxValue))
            }

            return .valid

        case .date(let format):
            if isValidDate(trimmedValue, format: format) {
                return .valid
            }
            return .invalid(ValidationErrorMessages.invalidDate)

        case .time:
            if isValidTime(trimmedValue) {
                return .valid
            }
            return .invalid(ValidationErrorMessages.invalidTime)

        case .dateTime:
            if isValidDateTime(trimmedValue) {
                return .valid
            }
            return .invalid(ValidationErrorMessages.invalidDateTime)

        case .custom(let pattern):
            if isValidCustomPattern(trimmedValue, pattern: pattern) {
                return .valid
            }
            return .invalid(ValidationErrorMessages.patternMismatch(pattern))

        case .none:
            return .valid
        }
    }

    // MARK: - Helper Methods

    /// Checks if a string matches a regex pattern
    /// - Parameters:
    ///   - string: The string to check
    ///   - pattern: The regex pattern to match
    /// - Returns: True if the string matches the pattern
    private static func matchesPattern(_ string: String, pattern: String) -> Bool {
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let range = NSRange(string.startIndex..., in: string)
            return regex.firstMatch(in: string, options: [], range: range) != nil
        } catch {
            debugPrint("[ValidationUtils] Invalid regex pattern: \(pattern), error: \(error)")
            return false
        }
    }

    /// Debug print helper
    private static func debugPrint(_ message: String) {
        #if DEBUG
        print(message)
        #endif
    }
}

// MARK: - InputValidation Equatable Conformance

extension InputValidation: Equatable {
    public static func == (lhs: InputValidation, rhs: InputValidation) -> Bool {
        switch (lhs, rhs) {
        case (.email, .email):
            return true
        case (.phone, .phone):
            return true
        case (.url, .url):
            return true
        case (.number(let lMin, let lMax), .number(let rMin, let rMax)):
            return lMin == rMin && lMax == rMax
        case (.date(let lFormat), .date(let rFormat)):
            return lFormat == rFormat
        case (.time, .time):
            return true
        case (.dateTime, .dateTime):
            return true
        case (.custom(let lPattern), .custom(let rPattern)):
            return lPattern == rPattern
        case (.none, .none):
            return true
        default:
            return false
        }
    }
}

// MARK: - ValidationResult Equatable Conformance

extension ValidationResult: Equatable {
    public static func == (lhs: ValidationResult, rhs: ValidationResult) -> Bool {
        return lhs.isValid == rhs.isValid && lhs.errorMessage == rhs.errorMessage
    }
}
