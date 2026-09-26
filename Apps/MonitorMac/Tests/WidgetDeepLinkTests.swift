import MonitorCore
import XCTest

final class WidgetDeepLinkTests: XCTestCase {
    func testUsageWidgetRoutesRoundTripForSupportedPeriods() throws {
        for period in WidgetUsagePeriod.allCases {
            let route = WidgetDeepLinkRoute.usage(period)
            let url = try XCTUnwrap(route.url)

            XCTAssertEqual(WidgetDeepLinkRoute(url: url), route)
            XCTAssertEqual(url.scheme, WidgetDeepLinkRoute.scheme)
        }
    }

    func testCacheHitWidgetRouteRoundTripsWithoutIdentityParameters() throws {
        let url = try XCTUnwrap(WidgetDeepLinkRoute.cacheHitRate.url)

        XCTAssertEqual(WidgetDeepLinkRoute(url: url), .cacheHitRate)
        XCTAssertNil(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertNil(url.user)
        XCTAssertNil(url.password)
    }

    func testUnknownOrMalformedWidgetLinksAreRejected() {
        XCTAssertNil(WidgetDeepLinkRoute(url: URL(string: "https://example.com/usage")!))
        XCTAssertNil(WidgetDeepLinkRoute(url: URL(string: "sessionmonitor://unknown")!))
        XCTAssertNil(WidgetDeepLinkRoute(url: URL(string: "sessionmonitor://usage?period=all")!))
        XCTAssertNil(WidgetDeepLinkRoute(url: URL(string: "sessionmonitor://usage")!))
    }
}
