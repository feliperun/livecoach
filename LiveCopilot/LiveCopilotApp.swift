import SwiftUI

@main
struct LiveCopilotApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .frame(minWidth: 380, minHeight: 520)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 460, height: 720)
    }
}
