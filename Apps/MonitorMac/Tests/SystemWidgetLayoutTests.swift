#if DEBUG
import AppKit
import MonitorCore
import SwiftUI
import WidgetKit
import XCTest
@testable import SessionMonitor

final class SystemWidgetLayoutTests: XCTestCase {
    @MainActor
    func testCacheWidgetRendersAllSizes() throws {
        let snapshot = WidgetPreviewData.snapshot
        let cache = try XCTUnwrap(snapshot.cache)
        let entry = SessionMonitorWidgetEntry(date: snapshot.generatedAt, snapshot: snapshot)
        for (name, family, width, height) in [("small", WidgetFamily.systemSmall, 164.0, 164.0),
                                              ("medium", .systemMedium, 344.0, 164.0),
                                              ("large", .systemLarge, 344.0, 344.0)] {
            for inset in [0.0, 16.0] {
                let padding = family == .systemSmall ? WidgetDesignTokens.compactInset : WidgetDesignTokens.contentInset
                let view = CacheWidgetContent(cache: cache, entry: entry, family: family)
                    .padding(padding)
                    .frame(width: width - inset * 2, height: height - inset * 2)
                    .background(Color.black).environment(\.colorScheme, .dark)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                let image = try XCTUnwrap(renderer.nsImage)
                XCTAssertEqual(image.size.width, width - inset * 2, accuracy: 1)
                XCTAssertEqual(image.size.height, height - inset * 2, accuracy: 1)
                let attachment = XCTAttachment(image: image)
                attachment.name = "\(name)-inset-\(Int(inset))"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }
}
#endif
