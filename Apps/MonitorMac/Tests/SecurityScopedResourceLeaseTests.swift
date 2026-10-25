import Foundation
import Synchronization
import Testing
@testable import SessionMonitor

struct SecurityScopedResourceLeaseTests {
    @Test(arguments: [false, true], [false, true])
    func balancesImplicitAndExplicitGrants(fromPanel: Bool, acquired: Bool) {
        let counts = Mutex((starts: 0, stops: 0))
        let client = FolderBookmarkClient(create: { _ in Data() }, resolve: { _ in (URL.temporaryDirectory, false) },
                                          startAccess: { _ in counts.withLock { $0.starts += 1 }; return acquired },
                                          stopAccess: { _ in counts.withLock { $0.stops += 1 } })
        do {
            let lease = SecurityScopedResourceLease(.temporaryDirectory, fromPanel: fromPanel, bookmarks: client)
            withExtendedLifetime(lease) {
                #expect(counts.withLock { $0.stops } == 0)
            }
        }
        #expect(counts.withLock { $0.starts } == (fromPanel ? 0 : 1))
        #expect(counts.withLock { $0.stops } == (fromPanel || acquired ? 1 : 0))
    }
}
