import SpecificationCore

public struct SourceRelocationInput: Sendable {
    public let matchingSources: Int
    public let previousPathIsMissing: Bool
    public let previousScopeIsUnknown: Bool
    public let hasCheckpoint: Bool
    public let destinationIsUnmappedAndUnused: Bool
    public let parentDirectoryChanged: Bool

    public init(matchingSources: Int, previousPathIsMissing: Bool, previousScopeIsUnknown: Bool,
                hasCheckpoint: Bool, destinationIsUnmappedAndUnused: Bool, parentDirectoryChanged: Bool) {
        self.matchingSources = matchingSources
        self.previousPathIsMissing = previousPathIsMissing
        self.previousScopeIsUnknown = previousScopeIsUnknown
        self.hasCheckpoint = hasCheckpoint
        self.destinationIsUnmappedAndUnused = destinationIsUnmappedAndUnused
        self.parentDirectoryChanged = parentDirectoryChanged
    }
}

/// Unknown attribution may follow a uniquely identified, displaced file, never a copy or another account.
public struct SourceRelocationSpecification: Specification {
    public init() {}

    public func isSatisfiedBy(_ candidate: SourceRelocationInput) -> Bool {
        candidate.matchingSources == 1 && candidate.previousPathIsMissing
            && candidate.previousScopeIsUnknown && candidate.hasCheckpoint
            && candidate.destinationIsUnmappedAndUnused && candidate.parentDirectoryChanged
    }
}
