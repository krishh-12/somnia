import SwiftUI
import UIKit

@main
struct SomniaApp: App {
    init() {
        let background = UIColor(red: 0.04, green: 0.06, blue: 0.12, alpha: 1)
        let navigation = UINavigationBarAppearance()
        navigation.configureWithOpaqueBackground()
        navigation.backgroundColor = background
        let titleFont = UIFont.systemFont(ofSize: 17, weight: .semibold).fontDescriptor.withDesign(.rounded)
            .map { UIFont(descriptor: $0, size: 17) } ?? UIFont.systemFont(ofSize: 17, weight: .semibold)
        let tabFont = UIFont.systemFont(ofSize: 10, weight: .medium).fontDescriptor.withDesign(.rounded)
            .map { UIFont(descriptor: $0, size: 10) } ?? UIFont.systemFont(ofSize: 10, weight: .medium)
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
