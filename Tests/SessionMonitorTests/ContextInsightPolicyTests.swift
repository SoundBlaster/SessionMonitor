import Foundation
import MonitorCore
import MonitorPolicies
import Testing

struct ContextInsightPolicyTests {
    private func request(_ id: String, input: Int64? = 20_000, cached: Int64? = 18_000,
                         at time: Double = 0, model: String? = "m", window: Int64? = 100_000,
                         output: Int64? = 100) -> RequestTimelinePoint {
        RequestTimelinePoint(id: id, sessionID: "S", timestamp: Date(timeIntervalSince1970: time),
                             kind: .usageRequest, inputTokens: input, cachedInputTokens: cached,
                             outputTokens: output, model: model, contextWindowTokens: window)
    }

    private func report(_ points: [RequestTimelinePoint], query: UsageQuery? = nil,
                        configuration: ContextInsightConfiguration = .init()) throws -> ContextInsightReport {
        ContextInsightPolicy.evaluate(RequestTimeline(sessionID: "S", query: try query ?? UsageQuery(),
                                                     points: points), configuration: configuration)
    }

    @Test func growthAndDropAreBothRetainedAcrossRecovery() throws {
        let value = try report([request("a"), request("b", input: 50_000, at: 1),
                                request("c", input: 20_000, at: 2), request("d", input: 60_000, at: 3)])
        #expect(value.insights.filter { $0.kind == .contextGrowth }.map(\.requestID) == ["b", "d"])
        let drop = try #require(value.insights.first { $0.kind == .contextDrop })
        #expect(drop.requestID == "c")
        #expect(drop.explanation.contains("reset is not proven"))
    }

    @Test func significanceRequiresBothAbsoluteAndRelativeThresholds() throws {
        let small = try report([request("a", input: 1_000), request("b", input: 2_000, at: 1)])
        #expect(!small.insights.contains { $0.kind == .contextGrowth })
        let tinyShare = try report([request("a", input: 1_000_000), request("b", input: 1_010_000, at: 1)])
        #expect(!tinyShare.insights.contains { $0.kind == .contextGrowth })
        let boundary = try report([request("a", input: 32_000), request("b", input: 40_000, at: 1)])
        #expect(boundary.insights.contains { $0.kind == .contextGrowth })
    }

    @Test func compactionIsIndependentOfDropAndSurvivesUnknownInput() throws {
        let event = RequestTimelinePoint(id: "event", sessionID: "S", timestamp: Date(timeIntervalSince1970: 1),
                                         kind: .compaction)
        let value = try report([request("a", input: 90_000), event, request("b", input: 20_000, at: 2)])
        #expect(Set(value.insights.map(\.kind)).isSuperset(of: [.compaction, .contextDrop]))
        let gap = try report([request("a"), event, request("unknown", input: nil, at: 2),
                              request("b", input: 90_000, at: 3)])
        #expect(gap.insights.contains { $0.kind == .compaction })
        #expect(!gap.insights.contains { $0.kind == .contextGrowth })
        #expect(gap.limitations.contains { $0.contains("never bridge") })
        #expect(gap.phases.count == 2)
    }

    @Test func modelChangesMissingModelsAndReversedTimeDoNotCompare() throws {
        let models: [String?] = [nil, "", "different"]
        for model in models {
            let value = try report([request("a"), request("b", input: 90_000, cached: 0, at: 600, model: model)])
            let pairKinds: [ContextInsightKind] = [.contextGrowth, .cacheDropAfterPause, .criticalEntry]
            #expect(!value.insights.contains { pairKinds.contains($0.kind) })
        }
        let reversed = try report([request("a", at: 600), request("b", input: 90_000, cached: 0, at: 0)])
        #expect(reversed.insights.isEmpty)
    }

    @Test func cacheDropAfterPauseIsAHypothesisWithExactObservedEvidence() throws {
        let value = try report([request("a"), request("b", cached: 2_000, at: 300)])
        let finding = try #require(value.insights.first { $0.kind == .cacheDropAfterPause })
        #expect(finding.isHypothesis)
        #expect(finding.explanation.contains("cannot establish cache expiry"))
        #expect(!finding.evidence.inference.isEmpty)
        #expect(finding.evidence.observed.contains { $0.detail.contains("300.0 seconds") })
        #expect(value.insightsByRequest[2]?.contains(finding) == true)
    }

