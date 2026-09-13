import Foundation
import MonitorCore
import Observation

protocol RequestTimelineSource: Sendable {
    func timeline(sessionID: String, query: UsageQuery) async throws -> RequestTimeline
}

@MainActor
@Observable
final class RequestTimelineModel {
    private(set) var timeline: RequestTimeline?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    func load(sessionID: String, query: UsageQuery, source: any RequestTimelineSource) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let value = try await source.timeline(sessionID: sessionID, query: query)
            guard value.sessionID == sessionID, value.query == query else {
                errorMessage = "Timeline query did not match the selected session."
                return
            }
            timeline = value
        } catch {
            errorMessage = "Could not load request timeline. \(error.localizedDescription)"
        }
    }

    func reset() {
        timeline = nil
        isLoading = false
        errorMessage = nil
    }

    func fail(_ error: Error) {
        isLoading = false
        errorMessage = "Could not load request timeline. \(error.localizedDescription)"
    }
}
