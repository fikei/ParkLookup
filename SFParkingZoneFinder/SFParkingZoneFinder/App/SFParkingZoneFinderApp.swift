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

    @State private var isLoading = true
    @State private var loadingStatus = "Starting up..."

    var body: some View {
        Group {
            if isLoading {
                LaunchLoadingView(status: loadingStatus)
            } else if hasCompletedOnboarding {
                MainResultView()
            } else {
                OnboardingContainerView()
            }
        }
        .task {
            await preloadData()
        }
    }

    private func preloadData() async {
        loadingStatus = "Loading parking zones..."

        // Preload zones so the lookup engine is ready
        do {
            _ = try await container.zoneRepository.getZones(for: .sanFrancisco)
            loadingStatus = "Ready!"

            // Brief delay to show "Ready!" state
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
        } catch {
            loadingStatus = "Ready"
        }

        withAnimation(.easeOut(duration: 0.3)) {
            isLoading = false
        }
    }
}

// MARK: - Launch Loading View

struct LaunchLoadingView: View {
    let status: String

    @State private var isPulsing = false

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color.blue.opacity(0.8), Color.blue],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // App icon placeholder
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 120, height: 120)
                        .scaleEffect(isPulsing ? 1.1 : 1.0)

                    Image(systemName: "car.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.white)
                }

                // App name
                VStack(spacing: 8) {
                    Text("SF Parking")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text("Zone Finder")
                        .font(.system(size: 24, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                }

                Spacer()

                // Loading indicator and status
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.2)

                    Text(status)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(.bottom, 60)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(DependencyContainer.shared)
}

#Preview("Loading") {
    LaunchLoadingView(status: "Loading parking zones...")
}
