import UIKit
import GoogleMaps

class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        configureGoogleMaps()
        return true
    }

    private func configureGoogleMaps() {
        // Load API key from configuration
        guard let apiKey = googleMapsAPIKey else {
            assertionFailure("Google Maps API key not found. Add GOOGLE_MAPS_API_KEY to Config.plist or environment.")
            return
        }
        GMSServices.provideAPIKey(apiKey)
    }

    /// Retrieves the Google Maps API key from configuration
    /// Priority: 1. Environment variable, 2. Config.plist, 3. Info.plist
    private var googleMapsAPIKey: String? {
        // Check environment variable first (for CI/CD)
        if let envKey = ProcessInfo.processInfo.environment["GOOGLE_MAPS_API_KEY"],
           !envKey.isEmpty {
            return envKey
        }

        // Check Config.plist (recommended for local development)
        if let configPath = Bundle.main.path(forResource: "Config", ofType: "plist"),
           let config = NSDictionary(contentsOfFile: configPath),
           let apiKey = config["GOOGLE_MAPS_API_KEY"] as? String,
           !apiKey.isEmpty,
           !apiKey.hasPrefix("YOUR_") {
            return apiKey
        }

        // Fallback to Info.plist
        if let apiKey = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_MAPS_API_KEY") as? String,
           !apiKey.isEmpty,
           !apiKey.hasPrefix("YOUR_") {
            return apiKey
        }

        return nil
    }
}
