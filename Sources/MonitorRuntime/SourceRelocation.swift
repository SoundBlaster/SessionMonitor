import CodexSource
import Foundation
import MonitorCore
import MonitorPolicies
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

extension SessionMonitor {
    func relocationCandidate(path: URL, source: String, checkpoint: Data?) throws -> SourceRelocation? {
        guard checkpoint == nil, let identity = try RolloutDecoder().relocationIdentity(path) else { return nil }
        let candidates = try store.relocationCandidates(fileIdentity: identity)
        guard let previous = candidates.first else { return nil }
        let input = SourceRelocationInput(
            matchingSources: candidates.count,
            previousPathIsMissing: candidates.count == 1 && pathIsMissing(previous.source),
            previousScopeIsUnknown: previous.isUnknownAccountScope,
            hasCheckpoint: previous.checkpoint != nil,
            destinationIsUnmappedAndUnused: try store.relocationDestinationIsAvailable(source: source),
            parentDirectoryChanged: URL(fileURLWithPath: previous.source).deletingLastPathComponent()
                != URL(fileURLWithPath: source).deletingLastPathComponent()
        )
        return SourceRelocationSpecification().isSatisfiedBy(input) ? previous : nil
    }

    private func pathIsMissing(_ path: String) -> Bool {
        var attributes = stat()
        // Permission failures, dangling symlinks and inaccessible volumes are not proof of absence.
        return path.withCString { lstat($0, &attributes) != 0 && errno == ENOENT }
    }
}