    @Test func cacheRulesRejectUnknownInvalidCountersSmallInputAndMissingRequests() throws {
        let cases: [[RequestTimelinePoint]] = [
            [request("a"), request("b", cached: nil, at: 600)],
            [request("a", cached: 30_000), request("b", cached: 0, at: 600)],
            [request("a"), request("b", cached: -1, at: 600)],
            [request("a", input: 100, cached: 90), request("b", input: 100, cached: 0, at: 600)],
            [request("a"), request("missing", input: nil, at: 100), request("b", cached: 0, at: 600)],
            [request("a"), request("b", cached: 0, at: 299)]
        ]
        for points in cases {
            #expect(try !report(points).insights.contains { $0.kind == .cacheDropAfterPause })
        }
    }

    @Test func coldStartNamesOnlyFirstObservedRequestAndDoesNotInventSessionStart() throws {
        let query = try UsageQuery(since: Date(timeIntervalSince1970: 10))
        let value = try report([request("a", cached: 0, at: 10), request("b", cached: 0, at: 20)], query: query)
        let cold = try #require(value.insights.first { $0.kind == .coldStart })
        #expect(cold.requestID == "a")
        #expect(cold.isHypothesis)
        #expect(cold.explanation.contains("outside this query"))
        #expect(value.insights.filter { $0.kind == .coldStart }.count == 1)
        let missing = try report([request("unknown", input: nil), request("b", cached: 0, at: 1)])
        #expect(!missing.insights.contains { $0.kind == .coldStart })
    }

    @Test func criticalEntryRequiresExplicitEqualWindowsAndCrossing() throws {
        let value = try report([request("a", input: 89_999), request("b", input: 90_000, at: 1),
                                request("c", input: 95_000, at: 2)])
        #expect(value.insights.filter { $0.kind == .criticalEntry }.map(\.requestID) == ["b"])
        let windows: [Int64?] = [nil, 99_000]
        for window in windows {
            let changed = try report([request("a", input: 80_000), request("b", input: 95_000, at: 1, window: window)])
            #expect(!changed.insights.contains { $0.kind == .criticalEntry })
        }
        let peak = try report([request("a", window: nil), request("b", input: 90_000, at: 1, window: nil)])
        #expect(!peak.insights.contains { $0.kind == .criticalEntry })
        #expect(peak.limitations.contains { $0.contains("session peak") })
    }

    @Test func phasesPreserveCountsUnknownOutputAndZeroInput() throws {
        let value = try report([request("a", input: 0, cached: 0), request("b", input: 20_000, at: 1, output: nil),
                                request("c", input: 60_000, at: 2), request("d", input: 40_000, at: 3)])
        #expect(value.phases.map(\.zone) == [.low, .moderate, .low])
        #expect(value.phases.map(\.requests) == [2, 1, 1])
        #expect(value.phases[0].inputTokens == 20_000)
        #expect(value.phases[0].outputTokens == nil)
        #expect(value.phases.reduce(0) { $0 + $1.requests } == value.anatomy.steps.count)
    }

    @Test func phaseSumsDoNotWrapOnOverflow() throws {
        // Zero outputs avoid overflowing the anatomy builder's unrelated cumulative sum.
        let value = try report([request("a", input: Int64.max, cached: nil, window: Int64.max, output: nil),
                                request("b", input: Int64.max, cached: nil, at: 1, window: Int64.max, output: nil)])
        #expect(value.phases[0].inputTokens == nil)
    }

    @Test func phaseBreaksOnModelAndWindowChangesEvenWithinSameZone() throws {
        let value = try report([request("a"), request("b", at: 1, model: "other"),
                                request("c", at: 2, model: "other", window: 200_000)])
        #expect(value.phases.count == 3)
    }

    @Test func emptyForeignSessionAndTrailingCompactionAreExplicit() throws {
        #expect(try report([]).insights.isEmpty)
        let foreign = RequestTimelinePoint(id: "foreign", sessionID: "other", timestamp: .distantPast,
                                           kind: .usageRequest, inputTokens: 100_000)
        let event = RequestTimelinePoint(id: "event", sessionID: "S", timestamp: Date(timeIntervalSince1970: 1),
                                         kind: .compaction)
        let value = try report([request("a"), foreign, event])
        #expect(value.anatomy.steps.count == 1)
        #expect(value.limitations.contains { $0.contains("trailing compaction") })
    }

    @Test func IDsAreStableAndSignalsNeverRewriteSourcePoints() throws {
        let points = [request("a"), request("b", input: 90_000, cached: 0, at: 600)]
        let first = try report(points)
        #expect(first == (try report(points)))
        #expect(Set(first.insights.map(\.id)).count == first.insights.count)
        #expect(first.anatomy.steps.map(\.contextTokens) == [20_000, 90_000])
        #expect(first.anatomy.steps.map(\.outputTokens) == [100, 100])
    }

