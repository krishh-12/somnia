import SwiftUI

@main
struct SomniaApp: App {
    @State private var model = DemoModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .preferredColorScheme(.dark)
        }
    }
}
