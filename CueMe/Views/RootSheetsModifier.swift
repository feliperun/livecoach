import SwiftUI

struct RootSheetsModifier: ViewModifier {
    @Bindable var app: AppModel

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $app.showSettings) {
                BriefEditor()
            }
            .sheet(isPresented: $app.showPreflight) {
                PreflightView()
            }
            .sheet(isPresented: $app.showVoiceMemoImporter) {
                VoiceMemoImportView()
            }
    }
}