    @Test func pairEvidenceRetainsBothResponseIDsAndRequestLines() throws {
        let points = [
            RequestTimelinePoint(id: "a", sessionID: "S", timestamp: Date(timeIntervalSince1970: 0),
                                 kind: .usageRequest, sourceLine: 4, responseID: "response-a", inputTokens: 20_000,
                                 cachedInputTokens: 18_000, model: "m", contextWindowTokens: 100_000),
            RequestTimelinePoint(id: "b", sessionID: "S", timestamp: Date(timeIntervalSince1970: 600),
                                 kind: .usageRequest, sourceLine: 10, responseID: "response-b", inputTokens: 95_000,
                                 cachedInputTokens: 0, model: "m", contextWindowTokens: 100_000)
        ]
        let value = try report(points)
        for kind in [ContextInsightKind.contextGrowth, .cacheDropAfterPause, .criticalEntry] {
            let finding = try #require(value.insights.first { $0.kind == kind })
            let current = try #require(finding.evidence.observed.first)
            #expect(current.responseIDs == ["response-b"])
            #expect(current.sourceLines == [10])
            let comparison = try #require(finding.evidence.observed.first { $0.detail.contains("Previous input") })
            #expect(comparison.responseIDs == ["response-a", "response-b"])
            #expect(comparison.sourceLines == [4, 10])
            #expect(finding.evidence.observed.allSatisfy { $0.sessionIDs == ["S"] })
            if finding.isHypothesis {
                #expect(finding.evidence.inference.first?.responseIDs == ["response-a", "response-b"])
            }
            let decoded = try JSONDecoder().decode(ContextInsight.self, from: JSONEncoder().encode(finding))
            #expect(decoded == finding)
        }
    }

    @Test func compactionEvidenceRetainsEachSourceLineAcrossUnknownInputWithoutForeignOrTrailingEvents() throws {
        func compaction(_ id: String, line: Int, session: String = "S") -> RequestTimelinePoint {
            RequestTimelinePoint(id: id, sessionID: session, timestamp: Date(timeIntervalSince1970: Double(line)),
                                 kind: .compaction, sourceLine: line)
        }
        let value = try report([
            request("a", input: 90_000), compaction("one", line: 10), request("unknown", input: nil, at: 20),
            compaction("foreign", line: 99, session: "other"), compaction("two", line: 30),
            request("b", input: 20_000, at: 40), compaction("trailing", line: 50)
        ])
        let finding = try #require(value.insights.first { $0.kind == .compaction })
        let events = finding.evidence.observed.filter { $0.detail.hasPrefix("Explicit compaction ") }
        #expect(events.count == 2)
        #expect(events.map(\.sourceLines) == [[10], [30]])
        #expect(Set(events.map(\.detail)).count == events.count)
        #expect(events.allSatisfy { $0.responseIDs.isEmpty && $0.sessionIDs == ["S"] })
        #expect(!finding.evidence.observed.flatMap(\.sourceLines).contains(99))
        #expect(!finding.evidence.observed.flatMap(\.sourceLines).contains(50))
        #expect(finding.requestID == "b")
        #expect(value.anatomy.steps.last?.activityBefore.compactions == 2)
    }

    @Test func missingProvenanceDoesNotInventResponseIDsOrSourceLines() throws {
        let value = try report([request("a", cached: 0), request("b", input: 90_000, at: 1)])
        #expect(!value.insights.isEmpty)
        #expect(value.insights.flatMap { $0.evidence.observed + $0.evidence.inference }.allSatisfy {
            $0.responseIDs.isEmpty && $0.sourceLines.isEmpty
        })
    }

    @Test func configurationSanitizesNonfiniteAndOutOfRangeValues() {
        let value = ContextInsightConfiguration(minimumChangeTokens: -1, minimumChangeFraction: .nan,
                                               minimumCacheInput: 0, cacheDropFraction: -1,
                                               coldCacheFraction: .infinity, pauseSeconds: .nan)
        #expect(value.minimumChangeTokens == 1)
        #expect(value.minimumChangeFraction == 0.25)
        #expect(value.minimumCacheInput == 1)
        #expect(value.cacheDropFraction > 0)
        #expect(value.coldCacheFraction == 0.1)
        #expect(value.pauseSeconds == 300)
    }
}
