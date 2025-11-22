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
                // TODO: Replace with OnboardingContainerView
                OnboardingPlaceholderView(onComplete: {
                    hasCompletedOnboarding = true
                })
            }
        }
    }
}

/// Temporary onboarding placeholder until proper onboarding is built
struct OnboardingPlaceholderView: View {
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "car.fill")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            Text("SF Parking Zone Finder")
                .font(.title)
                .fontWeight(.bold)

            Text("Find out if your permit is valid at your current location")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Get Started") {
                onComplete()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
    }
}

#Preview {
    ContentView()
        .environmentObject(DependencyContainer.shared)
}
