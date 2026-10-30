#if DEBUG
import SwiftUI
import WidgetKit

struct WidgetLabPage: View {
    var body: some View {
        TabView {
            SystemWidgetLabPage()
                .tabItem { Text("System widgets") }
            CacheWidgetLabPage()
                .tabItem { Text("Sidebar chart") }
        }
    }
}

private struct SystemWidgetLabPage: View {
    @State private var family: WidgetFamily = .systemMedium
    @State private var showsCache = true
    @State private var showsData = true
    @State private var dark = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Picker("Widget", selection: $showsCache) {
                    Text("Cache Hit Rate").tag(true)
                    Text("Usage Summary").tag(false)
                }
                Picker("Size", selection: $family) {
                    Text("Small").tag(WidgetFamily.systemSmall)
                    Text("Medium").tag(WidgetFamily.systemMedium)
                    Text("Large").tag(WidgetFamily.systemLarge)
                }
                Toggle("Sample data", isOn: $showsData)
                Toggle("Dark", isOn: $dark)
            }
            ScrollView([.horizontal, .vertical]) {
                SystemWidgetLabPreview(family: family, showsCache: showsCache, showsData: showsData)
                    .padding(32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color.secondary.opacity(0.12))
            Text("Synthetic data · approximate macOS widget sizes · system rendering can differ")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .preferredColorScheme(dark ? .dark : .light)
        .frame(minWidth: 800, minHeight: 680)
    }
}

private struct SystemWidgetLabPreview: View {
    let family: WidgetFamily
    let showsCache: Bool
    let showsData: Bool

    private var size: CGSize {
        switch family {
        case .systemSmall: CGSize(width: 164, height: 164)
        case .systemLarge: CGSize(width: 344, height: 344)
        default: CGSize(width: 344, height: 164)
        }
    }

    private var entry: SessionMonitorWidgetEntry {
        SessionMonitorWidgetEntry(date: .now, snapshot: showsData ? WidgetPreviewData.snapshot : nil)
    }

    var body: some View {
        Group {
            if showsCache, let cache = entry.snapshot?.cache {
                CacheWidgetContent(cache: cache, entry: entry, family: family)
                    .padding(family == .systemSmall ? WidgetDesignTokens.compactInset : WidgetDesignTokens.contentInset)
            } else if showsCache {
                WidgetUnavailableState(title: "Cache data unavailable",
                                       detail: "Open SessionMonitor to refresh the shared snapshot.")
                    .padding(family == .systemSmall ? WidgetDesignTokens.compactInset : WidgetDesignTokens.contentInset)
            } else {
                SessionMonitorUsageWidgetView(entry: entry, familyOverride: family)
            }
        }
        .frame(width: size.width, height: size.height)
        .background(.background, in: RoundedRectangle(cornerRadius: 22))
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }
}
#endif
