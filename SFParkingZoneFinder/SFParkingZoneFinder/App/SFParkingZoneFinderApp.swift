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

/// Temporary root view - will be replaced with proper navigation
struct ContentView: View {
    @EnvironmentObject var container: DependencyContainer
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                // TODO: Replace with MainResultView
                Text("Main Result View")
                    .font(.title)
            } else {
                // TODO: Replace with OnboardingContainerView
                Text("Onboarding")
                    .font(.title)
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(DependencyContainer.shared)
}
