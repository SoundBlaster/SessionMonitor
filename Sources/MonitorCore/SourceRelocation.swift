import Foundation

/// Stored evidence for one physical source. A missing checkpoint cannot authorize relocation.
public struct SourceRelocation: Equatable, Sendable {
    public let source: String
    public let fileIdentity: String
    public let checkpoint: Data?
    public let scopeKey: String
    public let isUnknownAccountScope: Bool

    public init(source: String, fileIdentity: String, checkpoint: Data?, scopeKey: String,
                isUnknownAccountScope: Bool) {
        self.source = source
        self.fileIdentity = fileIdentity
        self.checkpoint = checkpoint
        self.scopeKey = scopeKey
        self.isUnknownAccountScope = isUnknownAccountScope
    }
}
