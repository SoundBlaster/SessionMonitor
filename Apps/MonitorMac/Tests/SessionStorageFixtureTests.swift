import AppKit
import MonitorCore
import SwiftUI
import XCTest
@testable import SessionMonitor

@MainActor
final class SessionStorageFixtureTests: XCTestCase {
    func testInspectorStorageInLightDarkPartialAndUnknownStates() throws {
        let known = SessionStorageSummary(knownBytes: 12_345_678, fileCount: 2, unknownSizeFileCount: 0,
                                          lastModifiedAt: Date(timeIntervalSince1970: 1_793_000_000))
        let partial = SessionStorageSummary(knownBytes: 12_345_678, fileCount: 3, unknownSizeFileCount: 1,
                                            lastModifiedAt: nil)
        for scheme in [ColorScheme.light, .dark] {
            for (name, storage) in [("known", known), ("partial", partial), ("unknown", nil)] {
                let content = Form { SessionStorageSection(storage: storage) }
                    .formStyle(.grouped)
                    .frame(width: 360, height: 500)
                    .environment(\.colorScheme, scheme)
                    .environment(\.locale, Locale(identifier: "en_US"))
                let host = NSHostingView(rootView: content)
                host.frame.size = NSSize(width: 360, height: 500)
                let window = NSWindow(contentRect: host.frame, styleMask: [.borderless],
                                      backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                window.contentView = host
                defer { window.orderOut(nil) }
                window.orderFrontRegardless()
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
                host.layoutSubtreeIfNeeded()
                host.displayIfNeeded()
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let image = NSImage(size: host.bounds.size)
                image.addRepresentation(bitmap)
                let attachment = XCTAttachment(image: image)
                attachment.name = "storage-inspector-\(scheme)-\(name)"
                attachment.lifetime = .keepAlways
                add(attachment)
                XCTAssertEqual(host.bounds.width, 360)
                XCTAssertEqual(host.bounds.height, 500)
            }
        }
    }
}
