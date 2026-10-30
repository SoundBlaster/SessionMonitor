import Foundation
import MonitorCore
import SwiftUI
import WidgetKit

#if DEBUG
#Preview("Cache Hit Rate · Small", as: .systemSmall) {
    SessionMonitorCacheHitRateWidget()
} timeline: {
    SessionMonitorWidgetEntry(date: .now, snapshot: WidgetPreviewData.snapshot)
}

#Preview("Cache Hit Rate · Medium", as: .systemMedium) {
    SessionMonitorCacheHitRateWidget()
} timeline: {
    SessionMonitorWidgetEntry(date: .now, snapshot: WidgetPreviewData.snapshot)
}

#Preview("Cache Hit Rate · Large", as: .systemLarge) {
    SessionMonitorCacheHitRateWidget()
} timeline: {
    SessionMonitorWidgetEntry(date: .now, snapshot: WidgetPreviewData.snapshot)
}

#Preview("Usage Summary · Small", as: .systemSmall) {
    SessionMonitorUsageWidget()
} timeline: {
    SessionMonitorWidgetEntry(date: .now, snapshot: WidgetPreviewData.snapshot)
}

#Preview("Usage Summary · Medium", as: .systemMedium) {
    SessionMonitorUsageWidget()
} timeline: {
    SessionMonitorWidgetEntry(date: .now, snapshot: WidgetPreviewData.snapshot)
}

#Preview("Usage Summary · Large", as: .systemLarge) {
    SessionMonitorUsageWidget()
} timeline: {
    SessionMonitorWidgetEntry(date: .now, snapshot: WidgetPreviewData.snapshot)
}
#endif
