import AppKit
import MonitorCore
import SwiftUI
import UniformTypeIdentifiers

struct SessionExplorerPage: View {
    @AppStorage(UsageChartPaletteSelection.storageKey)
    private var chartPaletteRawValue = UsageChartPaletteSelection.system.rawValue
    @Bindable var model: SessionExplorerModel
    @Bindable var reportScope: ReportScopeModel
    @Bindable var cacheHitRateWidgetSettings: CacheHitRateWidgetSettings
    var cacheAnalytics: CacheAnalyticsPresentation?

    var body: some View {
        NavigationSplitView(columnVisibility: $model.navigation.columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 240, ideal: 290, max: 420)
        } detail: {
            SessionExplorerDetailLayout {
                if let session = model.selectedSession {
                    SessionDetailView(session: session, query: model.query,
                                      timelineModel: model.timelineModel, provider: model.contextProvider,
                                      sessionTitle: model.provenance[session.id]?.sessionTitle
                                        ?? model.provenance[session.id]?.displayName,
                                      chartPalette: chartPalette)
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity,
                               alignment: .topLeading)
                        .task(id: model.timelineLoadID) {
                            await model.loadTimeline(sessionID: session.id)
                        }
                } else {
                    emptyDetail
                }
            } notices: {
                SessionExplorerImportNotices(model: model, reportScope: reportScope)
            }
            .navigationTitle("SessionMonitor")
            .navigationSubtitle("\(reportScope.accountLabel) · Canonical usage")
            .toolbar {
                SessionExplorerDetailToolbar(model: model) { sessionID in
                    exportSession(sessionID: sessionID)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
        }
        .toolbar {
            SessionExplorerToolbar(
                model: model,
                reportScope: reportScope,
                chooseImportDirectory: chooseImportDirectory
            )
        }
        .inspector(isPresented: $model.navigation.showsInspector) {
            SessionReportInspector(model: model)
                .inspectorColumnWidth(min: 250, ideal: 300, max: 400)
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            statusBar
        }
        .modifier(QuotaPresentationLoader(model: model))
        .findingsAlertsSheet(model: model)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarHeader
                .frame(height: SessionExplorerSidebarLayout.headerHeight, alignment: .topLeading)
            Divider()
            sidebarChart
            if let interval = reportScope.focusedInterval {
                SessionExplorerFocusChip(interval: interval, timeZoneIdentifier: reportScope.query.timeZoneIdentifier,
                                         clear: { reportScope.clearFocus() })
            }
            Divider()
            SessionSidebarList(model: model)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .layoutPriority(1)
        }
        .navigationTitle("Sessions")
        .safeAreaPadding(.top)
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }

    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(reportScope.accountLabel) · \(reportScope.title)")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            SessionSidebarTotals(sessions: Int64(model.report.sessions.count),
                                 requests: model.report.totals.requests,
                                 inputTokens: model.report.totals.inputTokens,
                                 outputTokens: model.report.totals.outputTokens)
            Text("Totals use the selected period. Search only narrows this list.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding()
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }

    private var sidebarChart: some View {
        SessionExplorerCacheChart(model: model, reportScope: reportScope,
                                  settings: cacheHitRateWidgetSettings, chartPalette: chartPalette,
                                  analytics: cacheAnalytics)
    }

    private var chartPalette: UsageChartPalette {
        UsageChartPaletteSelection(rawValue: chartPaletteRawValue)?.palette ?? .system
    }

    private var emptyDetail: some View {
        Group {
            if model.activity == .loading && model.report.sessions.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading imported sessions…")
                        .foregroundStyle(.secondary)
                }
            } else if model.report.sessions.isEmpty {
                ContentUnavailableView {
                    Label("No canonical sessions yet", systemImage: "folder")
                } description: {
                    Text("Import a folder containing JSONL rollouts. "
                         + "Only confirmed canonical usage is counted; legacy token_count records are excluded.")
                } actions: {
                    Button("Import Folder…", action: chooseImportDirectory)
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isBusy)
                }
            } else if model.visibleSessions.isEmpty {
                ContentUnavailableView.search(text: model.filter)
            } else {
                ContentUnavailableView("Select a session", systemImage: "sidebar.left",
                                       description: Text("Choose a session to inspect its usage and cache coverage."))
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if model.isBusy {
                ProgressView().controlSize(.small)
                Text(model.activity == .importing ? "Importing JSONL files…" : "Refreshing report…")
            } else if let summary = model.importSummary {
                Text("Last import: \(summary.files) files · \(summary.records) canonical records")
            } else if let date = model.lastUpdated {
                Text("Updated \(date.formatted(date: .omitted, time: .shortened))").monospaced()
            } else {
                Text("Choose a JSONL folder to get started")
            }
            Spacer()
            Text("Canonical only · Legacy excluded")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(.bar)
    }

    private func chooseImportDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Import JSONL Rollouts"
        panel.directoryURL = RolloutDirectorySelection.initialDirectory(preferred: model.importedDirectory)
        panel.showsHiddenFiles = true
        panel.message = "Choose a folder. JSONL files in its subfolders will also be imported."
        panel.prompt = "Import"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        let lease = SecurityScopedResourceLease(directory, fromPanel: true)
        model.startImportDirectory(directory) {
            await reportScope.refreshProfiles()
            withExtendedLifetime(lease) {}
        }
    }

    private func exportSession(sessionID: String) {
        Task { @MainActor in
            do {
                guard let data = try await model.anonymizedSessionExportData(sessionID: sessionID) else { return }
                let panel = NSSavePanel()
                panel.title = "Export Anonymized Session"
                panel.nameFieldStringValue = "session-export.json"
                panel.allowedContentTypes = [.json]
                panel.canCreateDirectories = true
                guard panel.runModal() == .OK, let destination = panel.url else { return }
                defer { destination.stopAccessingSecurityScopedResource() }
                try data.write(to: destination, options: .atomic)
            } catch {
                model.reportError("Could not export anonymized session JSON. \(error.localizedDescription)")
            }
        }
    }
}

extension CacheHitRateWidgetPeriod {
    /// The chart follows the report period; "All Time" uses the period chosen in Settings.
    static func sidebar(for preset: ReportScopeModel.PeriodPreset, fallback: Self) -> Self {
        switch preset {
        case .all: fallback
        case .today: .last24Hours
        case .lastSevenDays: .last7Days
        case .lastThirtyDays: .last30Days
        }
    }
}

enum SessionExplorerSidebarLayout {
    // The sidebar has two fixed sections followed by the only flexible region.
    static let headerHeight: CGFloat = 176
    static let chartHeight: CGFloat = 256
    static let sectionInset: CGFloat = 16
}

private struct QuotaPresentationLoadID: Hashable {
    let query: UsageQuery
    let revision: Int64?
}

private struct QuotaPresentationLoader: ViewModifier {
    let model: SessionExplorerModel

    func body(content: Content) -> some View {
        content.task(id: QuotaPresentationLoadID(
            query: model.query, revision: model.snapshot?.watermark.revision
        )) {
            guard model.snapshot != nil else { return }
            await model.loadQuotaPresentation()
            while !Task.isCancelled {
                guard let delay = model.quotaFreshnessRefreshDelay() else { return }
                do {
                    try await Task.sleep(for: .seconds(delay))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await model.loadQuotaPresentation()
            }
        }
    }
}
