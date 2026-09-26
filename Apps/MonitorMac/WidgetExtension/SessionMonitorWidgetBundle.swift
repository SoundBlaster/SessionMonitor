import SwiftUI
import WidgetKit

@main
struct SessionMonitorWidgetBundle: WidgetBundle {
    var body: some Widget {
        SessionMonitorUsageWidget()
        SessionMonitorCacheHitRateWidget()
    }
}
