import SwiftUI
import UIKit

@main
struct SomniaApp: App {
    init() {
        let background = Night.uiBackground
        let navigation = UINavigationBarAppearance()
        navigation.configureWithOpaqueBackground()
        navigation.backgroundColor = background
        let titleFont = Night.face(size: 17, weight: 600)
        let tabFont = Night.face(size: 10, weight: 520)
        navigation.titleTextAttributes = [.foregroundColor: UIColor.white, .font: titleFont]
        UINavigationBar.appearance().standardAppearance = navigation
        UINavigationBar.appearance().scrollEdgeAppearance = navigation
        let tabs = UITabBarAppearance()
        tabs.configureWithOpaqueBackground()
        tabs.backgroundColor = background
        let muted = UIColor.white.withAlphaComponent(0.62)
        let pink = UIColor(red: 0.96, green: 0.62, blue: 0.76, alpha: 1)
        tabs.stackedLayoutAppearance.normal.iconColor = muted
        tabs.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: muted, .font: tabFont]
        tabs.stackedLayoutAppearance.selected.iconColor = pink
        tabs.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: pink, .font: tabFont]
        UITabBar.appearance().standardAppearance = tabs
        UITabBar.appearance().scrollEdgeAppearance = tabs
        UITabBar.appearance().tintColor = pink
        UITabBar.appearance().unselectedItemTintColor = muted
    }

    @State private var model = DemoModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .environment(\.font, .somnia(.body))
                .preferredColorScheme(.dark)
        }
    }
}
