//
//  AnyContextProvider.swift
//  SpecificationCore
//
//  Type erasure for ContextProviding to enable heterogeneous storage.
//

import Foundation

/// A type-erased context provider.
///
/// Use `AnyContextProvider` when you need to store heterogeneous
/// `ContextProviding` instances in collections (e.g., for composition) or
/// expose a stable provider type from APIs.
public struct AnyContextProvider<Context>: ContextProviding {
    private let _currentContext: () -> Context

    /// Wraps a concrete context provider.
    public init<P: ContextProviding>(_ base: P) where P.Context == Context {
        _currentContext = base.currentContext
    }

    /// Wraps a context-producing closure.
    /// - Parameter makeContext: Closure invoked to produce a context snapshot.
    public init(_ makeContext: @escaping () -> Context) {
        _currentContext = makeContext
    }

    public func currentContext() -> Context { _currentContext() }
}
