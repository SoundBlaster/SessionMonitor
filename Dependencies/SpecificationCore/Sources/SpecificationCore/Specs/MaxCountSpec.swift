//
//  MaxCountSpec.swift
//  SpecificationCore
//
//  Created by SpecificationCore on 2025.
//

import Foundation

/// A specification that checks if a counter is below a maximum threshold.
/// This is useful for implementing limits on actions, display counts, or usage restrictions.
public struct MaxCountSpec: Specification {
    public typealias T = EvaluationContext

    /// The key identifying the counter in the context
    public let counterKey: String

    /// The maximum allowed value for the counter (exclusive)
    public let maximumCount: Int

    /// Creates a new MaxCountSpec
    /// - Parameters:
    ///   - counterKey: The key identifying the counter in the evaluation context
    ///   - maximumCount: The maximum allowed value (counter must be less than this)
    public init(counterKey: String, maximumCount: Int) {
        self.counterKey = counterKey
        self.maximumCount = maximumCount
    }

    /// Creates a new MaxCountSpec with a limit parameter for clarity
    /// - Parameters:
    ///   - counterKey: The key identifying the counter in the evaluation context
    ///   - limit: The maximum allowed value (counter must be less than this)
    public init(counterKey: String, limit: Int) {
        self.init(counterKey: counterKey, maximumCount: limit)
    }

    public func isSatisfiedBy(_ context: EvaluationContext) -> Bool {
        let currentCount = context.counter(for: counterKey)
        return currentCount < maximumCount
    }
}

// MARK: - Convenience Extensions

public extension MaxCountSpec {
    /// Creates a specification that checks if a counter hasn't exceeded a limit
    /// - Parameters:
    ///   - counterKey: The counter key to check
    ///   - limit: The maximum allowed count
    /// - Returns: A MaxCountSpec with the specified parameters
    static func counter(_ counterKey: String, limit: Int) -> MaxCountSpec {
        MaxCountSpec(counterKey: counterKey, limit: limit)
    }

    /// Creates a specification for single-use actions (limit of 1)
    /// - Parameter counterKey: The counter key to check
    /// - Returns: A MaxCountSpec that allows only one occurrence
    static func onlyOnce(_ counterKey: String) -> MaxCountSpec {
        MaxCountSpec(counterKey: counterKey, limit: 1)
    }

    /// Creates a specification for actions that can happen twice
    /// - Parameter counterKey: The counter key to check
    /// - Returns: A MaxCountSpec that allows up to two occurrences
    static func onlyTwice(_ counterKey: String) -> MaxCountSpec {
        MaxCountSpec(counterKey: counterKey, limit: 2)
    }

    /// Creates a specification for daily limits (assuming counter tracks daily occurrences)
    /// - Parameters:
    ///   - counterKey: The counter key to check
    ///   - limit: The maximum number of times per day
    /// - Returns: A MaxCountSpec with the daily limit
    static func dailyLimit(_ counterKey: String, limit: Int) -> MaxCountSpec {
        MaxCountSpec(counterKey: counterKey, limit: limit)
    }

    /// Creates a specification for weekly limits (assuming counter tracks weekly occurrences)
    /// - Parameters:
    ///   - counterKey: The counter key to check
    ///   - limit: The maximum number of times per week
    /// - Returns: A MaxCountSpec with the weekly limit
    static func weeklyLimit(_ counterKey: String, limit: Int) -> MaxCountSpec {
        MaxCountSpec(counterKey: counterKey, limit: limit)
    }

    /// Creates a specification for monthly limits (assuming counter tracks monthly occurrences)
    /// - Parameters:
    ///   - counterKey: The counter key to check
    ///   - limit: The maximum number of times per month
    /// - Returns: A MaxCountSpec with the monthly limit
    static func monthlyLimit(_ counterKey: String, limit: Int) -> MaxCountSpec {
        MaxCountSpec(counterKey: counterKey, limit: limit)
    }
}

// MARK: - Inclusive/Exclusive Variants

public extension MaxCountSpec {
    /// Creates a specification that checks if a counter is less than or equal to a maximum
    /// - Parameters:
    ///   - counterKey: The key identifying the counter in the evaluation context
    ///   - maximumCount: The maximum allowed value (inclusive)
    /// - Returns: An AnySpecification that allows values up to and including the maximum
    static func inclusive(counterKey: String, maximumCount: Int) -> AnySpecification<
        EvaluationContext
    > {
        AnySpecification { context in
            let currentCount = context.counter(for: counterKey)
            return currentCount <= maximumCount
        }
    }

    /// Creates a specification that checks if a counter is exactly equal to a value
    /// - Parameters:
    ///   - counterKey: The key identifying the counter in the evaluation context
    ///   - count: The exact value the counter must equal
    /// - Returns: An AnySpecification that is satisfied only when the counter equals the exact value
    static func exactly(counterKey: String, count: Int) -> AnySpecification<
        EvaluationContext
    > {
        AnySpecification { context in
            let currentCount = context.counter(for: counterKey)
            return currentCount == count
        }
    }

    /// Creates a specification that checks if a counter is within a range
    /// - Parameters:
    ///   - counterKey: The key identifying the counter in the evaluation context
    ///   - range: The allowed range of values (inclusive)
    /// - Returns: An AnySpecification that is satisfied when the counter is within the range
    static func inRange(counterKey: String, range: ClosedRange<Int>) -> AnySpecification<
        EvaluationContext
    > {
        AnySpecification { context in
            let currentCount = context.counter(for: counterKey)
            return range.contains(currentCount)
        }
    }
}

// MARK: - Combinable Specifications

public extension MaxCountSpec {
    /// Combines this MaxCountSpec with another counter specification using AND logic
    /// - Parameter other: Another MaxCountSpec to combine with
    /// - Returns: An AndSpecification that requires both counter conditions to be met
    func and(_ other: MaxCountSpec) -> AndSpecification<MaxCountSpec, MaxCountSpec> {
        AndSpecification(left: self, right: other)
    }

    /// Combines this MaxCountSpec with another counter specification using OR logic
    /// - Parameter other: Another MaxCountSpec to combine with
    /// - Returns: An OrSpecification that requires either counter condition to be met
    func or(_ other: MaxCountSpec) -> OrSpecification<MaxCountSpec, MaxCountSpec> {
        OrSpecification(left: self, right: other)
    }
}
