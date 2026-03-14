import SwiftUI

/// Identifier used for locating the main window without relying on title string matching.
/// AppDelegate and other code should use this instead of matching by window title.
enum MainWindowID {
    static let identifier = "com.anotherme.main-window"
}

/// Main window view with sidebar navigation.
/// Includes Dashboard, Chat, Profile, and Settings tabs.
struct MainWindowView: View {
    @State private var selectedTab: Tab = .dashboard
    @AppStorage("debug.devMode.enabled") private var devModeEnabled = false

    enum Tab: String, CaseIterable, Identifiable {
        case dashboard = "Dashboard"
        case chat = "Chat"
        case memory = "Memory"
        case profile = "Personality"
        case settings = "Settings"
        case debug = "Debug"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .dashboard: return "chart.bar.fill"
            case .chat: return "bubble.left.and.bubble.right.fill"
            case .memory: return "brain.head.profile"
            case .profile: return "brain.fill"
            case .settings: return "gearshape"
            case .debug: return "ladybug"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            let visibleTabs = Tab.allCases.filter { tab in
                tab != .debug || devModeEnabled
            }
            List(visibleTabs, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .frame(minWidth: 160)
        } detail: {
            switch selectedTab {
            case .dashboard:
                DashboardView()
            case .chat:
                ChatView()
            case .memory:
                MemoryListView()
            case .profile:
                ProfileTabView()
            case .settings:
                SettingsView()
            case .debug:
                DebugDashboardView()
            }
        }
        .frame(minWidth: 800, minHeight: 600)
    }

    // MARK: - Window Utilities

    /// Finds the main window by its identifier.
    static func findMainWindow() -> NSWindow? {
        NSApplication.shared.windows.first { window in
            window.identifier?.rawValue == MainWindowID.identifier
        }
    }

    /// Activates and brings the main window to front.
    static func showMainWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let window = findMainWindow() {
            window.makeKeyAndOrderFront(nil)
        }
    }
}

// MARK: - Profile Tab (sub-navigation between personality profile and knowledge graph)

struct ProfileTabView: View {
    @State private var selectedSubTab: SubTab = .profile

    enum SubTab: String, CaseIterable, Identifiable {
        case profile = "Personality"
        case knowledgeGraph = "Knowledge Graph"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedSubTab) {
                ForEach(SubTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            switch selectedSubTab {
            case .profile:
                PersonalityProfileView()
            case .knowledgeGraph:
                KnowledgeGraphView()
            }
        }
    }
}

#Preview {
    MainWindowView()
}
