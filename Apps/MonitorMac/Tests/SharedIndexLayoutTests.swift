import AppKit
import SwiftUI
import XCTest
@testable import SessionMonitor

@MainActor
final class SharedIndexLayoutTests: XCTestCase {
    func testConnectionAndPendingFolderSettingsInLightAndDark() async throws {
        let connection = SharedIndexConnection(
            databaseURL: URL(fileURLWithPath: "/Users/example/Library/Application Support/SessionMonitor/usage.sqlite"),
            selectedDirectory: URL(fileURLWithPath: "/Users/example/A different index folder", isDirectory: true)
        )
        let model = SharedIndexLocationModel(restore: { connection }, select: { _ in connection })
        await model.restoreIfNeeded()
        XCTAssertTrue(model.needsRestart)
        let disconnected = SharedIndexLocationModel(restore: { throw SharedIndexError.selectionRequired },
                                                    select: { _ in connection })
        await disconnected.restoreIfNeeded()
        for scheme in [ColorScheme.light, .dark] {
            try capture(MonitorSettingsPage(cacheHitRateWidgetSettings: CacheHitRateWidgetSettings(),
                                            sharedIndex: model), size: NSSize(width: 580, height: 590),
                        scheme: scheme, name: "shared-index-settings-\(scheme)")
            try capture(SharedIndexGate(model: disconnected) { Text("Unexpected connected content") }
                .frame(maxWidth: .infinity, maxHeight: .infinity), size: NSSize(width: 760, height: 520),
                        scheme: scheme, name: "shared-index-connect-\(scheme)")
        }
    }

    private func capture(_ view: some View, size: NSSize, scheme: ColorScheme, name: String) throws {
        let host = NSHostingView(rootView: view.environment(\.colorScheme, scheme)
            .environment(\.locale, Locale(identifier: "en_US"))
            .background(Color(nsColor: .windowBackgroundColor)))
        host.frame.size = size
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let image = NSImage(size: host.bounds.size)
        image.addRepresentation(bitmap)
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        // Deterministic, synthetic previews for local inspection; never include the real index.
        let directory = URL.temporaryDirectory.appending(path: "SessionMonitor-shared-index-previews")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            .write(to: directory.appending(path: name + ".png"))
    }
}
