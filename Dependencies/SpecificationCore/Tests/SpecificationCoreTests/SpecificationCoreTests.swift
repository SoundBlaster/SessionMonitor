//
//  SpecificationCoreTests.swift
//  SpecificationCoreTests
//
//  Basic smoke tests for SpecificationCore
//

@testable import SpecificationCore
import XCTest

final class SpecificationCoreTests: XCTestCase {
    // MARK: - Core Protocol Tests

    func testSpecificationComposition() {
        let greaterThan5 = PredicateSpec<Int> { $0 > 5 }
        let lessThan10 = PredicateSpec<Int> { $0 < 10 }

        let between5And10 = greaterThan5.and(lessThan10)

        XCTAssertTrue(between5And10.isSatisfiedBy(7))
        XCTAssertFalse(between5And10.isSatisfiedBy(3))
        XCTAssertFalse(between5And10.isSatisfiedBy(12))
    }

    func testSpecificationNegation() {
        let isEven = PredicateSpec<Int> { $0 % 2 == 0 }
        let isOdd = isEven.not()

        XCTAssertTrue(isOdd.isSatisfiedBy(3))
        XCTAssertFalse(isOdd.isSatisfiedBy(4))
    }

    // MARK: - Context Tests

    func testEvaluationContext() {
        let context = EvaluationContext(
            counters: ["loginAttempts": 3],
            flags: ["isPremium": true]
        )

        XCTAssertEqual(context.counter(for: "loginAttempts"), 3)
        XCTAssertTrue(context.flag(for: "isPremium"))
        XCTAssertFalse(context.flag(for: "nonexistent"))
    }

    func testDefaultContextProvider() {
        let provider = DefaultContextProvider.shared

        provider.setCounter("test", to: 5)
        provider.setFlag("testFlag", to: true)

        let context = provider.currentContext()

        XCTAssertEqual(context.counter(for: "test"), 5)
        XCTAssertTrue(context.flag(for: "testFlag"))

        // Cleanup
        provider.clearAll()
    }

    // MARK: - Specification Tests

    func testMaxCountSpec() {
        let provider = DefaultContextProvider.shared
        provider.setCounter("clicks", to: 3)

        let maxClicks = MaxCountSpec(counterKey: "clicks", maximumCount: 5)
        let context = provider.currentContext()

        XCTAssertTrue(maxClicks.isSatisfiedBy(context))

        provider.setCounter("clicks", to: 6)
        let newContext = provider.currentContext()
        XCTAssertFalse(maxClicks.isSatisfiedBy(newContext))

        // Cleanup
        provider.clearAll()
    }

    func testPredicateSpec() {
        let isAdult = PredicateSpec<Int> { age in age >= 18 }

        XCTAssertTrue(isAdult.isSatisfiedBy(25))
        XCTAssertFalse(isAdult.isSatisfiedBy(16))
    }

    func testFirstMatchSpec() {
        let context = EvaluationContext(counters: ["purchases": 7])

        enum DiscountTier: Equatable { case none, bronze, silver, gold }

        let tierSpec = FirstMatchSpec<EvaluationContext, DiscountTier>([
            (MaxCountSpec(counterKey: "purchases", maximumCount: 10).not(), .gold),
            (MaxCountSpec(counterKey: "purchases", maximumCount: 5).not(), .silver),
            (MaxCountSpec(counterKey: "purchases", maximumCount: 2).not(), .bronze)
        ])

        let tier = tierSpec.decide(context)
        XCTAssertEqual(tier, .silver)
    }

    // MARK: - Property Wrapper Tests

    func testSatisfiesWrapperManual() {
        let provider = DefaultContextProvider.shared
        provider.setCounter("age", to: 25)

        let adultSpec = PredicateSpec<EvaluationContext> { context in
            context.counter(for: "age") >= 18
        }

        let wrapper = Satisfies(provider: provider, using: adultSpec)
        XCTAssertTrue(wrapper.wrappedValue)

        provider.setCounter("age", to: 16)
        let minorWrapper = Satisfies(provider: provider, using: adultSpec)
        XCTAssertFalse(minorWrapper.wrappedValue)

        // Cleanup
        provider.clearAll()
    }

    func testDecidesWrapperManual() {
        enum AccessLevel: Equatable { case guest, user, admin }

        let provider = DefaultContextProvider.shared
        provider.setFlag("isAdmin", to: true)

        let isAdminSpec = PredicateSpec<EvaluationContext> { $0.flag(for: "isAdmin") }
        let isUserSpec = PredicateSpec<EvaluationContext> { $0.flag(for: "isUser") }

        let wrapper = Decides(
            provider: provider,
            firstMatch: [
                (isAdminSpec, AccessLevel.admin),
                (isUserSpec, AccessLevel.user)
            ],
            fallback: .guest
        )

        XCTAssertEqual(wrapper.wrappedValue, .admin)

        provider.setFlag("isAdmin", to: false)
        let guestWrapper = Decides(
            provider: provider,
            firstMatch: [
                (isAdminSpec, AccessLevel.admin),
                (isUserSpec, AccessLevel.user)
            ],
            fallback: .guest
        )
        XCTAssertEqual(guestWrapper.wrappedValue, .guest)

        // Cleanup
        provider.clearAll()
    }

    // MARK: - Type Erasure Tests

    func testAnySpecification() {
        let spec1 = PredicateSpec<Int> { $0 > 5 }
        let spec2 = PredicateSpec<Int> { $0 < 10 }

        let specs: [AnySpecification<Int>] = [
            AnySpecification(spec1),
            AnySpecification(spec2)
        ]

        XCTAssertTrue(specs[0].isSatisfiedBy(7))
        XCTAssertTrue(specs[1].isSatisfiedBy(7))
    }

    func testAnySpecificationConstants() {
        let alwaysTrue = AnySpecification<Int>.always
        let alwaysFalse = AnySpecification<Int>.never

        XCTAssertTrue(alwaysTrue.isSatisfiedBy(42))
        XCTAssertFalse(alwaysFalse.isSatisfiedBy(42))
    }

    // MARK: - Async Tests

    func testAsyncSpecification() async throws {
        let asyncSpec = AnyAsyncSpecification<Int> { value in
            // Simulate async work
            try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
            return value > 5
        }

        let result = try await asyncSpec.isSatisfiedBy(7)
        XCTAssertTrue(result)
    }
}
