import SwiftUI
import UIKit

@main
struct SomniaApp: App {
    init() {
        let background = UIColor(red: 0.04, green: 0.06, blue: 0.12, alpha: 1)
        let navigation = UINavigationBarAppearance()
        navigation.configureWithOpaqueBackground()
        navigation.backgroundColor = background
        navigation.titleTextAttributes = [.foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance = navigation
        UINavigationBar.appearance().scrollEdgeAppearance = navigation
        let tabs = UITabBarAppearance()
        tabs.configureWithOpaqueBackground()
        tabs.backgroundColor = background
        let muted = UIColor.white.withAlphaComponent(0.62)
        let teal = UIColor(red: 0.96, green: 0.62, blue: 0.76, alpha: 1)
        tabs.stackedLayoutAppearance.normal.iconColor = muted
        tabs.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: muted]
        tabs.stackedLayoutAppearance.selected.iconColor = teal
        tabs.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: teal]
        UITabBar.appearance().standardAppearance = tabs
        UITabBar.appearance().scrollEdgeAppearance = tabs
        UITabBar.appearance().tintColor = teal
        UITabBar.appearance().unselectedItemTintColor = muted
    }

    @State private var model = DemoModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .preferredColorScheme(.dark)
        }
    }
}
