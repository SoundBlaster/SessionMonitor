import Observation
import os
import XCTest
@testable import SessionMonitor

@MainActor
final class ContextAnatomyInspectionTests: XCTestCase {
    func testHoverWithinOneRequestDoesNotInvalidateObservers() {
        let inspection = ContextAnatomyInspection()
        XCTAssertTrue(inspection.select(x: 3, stepCount: 7_196))
        let changes = OSAllocatedUnfairLock(initialState: 0)
        withObservationTracking {
            _ = inspection.index
        } onChange: {
            changes.withLock { $0 += 1 }
        }
        for coordinate in [2.6, 2.9, 3.0, 3.2, 3.49] {
            XCTAssertFalse(inspection.select(x: coordinate, stepCount: 7_196))
        }
        XCTAssertEqual(inspection.index, 3)
        XCTAssertEqual(changes.withLock { $0 }, 0)
        XCTAssertTrue(inspection.select(x: 3.5, stepCount: 7_196))
        XCTAssertEqual(inspection.index, 4)
        XCTAssertEqual(changes.withLock { $0 }, 1)
    }

    func testExitClearsSelectionOnceAndReentrySelectsTheRequest() {
        let inspection = ContextAnatomyInspection()
        inspection.select(x: 40, stepCount: 100)
        XCTAssertTrue(inspection.select(x: nil, stepCount: 100))
        XCTAssertNil(inspection.index)
        XCTAssertFalse(inspection.select(x: nil, stepCount: 100))
        XCTAssertTrue(inspection.select(x: 41, stepCount: 100))
        XCTAssertEqual(inspection.index, 41)
    }

    func testKeyboardAndHoverShareSelectionAndClampAtEdges() {
        let inspection = ContextAnatomyInspection()
        XCTAssertEqual(inspection.move(by: -1, stepCount: 10), 10)
        inspection.select(x: 3.4, stepCount: 10)
        XCTAssertEqual(inspection.move(by: 1, stepCount: 10), 4)
        XCTAssertEqual(inspection.move(by: -10, stepCount: 10), 1)
        XCTAssertEqual(inspection.move(by: -1, stepCount: 10), 1)
        XCTAssertNil(inspection.move(by: 1, stepCount: 0))
    }

    func testLiveGrowthPreservesSelectionAndShrinkageReconcilesIt() {
        let inspection = ContextAnatomyInspection()
        inspection.reconcile(stepCount: 100)
        XCTAssertNil(inspection.index)
        inspection.select(x: 90, stepCount: 100)
        inspection.reconcile(stepCount: 120)
        XCTAssertEqual(inspection.index, 90)
        inspection.reconcile(stepCount: 20)
        XCTAssertEqual(inspection.index, 20)
        inspection.reconcile(stepCount: 0)
        XCTAssertNil(inspection.index)
    }

    func testInvalidCoordinatesAndEmptyDataClearTheSnapshot() {
        let inspection = ContextAnatomyInspection()
        for coordinate in [Double.nan, .infinity, -.infinity] {
            inspection.select(x: 2, stepCount: 3)
            XCTAssertTrue(inspection.select(x: coordinate, stepCount: 3))
            XCTAssertNil(inspection.index)
        }
        inspection.select(x: 2, stepCount: 3)
        XCTAssertTrue(inspection.select(x: 2, stepCount: 0))
        XCTAssertNil(inspection.index)
    }
}
