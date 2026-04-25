import SwiftUI

struct ConfigurationView: View {
    var body: some View {
        TabView {
            PipelineListView()
                .tabItem { Label("Pipelines", systemImage: "list.bullet.rectangle") }
                .tag(0)

            ProviderSettingsView()
                .tabItem { Label("Providers", systemImage: "key.fill") }
                .tag(1)

            ShortcutSettingsView()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
                .tag(2)

            LogView()
                .tabItem { Label("Log", systemImage: "doc.text.magnifyingglass") }
                .tag(3)
        }
        .frame(minWidth: 640, minHeight: 460)
    }
}
