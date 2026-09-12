import Foundation
import MonitorCore

public struct WatchOptions: Sendable {
    public var debounce: Duration
    public var retryDelay: Duration
    public var maximumRetryDelay: Duration

    public init(debounce: Duration = .milliseconds(250), retryDelay: Duration = .seconds(1),
                maximumRetryDelay: Duration = .seconds(30)) {
        self.debounce = debounce
        self.retryDelay = retryDelay
        self.maximumRetryDelay = maximumRetryDelay
    }

    func validate() throws {
        guard debounce > .zero, retryDelay > .zero, maximumRetryDelay >= retryDelay else {
            throw WatchError.invalidTiming
        }
    }
}

public struct WatchStatus: Codable, Sendable {
    public enum Phase: String, Codable, Sendable {
        case importing, watching, paused, recovering, stopped
    }

    public internal(set) var phase: Phase = .stopped
    public internal(set) var completedImports = 0
    public internal(set) var lastImport: ImportSummary?
    public internal(set) var error: String?
}

public enum WatchError: Error, LocalizedError {
    case invalidTiming, directoryRequired

    public var errorDescription: String? {
        switch self {
        case .invalidTiming:
            "Watch delays must be positive, and maximum retry delay must not be smaller than retry delay."
        case .directoryRequired:
            "Watch requires an accessible directory."
        }
    }
}
