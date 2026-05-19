import SwiftUI

// MARK: - App Tab

enum AppTab: Int, CaseIterable {
    case dashboard, files, media, settings

    var icon: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .files:     "folder"
        case .media:     "play.rectangle"
        case .settings:  "gear"
        }
    }
    var label: String {
        switch self {
        case .dashboard: "Tổng quan"
        case .files:     "Tệp"
        case .media:     "Media"
        case .settings:  "Cài đặt"
        }
    }
}

// MARK: - App State

enum AppState {
    case splash, login, main
}

// MARK: - Root View

struct ContentView: View {
    @State private var appState: AppState = .splash

    var body: some View {
        ZStack {
            switch appState {
            case .splash:
                SplashView {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        appState = .login
                    }
                }
            case .login:
                LoginView {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        appState = .main
                    }
                }
            case .main:
                MainShell(onDisconnect: {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        appState = .login
                    }
                })
            }
        }
    }
}

// MARK: - Main Shell (Native iOS TabView)

struct MainShell: View {
    var onDisconnect: (() -> Void)?

    @State private var selectedTab: AppTab = .dashboard

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                DashboardScreen(onDisconnect: onDisconnect)
            }
            .tabItem { Label(AppTab.dashboard.label, systemImage: AppTab.dashboard.icon) }
            .tag(AppTab.dashboard)

            NavigationStack {
                FileManagerScreen()
            }
            .tabItem { Label(AppTab.files.label, systemImage: AppTab.files.icon) }
            .tag(AppTab.files)

            NavigationStack {
                MediaHubScreen()
            }
            .tabItem { Label(AppTab.media.label, systemImage: AppTab.media.icon) }
            .tag(AppTab.media)

            NavigationStack {
                SettingsScreen(onDisconnect: onDisconnect)
            }
            .tabItem { Label(AppTab.settings.label, systemImage: AppTab.settings.icon) }
            .tag(AppTab.settings)
        }
        .tint(.blue)
    }
}
