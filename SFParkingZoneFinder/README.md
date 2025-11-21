# SF Parking Zone Finder

An iOS application that helps San Francisco residents instantly understand parking regulations at their current location.

## Features

- **Instant Zone Detection**: Know which parking zone you're in
- **Permit Validation**: See if your residential parking permit is valid
- **Rule Summaries**: Human-readable parking rules and restrictions
- **Floating Map**: Visual zone context with expandable full-screen map

## Requirements

- iOS 16.0+
- Xcode 15.0+
- Google Maps API Key

## Setup

### 1. Clone the repository

```bash
git clone <repository-url>
cd SFParkingZoneFinder
```

### 2. Configure Google Maps API Key

1. Copy the template config file:
   ```bash
   cp SFParkingZoneFinder/Resources/Config.plist.template SFParkingZoneFinder/Resources/Config.plist
   ```

2. Edit `Config.plist` and replace `YOUR_GOOGLE_MAPS_API_KEY_HERE` with your actual API key

3. Get a Google Maps API key from [Google Cloud Console](https://console.cloud.google.com/):
   - Enable "Maps SDK for iOS"
   - Create an API key
   - Restrict to your bundle ID (recommended)

### 3. Open in Xcode

```bash
open SFParkingZoneFinder.xcodeproj
```

Or if using Swift Package Manager workspace:
```bash
open Package.swift
```

### 4. Add Google Maps SDK

In Xcode:
1. File > Add Package Dependencies
2. Enter: `https://github.com/nicklockwood/GoogleMaps-iOS-SDK` (or use CocoaPods)
3. Add to your target

### 5. Build and Run

Select your target device/simulator and press ⌘R

## Architecture

- **SwiftUI** + **MVVM**
- Protocol-oriented design for testability
- Dependency injection via `DependencyContainer`

### Project Structure

```
SFParkingZoneFinder/
├── App/                    # App entry point, delegates
├── Features/               # Feature modules (Main, Map, Onboarding, Settings)
├── Core/
│   ├── Services/          # Business logic services
│   ├── Models/            # Data models
│   ├── Protocols/         # Service abstractions
│   └── Extensions/        # Swift extensions
├── Data/
│   ├── Local/             # Mock data source
│   ├── Cache/             # Caching layer
│   └── Repositories/      # Data access
└── Resources/             # JSON data, assets
```

## Documentation

See `/docs` folder for:
- `ProductBrief.md` - Product requirements
- `TechnicalArchitecture.md` - System design
- `EngineeringProjectPlan.md` - Implementation roadmap
- `ImplementationChecklist.md` - Task tracking

## License

[License information]

## Contributing

[Contribution guidelines]
