/// A narrow status read. It omits whole-session spans/storage and unrelated provenance.
public struct AgentSessionSnapshot: Equatable, Sendable {
    public let sessionID: String?
    public let summary: SessionSummary?
    public let watermark: QueryWatermark

    public init(sessionID: String?, summary: SessionSummary?, watermark: QueryWatermark) {
        self.sessionID = sessionID
        self.summary = summary
        self.watermark = watermark
    }
}
