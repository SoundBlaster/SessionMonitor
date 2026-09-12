import SpecificationCore
import Testing

struct SpecificationIntegrationTests {
    @Test func erasedBuilderPreservesFirstMatchAndFallback() {
        let specification = FirstMatchSpec<Int, String>.builder()
            .add(PredicateSpec<Int> { $0 > 10 }, result: "large")
            .fallback("small")
            .build()
        #expect(specification.decide(11) == "large")
        #expect(specification.decide(1) == "small")
    }
}
