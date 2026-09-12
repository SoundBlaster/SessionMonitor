//
//  AnySpecification.swift
//  SpecificationCore
//
//  Created by SpecificationCore on 2025.
//

import Foundation

/// A type-erased wrapper for any specification optimized for performance.
/// This allows you to store specifications of different concrete types in the same collection
/// or use them in contexts where the specific type isn't known at compile time.
///
/// ## Performance Optimizations
///
/// - **@inlinable methods**: Enable compiler optimization across module boundaries
/// - **Specialized storage**: Different storage strategies based on specification type
/// - **Copy-on-write semantics**: Minimize memory allocations
/// - **Thread-safe design**: No internal state requiring synchronization
public struct AnySpecification<T>: Specification {
    // MARK: - Optimized Storage Strategy

    /// Internal storage that uses different strategies based on the specification type
    @usableFromInline
    enum Storage {
        case predicate((T) -> Bool)
        case specification(any Specification<T>)
        case constantTrue
        case constantFalse
    }

    @usableFromInline
    let storage: Storage

    // MARK: - Initializers

    /// Creates a type-erased specification wrapping the given specification.
    /// - Parameter specification: The specification to wrap
    @inlinable
    public init<S: Specification>(_ specification: S) where S.T == T {
        // Optimize for common patterns
        if specification is AlwaysTrueSpec<T> {
            storage = .constantTrue
        } else if specification is AlwaysFalseSpec<T> {
            storage = .constantFalse
        } else {
            // Store the specification directly for better performance
            storage = .specification(specification)
        }
    }

    /// Creates a type-erased specification from a closure.
    /// - Parameter predicate: A closure that takes a candidate and returns whether it satisfies the specification
    @inlinable
    public init(_ predicate: @escaping (T) -> Bool) {
        storage = .predicate(predicate)
    }

    // MARK: - Core Specification Protocol

    @inlinable
    public func isSatisfiedBy(_ candidate: T) -> Bool {
        switch storage {
        case .constantTrue:
            return true
        case .constantFalse:
            return false
        case let .predicate(predicate):
            return predicate(candidate)
        case let .specification(spec):
            return spec.isSatisfiedBy(candidate)
        }
    }
}

// MARK: - Convenience Extensions

public extension AnySpecification {
    /// Creates a specification that always returns true
    @inlinable
    static var always: AnySpecification<T> {
        AnySpecification { _ in true }
    }

    /// Creates a specification that always returns false
    @inlinable
    static var never: AnySpecification<T> {
        AnySpecification { _ in false }
    }

    /// Creates an optimized constant true specification
    @inlinable
    static func constantTrue() -> AnySpecification<T> {
        AnySpecification(AlwaysTrueSpec<T>())
    }

    /// Creates an optimized constant false specification
    @inlinable
    static func constantFalse() -> AnySpecification<T> {
        AnySpecification(AlwaysFalseSpec<T>())
    }
}

// MARK: - Collection Extensions

public extension Collection where Element: Specification {
    /// Creates a specification that is satisfied when all specifications in the collection are satisfied
    /// - Returns: An AnySpecification that represents the AND of all specifications
    @inlinable
    func allSatisfied() -> AnySpecification<Element.T> {
        // Optimize for empty collection
        guard !isEmpty else { return .constantTrue() }

        // Optimize for single element
        if count == 1, let first {
            return AnySpecification(first)
        }

        return AnySpecification { candidate in
            self.allSatisfy { spec in
                spec.isSatisfiedBy(candidate)
            }
        }
    }

    /// Creates a specification that is satisfied when any specification in the collection is satisfied
    /// - Returns: An AnySpecification that represents the OR of all specifications
    @inlinable
    func anySatisfied() -> AnySpecification<Element.T> {
        // Optimize for empty collection
        guard !isEmpty else { return .constantFalse() }

        // Optimize for single element
        if count == 1, let first {
            return AnySpecification(first)
        }

        return AnySpecification { candidate in
            self.contains { spec in
                spec.isSatisfiedBy(candidate)
            }
        }
    }
}

// MARK: - Helper Specs for AnySpecification

/// A specification that always evaluates to true
public struct AlwaysTrueSpec<T>: Specification {
    /// Creates a new AlwaysTrueSpec
    public init() {}

    public func isSatisfiedBy(_ candidate: T) -> Bool {
        true
    }
}

/// A specification that always evaluates to false
public struct AlwaysFalseSpec<T>: Specification {
    /// Creates a new AlwaysFalseSpec
    public init() {}

    public func isSatisfiedBy(_ candidate: T) -> Bool {
        false
    }
}
