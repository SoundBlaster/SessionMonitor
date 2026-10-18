import Observation

/// Pointer inspection changes independently of chart data and its viewport. Only the overlays observe it.
@MainActor
@Observable
final class ContextAnatomyInspection {
    private(set) var index: Int?

    /// Several mouse positions can describe the same request; none of them should redraw the snapshot.
    @discardableResult
    func select(x coordinate: Double?, stepCount: Int) -> Bool {
        update(coordinate.flatMap { ContextAnatomyPresentation.stepIndex(forX: $0, stepCount: stepCount) })
    }

    @discardableResult
    func move(by delta: Int, stepCount: Int) -> Int? {
        let next = ContextAnatomyPresentation.steppedIndex(from: index, by: delta, stepCount: stepCount)
        update(next)
        return next
    }

    /// Follow live data shrinkage without inventing a selection when nothing was inspected.
    func reconcile(stepCount: Int) {
        if let index { update(stepCount > 0 ? min(index, stepCount) : nil) }
    }

    @discardableResult
    private func update(_ next: Int?) -> Bool {
        guard next != index else { return false }
        index = next
        return true
    }
}
