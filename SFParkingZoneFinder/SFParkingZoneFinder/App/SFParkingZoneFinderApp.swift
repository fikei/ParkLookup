import SwiftUI

@main
struct SFParkingZoneFinderApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var dependencyContainer = DependencyContainer.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dependencyContainer)
        }
    }
}

/// Root view handling navigation between onboarding and main app
struct ContentView: View {
    @EnvironmentObject var container: DependencyContainer
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                MainResultView()
            } else {
                OnboardingContainerView()
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(DependencyContainer.shared)
}
