import SwiftUI

enum PreferencesTab: String, CaseIterable {
    case pipelines, providers, shortcuts, log, about

    var title: String {
        switch self {
        case .pipelines: "Pipelines"
        case .providers: "Providers"
        case .shortcuts: "Shortcuts"
        case .log: "Log"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .pipelines: "list.bullet.rectangle.portrait"
        case .providers: "key.horizontal"
        case .shortcuts: "keyboard"
        case .log: "doc.text.magnifyingglass"
        case .about: "info.circle"
        }
    }
}

struct PreferencesView: View {
    @State private var selectedTab: PreferencesTab = .pipelines

    var body: some View {
        VStack(spacing: 0) {
            PreferencesTabBar(selectedTab: $selectedTab)
            Divider()
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 720, minHeight: 480)
        // Suppress NavigationSplitView (and other SwiftUI containers) from injecting
        // their own items into the window toolbar or changing the window title.
        .toolbar(.hidden, for: .windowToolbar)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .pipelines: PipelineListView()
        case .providers: ProviderSettingsView()
        case .shortcuts: ShortcutSettingsView()
        case .log: LogView()
        case .about: AboutView()
        }
    }
}

struct PreferencesTabBar: View {
    @Binding var selectedTab: PreferencesTab

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 12)
            ForEach(PreferencesTab.allCases, id: \.self) { tab in
                PreferencesTabButton(tab: tab, isSelected: selectedTab == tab) {
                    selectedTab = tab
                }
            }
            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity, minHeight: 68)
    }
}

private struct PreferencesTabButton: View {
    let tab: PreferencesTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 22))
                    .frame(width: 40, height: 30)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Color.accentColor)
                        }
                    }
                    .foregroundStyle(isSelected ? Color.white : Color.secondary)
                Text(tab.title)
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            }
            .frame(width: 68)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
