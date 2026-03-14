import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            CaptureSettingsView()
                .tabItem { Label("Capture", systemImage: "camera") }

            AIModelSettingsView()
                .tabItem { Label("AI Models", systemImage: "brain") }

            AnalysisSettingsView()
                .tabItem { Label("Analysis", systemImage: "chart.xyaxis.line") }

            ExportImportSettingsView()
                .tabItem { Label("Import/Export", systemImage: "arrow.up.arrow.down") }

            DebugSettingsView()
                .tabItem { Label("Developer", systemImage: "ladybug") }
        }
        .frame(minWidth: 520, minHeight: 480)
    }
}

#Preview {
    SettingsView()
}
