import SwiftUI

struct PrimaryNavigationSection: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var navigation: AppNavigation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SidebarRowButton(
                title: "Library",
                systemImage: navigation.route == .library && model.selectedLibrarySurface == .papers ? "books.vertical.fill" : "books.vertical",
                selected: navigation.route == .library && model.selectedLibrarySurface == .papers
            ) {
                model.goToLibrary()
            }

            if !model.usesObsidianCatalog {
                SidebarRowButton(
                    title: "探索",
                    systemImage: "sparkle.magnifyingglass",
                    selected: navigation.route == .discover
                ) {
                    model.showDiscover()
                }

                SidebarRowButton(
                    title: "搜索",
                    systemImage: "magnifyingglass",
                    selected: navigation.route == .search
                ) {
                    model.showSearch()
                }
            }

            SidebarRowButton(
                title: "Settings",
                systemImage: "gearshape",
                selected: navigation.route == .settings
            ) {
                model.showSettings()
            }

            SidebarRowButton(
                title: "Recent Conversations",
                systemImage: "clock",
                selected: navigation.route == .library && model.selectedLibrarySurface == .recentConversations
            ) {
                model.showRecentConversations()
            }
        }
    }
}
