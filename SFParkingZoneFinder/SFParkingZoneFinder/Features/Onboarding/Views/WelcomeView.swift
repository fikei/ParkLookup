import SwiftUI

/// First onboarding screen with app branding and introduction
struct WelcomeView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // App Icon / Illustration
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 160, height: 160)

                Image(systemName: "car.fill")
                    .font(.system(size: 72))
                    .foregroundColor(.accentColor)
            }
            .padding(.bottom, 40)

            // Title
            Text("SF Parking\nZone Finder")
                .font(.system(size: 36, weight: .bold))
                .multilineTextAlignment(.center)
                .padding(.bottom, 16)

            // Tagline
            Text("Instantly know if your permit\nis valid where you're parked")
                .font(.title3)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            // Features list
            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(
                    icon: "location.fill",
                    title: "Location-Based",
                    description: "Uses GPS to find your zone"
                )
                FeatureRow(
                    icon: "checkmark.circle.fill",
                    title: "Instant Answers",
                    description: "Valid or not, at a glance"
                )
                FeatureRow(
                    icon: "clock.fill",
                    title: "Time Restrictions",
                    description: "See parking rules and limits"
                )
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)

            // Continue Button
            Button(action: onContinue) {
                Text("Get Started")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.accentColor)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .background(Color(.systemBackground))
    }
}

// MARK: - Feature Row

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    WelcomeView(onContinue: {})
}
