import Foundation

/// Non-secret account identity supplied by a rollout format. It is separate from session ownership.
public struct SourceAccountIdentity: Codable, Equatable, Hashable, Sendable {
    public let accountID: String?
    public let userID: String?

    public var deduplicationKey: String? {
        let account = accountID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let user = userID?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard account?.isEmpty == false || user?.isEmpty == false else { return nil }
        return "account:\(account ?? "unknown")\u{1f}user:\(user ?? "unknown")"
    }

    public init(accountID: String?, userID: String?) {
        self.accountID = Self.normalized(accountID)
        self.userID = Self.normalized(userID)
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}

public struct AccountProfile: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let label: String
    public let sourceRoot: String
    public let sourceIdentity: SourceAccountIdentity?
    public let mappingState: AccountProfileMappingState

    public init(id: String, label: String, sourceRoot: String, sourceIdentity: SourceAccountIdentity? = nil,
                mappingState: AccountProfileMappingState = .assigned) {
        self.id = id
        self.label = label
        self.sourceRoot = sourceRoot
        self.sourceIdentity = sourceIdentity
        self.mappingState = mappingState
    }
}

public enum AccountProfileMappingState: String, Codable, Sendable {
    case assigned
    case mixed
}
