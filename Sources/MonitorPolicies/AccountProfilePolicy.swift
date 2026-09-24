import Foundation
import MonitorCore
import SpecificationCore

public struct AccountProfileAssignmentInput: Equatable, Sendable {
    public let profileID: String
    public let label: String
    public let sourceRoot: String

    public init(profileID: String, label: String, sourceRoot: String) {
        self.profileID = profileID
        self.label = label
        self.sourceRoot = sourceRoot
    }
}

public struct AccountProfileAssignmentSpecification: Specification {
    public init() {}

    public func isSatisfiedBy(_ candidate: AccountProfileAssignmentInput) -> Bool {
        let id = candidate.profileID
        let validID = (1...64).contains(id.count)
            && id.first?.isASCII == true
            && id.first?.isLetterOrNumber == true
            && id.allSatisfy { $0.isASCII && ($0.isLetterOrNumber || "-_.".contains($0)) }
        let label = candidate.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let validLabel = !label.isEmpty && label.count <= 64 && !label.unicodeScalars.contains(where: {
            CharacterSet.controlCharacters.contains($0)
        })
        return validID && validLabel && candidate.sourceRoot.hasPrefix("/")
    }
}

public enum AccountProfileAssignmentError: Error, Equatable, Sendable {
    case invalidAssignment
    case mixedSourceIdentities
}

public enum AccountProfileResolution: Equatable, Sendable {
    case assigned(AccountProfile)
    case explicitIdentity(SourceAccountIdentity)
    case unknown
    case mixed
}

/// Keeps source identity evidence separate from the user's profile mapping.
public struct AccountProfilePolicy: Sendable {
    public init() {}

    public func validate(_ assignment: AccountProfileAssignmentInput) throws {
        guard AccountProfileAssignmentSpecification().isSatisfiedBy(assignment) else {
            throw AccountProfileAssignmentError.invalidAssignment
        }
    }

    public func resolve(
        identities: [SourceAccountIdentity], mapping: AccountProfile?
    ) -> AccountProfileResolution {
        let known = Dictionary(identities.compactMap { identity in
            identity.deduplicationKey.map { ($0, identity) }
        }, uniquingKeysWith: { first, _ in first })
        guard known.count <= 1 else { return .mixed }
        if let mapping, let identity = known.values.first {
            return .assigned(AccountProfile(
                id: mapping.id, label: mapping.label, sourceRoot: mapping.sourceRoot, sourceIdentity: identity
            ))
        }
        if let mapping { return .assigned(mapping) }
        if let identity = known.values.first { return .explicitIdentity(identity) }
        return .unknown
    }
}

private extension Character {
    var isASCII: Bool { unicodeScalars.allSatisfy { $0.isASCII } }
    var isLetterOrNumber: Bool { unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) } }
}
