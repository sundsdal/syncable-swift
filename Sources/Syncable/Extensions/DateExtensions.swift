import Foundation

extension Date {
    /// Returns the current date in UTC
    public static var utcNow: Date {
        Date()
    }

    /// ISO8601 string representation for Supabase
    public var iso8601String: String {
        ISO8601DateFormatter().string(from: self)
    }

    /// Parse ISO8601 string from Supabase
    public init?(iso8601String: String) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let date = formatter.date(from: iso8601String) {
            self = date
        } else {
            // Try without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: iso8601String) {
                self = date
            } else {
                return nil
            }
        }
    }
}
