import MonitorCore
import SwiftUI

/// The Sidebar session tree with a sort selector above it. The chosen order is remembered.
struct SessionSidebarList: View {
    @Bindable var model: SessionExplorerModel
    @AppStorage("sessionExplorer.sortOrder") private var sortOrderRaw = SessionSortOrder.default.rawValue

    private var reportTimeZone: TimeZone { TimeZone(identifier: model.query.timeZoneIdentifier) ?? .current }

    private var sortOrder: SessionSortOrder { SessionSortOrder(rawValue: sortOrderRaw) ?? .default }

    var body: some View {
        VStack(spacing: 0) {
            sortSelector
            Divider()
            sessionList
        }
    }

    private var sortSelector: some View {
        Picker("Sort", selection: $sortOrderRaw) {
            ForEach(SessionSortKey.allCases, id: \.self) { key in
                Section(key.title) {
                    ForEach(SessionSortOrder.all.filter { $0.key == key }) { order in
                        Text(order.title).tag(order.rawValue)
                    }
                }
            }
        }
        .pickerStyle(.menu)
        .help("Sort sessions")
        .accessibilityIdentifier("sessionExplorer.sort")
        .padding(.horizontal, SessionExplorerSidebarLayout.sectionInset)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sessionList: some View {
        List(selection: Binding(
            get: { model.navigation.selectedSessionID },
            set: { model.selectSession($0) }
        )) {
            OutlineGroup(sortOrder.sorted(model.visibleSessionTree), children: \.outlineChildren) { node in
                SessionListRow(node: node, provenance: model.provenance[node.id],
                               sortDetail: sortOrder.detail(for: node.session, timeZone: reportTimeZone))
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
}
