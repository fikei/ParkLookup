import SwiftUI

/// Container view managing onboarding flow navigation
struct OnboardingContainerView: View {
    @StateObject private var viewModel = OnboardingViewModel()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        ZStack {
            // Content based on current step
            Group {
                switch viewModel.currentStep {
                case .welcome:
                    WelcomeView(onContinue: viewModel.nextStep)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing),
                            removal: .move(edge: .leading)
                        ))

                case .locationPermission:
                    LocationPermissionView(
                        locationStatus: viewModel.locationStatus,
                        isRequesting: viewModel.isRequestingLocation,
                        onRequestPermission: viewModel.requestLocationPermission,
                        onContinue: viewModel.nextStep
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .leading)
                    ))

                case .permitSetup:
                    PermitSetupView(
                        selectedAreas: $viewModel.selectedPermitAreas,
                        onContinue: viewModel.nextStep,
                        onSkip: viewModel.skipPermitSetup
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .leading)
                    ))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: viewModel.currentStep)

            // Progress indicator
            VStack {
                ProgressIndicator(
                    currentStep: viewModel.currentStep.rawValue,
                    totalSteps: OnboardingStep.allCases.count
                )
                .padding(.top, 16)

                Spacer()
            }
        }
        .onChange(of: hasCompletedOnboarding) { _, newValue in
            // This will trigger ContentView to show MainResultView
        }
    }
}

// MARK: - Progress Indicator

struct ProgressIndicator: View {
    let currentStep: Int
    let totalSteps: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Capsule()
                    .fill(index <= currentStep ? Color.accentColor : Color(.systemGray4))
                    .frame(width: index == currentStep ? 24 : 8, height: 8)
                    .animation(.easeInOut(duration: 0.2), value: currentStep)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingContainerView()
}
