// GLPIKiosk — DebugLogger.swift

import Foundation
import OSLog

struct DebugLogEntry: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let level: String
    let category: String
    let message: String
    let duration: TimeInterval?

    var formattedTime: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss.SSS"
        return fmt.string(from: timestamp)
    }

    var isError: Bool {
        if level.uppercased() == "ERR" {
            return true
        }
        let lower = message.lowercased()
        return lower.contains("erreur")
            || lower.contains("error")
            || lower.contains("exception")
            || lower.contains("not found")
            || lower.contains("401")
            || lower.contains("403")
            || lower.contains("404")
            || lower.contains("500")
    }
}

final class DebugLogStore: ObservableObject {
    @Published var isEnabled: Bool = false
    @Published var entries: [DebugLogEntry] = []

    private let maxEntries = 2000

    func append(level: String, category: String, message: String, duration: TimeInterval? = nil) {
        let entry = DebugLogEntry(
            timestamp: Date(),
            level: level,
            category: category,
            message: message,
            duration: duration
        )
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    func clear() {
        entries.removeAll()
    }
}

enum DebugLogger {
    private static let logger = Logger(subsystem: "fr.jcd.glpikiosk", category: "network")
    static let shared = DebugLogStore()

    /// Active / desactive le mode debug (modifiable depuis les reglages admin).
    static var isEnabled: Bool {
        get { shared.isEnabled }
        set { shared.isEnabled = newValue }
    }

    // MARK: Generic API (backward compatible)

    static func log(_ message: String) {
        logger.debug("\(message, privacy: .public)")
        guard isEnabled else { return }
        append(level: "LOG", category: inferCategory(from: message), message: message, duration: nil)
    }

    static func warn(_ message: String) {
        logger.warning("\(message, privacy: .public)")
        guard isEnabled else { return }
        append(level: "WARN", category: inferCategory(from: message), message: message, duration: nil)
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        guard isEnabled else { return }
        append(level: "ERR", category: inferCategory(from: message), message: message, duration: nil)
    }

    // MARK: Category-aware API (aligned with APPAPPLE)

    static func log(_ category: String, _ message: String, duration: TimeInterval? = nil) {
        logger.debug("\(message, privacy: .public)")
        guard isEnabled else { return }
        append(level: "LOG", category: normalizeCategory(category, fallbackMessage: message), message: message, duration: duration)
    }

    static func warn(_ category: String, _ message: String, duration: TimeInterval? = nil) {
        logger.warning("\(message, privacy: .public)")
        guard isEnabled else { return }
        append(level: "WARN", category: normalizeCategory(category, fallbackMessage: message), message: message, duration: duration)
    }

    static func error(_ category: String, _ message: String, duration: TimeInterval? = nil) {
        logger.error("\(message, privacy: .public)")
        guard isEnabled else { return }
        append(level: "ERR", category: normalizeCategory(category, fallbackMessage: message), message: message, duration: duration)
    }

    private static func append(level: String, category: String, message: String, duration: TimeInterval?) {
        Task { @MainActor in
            shared.append(level: level, category: category, message: message, duration: duration)
        }
    }

    private static func normalizeCategory(_ raw: String, fallbackMessage: String) -> String {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty {
            return inferCategory(from: fallbackMessage)
        }
        return clean
    }

    private static func inferCategory(from message: String) -> String {
        let lower = message.lowercased()
        if lower.contains("http") || lower.hasPrefix("[get]") || lower.hasPrefix("[post]") || lower.hasPrefix("[put]") || lower.hasPrefix("[patch]") || lower.hasPrefix("[delete]") {
            return "HTTP"
        }
        if lower.contains("planning") || lower.contains("poll") || lower.contains("checkin") || lower.contains("refresh") {
            return "Planning"
        }
        if lower.contains("bl") || lower.contains("view_pdf") || lower.contains("ticket_bls") {
            return "BL"
        }
        return "General"
    }
}
