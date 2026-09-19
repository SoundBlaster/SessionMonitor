import AppKit
import MonitorCore
import SwiftUI

struct SessionExplorerPage: View {
    @Bindable var model: SessionExplorerModel
    @Bindable var reportScope: ReportScopeModel
    @Bindable var cacheHitRateWidgetSettings: CacheHitRateWidgetSettings

    var body: some View {
        NavigationSplitView(columnVisibility: $model.navigation.columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 240, ideal: 290, max: 420)
        } detail: {
            VStack(spacing: 0) {
                if let error = model.errorMessage {
                    errorBanner(error)
                }
                if let session = model.selectedSession {
                    SessionDetailView(session: session, query: model.query,
                                      timelineModel: model.timelineModel, provider: model.contextProvider)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .task(id: timelineTaskID(session: session)) {
                            await model.loadTimeline(sessionID: session.id)
                        }
                } else {
                    emptyDetail
                }
            }
            .navigationTitle("SessionMonitor")
            .navigationSubtitle("Canonical usage")
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .toolbar {
            ToolbarItemGroup {
                Button("Import Folder…", systemImage: "folder.badge.plus", action: chooseImportDirectory)
                    .keyboardShortcut("o")
                    .disabled(model.isBusy)
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await model.refresh() }
                }
                .keyboardShortcut("r")
                .disabled(model.isBusy)
                ReportScopeControls(model: reportScope)
                Button("Show Inspector", systemImage: "sidebar.right") {
                    model.navigation.showsInspector.toggle()
                }
                .help("Show report coverage and import diagnostics")
            }
        }
        .inspector(isPresented: $model.navigation.showsInspector) {
            SessionReportInspector(model: model)
                .inspectorColumnWidth(min: 250, ideal: 300, max: 400)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            statusBar
        }
        .safeAreaPadding(.top)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarHeader
                .frame(height: SessionExplorerSidebarLayout.headerHeight, alignment: .topLeading)
            Divider()
            sidebarChart
            Divider()
            sidebarSessionList
                .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .layoutPriority(1)
        }
        .navigationTitle("Sessions")
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }

    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(reportScope.title)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            HStack {
                compactTotal("Sessions", value: Int64(model.report.sessions.count))
                Spacer()
                compactTotal("Requests", value: model.report.totals.requests)
            }
            HStack {
                compactTotal("Input tokens", value: model.report.totals.inputTokens)
                Spacer()
                compactTotal("Output tokens", value: model.report.totals.outputTokens)
            }
            Text("Totals use the selected period. Search only narrows this list.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }

    private var sidebarChart: some View {
        CacheHitRateWidget(
            report: model.cacheHitRateWidgetReport,
            family: .medium,
            containerStyle: .embedded
        )
        .padding(SessionExplorerSidebarLayout.sectionInset)
        .frame(height: SessionExplorerSidebarLayout.chartHeight, alignment: .topLeading)
        .clipped()
        .task(id: CacheHitRateWidgetLoadID(
            period: cacheHitRateWidgetSettings.period,
            revision: model.snapshot?.watermark.revision,
            timeZoneIdentifier: model.query.timeZoneIdentifier
        )) {
            guard model.snapshot != nil else { return }
            while !Task.isCancelled {
                let timeZone = TimeZone(identifier: model.query.timeZoneIdentifier) ?? .current
                await model.loadCacheHitRateWidget(
                    period: cacheHitRateWidgetSettings.period,
                    timeZone: timeZone
                )
                let nextRefresh = CacheHitRateWidgetRefreshSchedule.nextRefresh(after: Date(), timeZone: timeZone)
                do {
                    try await Task.sleep(for: .seconds(nextRefresh.timeIntervalSinceNow))
                } catch {
                    return
                }
            }
        }
    }

    private var sidebarSessionList: some View {
        List(selection: Binding(
            get: { model.navigation.selectedSessionID },
            set: { model.selectSession($0) }
        )) {
            OutlineGroup(model.visibleSessionTree, children: \.outlineChildren) { node in
                SessionListRow(node: node, provenance: model.provenance[node.id])
                    .tag(node.id)
            }
        }
        .overlay {
            if model.visibleSessions.isEmpty && !model.report.sessions.isEmpty {
                ContentUnavailableView.search(text: model.filter)
            }
        }
        .searchable(text: Binding(get: { model.filter }, set: { model.setFilter($0) }),
                    prompt: "Session ID or model")
        .accessibilityLabel("Sessions")
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if model.isBusy {
                ProgressView().controlSize(.small)
                Text(model.activity == .importing ? "Importing JSONL files…" : "Refreshing report…")
            } else if let summary = model.importSummary {
                Text("Last import: \(summary.files) files · \(summary.records) canonical records")
            } else if let date = model.lastUpdated {
                Text("Updated \(date.formatted(date: .omitted, time: .shortened))")
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

    private func compactTotal(_ label: String, value: Int64) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value, format: .number)
                .font(.headline.monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message).textSelection(.enabled)
            Spacer(minLength: 0)
            Button("Dismiss", systemImage: "xmark", action: model.dismissError)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
        }
        .padding()
        .background(.orange.opacity(0.10))
        .accessibilityElement(children: .combine)
    }

    private func chooseImportDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Import JSONL Rollouts"
        panel.message = "Choose a folder. JSONL files in its subfolders will also be imported."
        panel.prompt = "Import"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        Task { await model.importDirectory(directory) }
    }

    private func timelineTaskID(session: SessionSummary) -> String {
        let start = model.query.since?.timeIntervalSince1970.description ?? "-"
        let end = model.query.until?.timeIntervalSince1970.description ?? "-"
        return "\(session.id)|\(start)|\(end)|\(model.query.timeZoneIdentifier)"
    }
}

enum SessionExplorerSidebarLayout {
    // The sidebar has two fixed sections followed by the only flexible region.
    static let headerHeight: CGFloat = 176
    static let chartHeight: CGFloat = 240
    static let sectionInset: CGFloat = 16
}

private struct CacheHitRateWidgetLoadID: Hashable {
    let period: CacheHitRateWidgetPeriod
    let revision: Int64?
    let timeZoneIdentifier: String
}

private struct SessionListRow: View {
    let node: SessionTreeNode
    let provenance: SessionProvenance?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(provenance?.displayName ?? (node.session.model.isEmpty ? "Unknown model" : node.session.model))
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)
            Text(node.session.id)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(node.session.id)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Cache hit")
                    .foregroundStyle(.secondary)
                Text(cacheHit.value)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .help(cacheHit.explanation)
                    .accessibilityValue(cacheHit.accessibilityValue)
                Spacer(minLength: 0)
                Text("\(node.session.totals.requests.formatted()) requests")
                    .lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            HStack {
                Label(
                    stateLabel,
                    systemImage: node.state == .attached ? "arrow.turn.down.right" : "questionmark.circle"
                )
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }

    private var cacheHit: SessionCacheHitPresentation {
        SessionCacheHitPresentation(totals: node.session.totals)
    }

    private var stateLabel: String {
        switch node.state {
        case .knownRoot: "Root"
        case .attached: provenance?.relationship?.kind == .subagent ? "Subagent" : "Child"
        case .unknown: "Unknown"
        case .orphan: "Orphan"
        case .conflict: "Conflict"
        case .cycle: "Cycle"
        }
    }
}
