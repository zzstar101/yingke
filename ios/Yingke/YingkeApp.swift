import CampusCore
import SwiftUI

@main
struct YingkeApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = AccountsModel()

    var body: some Scene {
        WindowGroup {
            TabView {
                NavigationStack {
                    HomeView()
                        .navigationDestination(for: CampusPlatform.self) { platform in
                            PlatformDetailView(platform: platform, model: model)
                        }
                }
                .tabItem { Label("首页", systemImage: "house") }

                NavigationStack {
                    AccountsView(model: model)
                        .navigationDestination(for: CampusPlatform.self) { platform in
                            PlatformDetailView(platform: platform, model: model)
                        }
                }
                .tabItem { Label("校园账号", systemImage: "person.crop.circle") }
            }
            .tint(CampusTheme.accent)
            .task(id: scenePhase) {
                if scenePhase == .active {
                    await model.reload()
                }
            }
        }
    }
}
