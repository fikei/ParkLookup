# iOS TestFlight Deployment Guide

This guide explains how to deploy the SF Parking Zone Finder iOS app to TestFlight using our automated pipeline.

## Table of Contents

1. [Quick Start](#quick-start)
2. [Prerequisites](#prerequisites)
3. [Initial Setup](#initial-setup)
4. [Deploying to TestFlight](#deploying-to-testflight)
5. [GitHub Secrets Configuration](#github-secrets-configuration)
6. [Troubleshooting](#troubleshooting)

---

## Quick Start

Once setup is complete, deploying is as simple as:

```bash
# From Claude Code
/deploy-ios

# Or directly
./scripts/deploy-testflight.sh
```

---

## Prerequisites

### On Your Mac (for local testing)

1. **Xcode 15.0+** installed
2. **Homebrew** (for installing dependencies)
3. **Ruby 3.0+** (comes with macOS)
4. **Fastlane**:
   ```bash
   gem install fastlane
   ```
5. **GitHub CLI**:
   ```bash
   brew install gh
   gh auth login
   ```

### Apple Developer Account Requirements

1. **Apple Developer Program membership** ($99/year)
2. **App Store Connect access**
3. **App created in App Store Connect**
4. **Distribution certificate**
5. **App Store provisioning profile**

---

## Initial Setup

### 1. Apple Developer Configuration

#### Create App in App Store Connect

1. Log in to [App Store Connect](https://appstoreconnect.apple.com)
2. Go to "My Apps" → "+" → "New App"
3. Fill in app information:
   - Platform: iOS
   - Name: SF Parking Zone Finder
   - Bundle ID: `com.yourcompany.sfparkingzonefinder` (update this!)
   - SKU: Choose a unique identifier
   - User Access: Full Access

#### Create App Store Connect API Key

1. In App Store Connect, go to "Users and Access" → "Keys" → "App Store Connect API"
2. Click "+" to generate a new key
3. Name it (e.g., "GitHub Actions CI/CD")
4. Access: Choose "App Manager" or higher
5. Download the `.p8` key file (⚠️ only available once!)
6. Note the:
   - **Issuer ID** (UUID format)
   - **Key ID** (10-character string)

7. Create `api_key.json` with this format:
   ```json
   {
     "key_id": "YOUR_KEY_ID",
     "issuer_id": "YOUR_ISSUER_ID",
     "key": "-----BEGIN PRIVATE KEY-----\nYOUR_KEY_CONTENT\n-----END PRIVATE KEY-----"
   }
   ```

#### Generate Distribution Certificate

```bash
# On your Mac
cd SFParkingZoneFinder

# Generate certificate signing request
fastlane cert

# Or manually:
# 1. Open Keychain Access
# 2. Keychain Access → Certificate Assistant → Request a Certificate from a Certificate Authority
# 3. Save to disk
# 4. Upload to Apple Developer Portal → Certificates → "+"
# 5. Choose "iOS Distribution"
```

Export the certificate:
```bash
# Export as .p12
# In Keychain Access:
# 1. Find your distribution certificate
# 2. Right-click → Export
# 3. Save as .p12 with a password
# 4. Base64 encode it: base64 -i certificate.p12 -o certificate.p12.base64
```

#### Create Provisioning Profile

```bash
# Using fastlane
fastlane sigh

# Or manually in Apple Developer Portal:
# 1. Go to Profiles → "+"
# 2. Choose "App Store"
# 3. Select your App ID
# 4. Select your distribution certificate
# 5. Download the profile
# 6. Base64 encode: base64 -i profile.mobileprovision -o profile.mobileprovision.base64
```

### 2. Configure Fastlane Locally

```bash
cd SFParkingZoneFinder/fastlane

# Copy the environment template
cp .env.default .env

# Edit .env with your values
nano .env
```

Fill in your `.env`:
```bash
APPLE_ID=your-apple-id@example.com
TEAM_ID=YOUR_TEAM_ID              # Found in Apple Developer Portal
ITC_TEAM_ID=YOUR_ITC_TEAM_ID      # Found in App Store Connect
APP_IDENTIFIER=com.yourcompany.sfparkingzonefinder
PROVISIONING_PROFILE_SPECIFIER=match AppStore com.yourcompany.sfparkingzonefinder
APP_STORE_CONNECT_API_KEY_PATH=./fastlane/api_key.json
```

Place your `api_key.json` in `SFParkingZoneFinder/fastlane/`

### 3. Test Locally

```bash
cd SFParkingZoneFinder

# Install dependencies
bundle install

# Test the build
fastlane build

# Test deployment (will upload to TestFlight)
fastlane beta
```

### 4. Configure GitHub Secrets

Go to your GitHub repository → Settings → Secrets and variables → Actions

Add the following secrets:

| Secret Name | Description | How to Get |
|------------|-------------|------------|
| `APP_STORE_CONNECT_API_KEY_CONTENT` | App Store Connect API key JSON | Content of `api_key.json` |
| `CERTIFICATE_P12` | Distribution certificate in base64 | `base64 -i certificate.p12` |
| `CERTIFICATE_PASSWORD` | Password for the .p12 file | Password you set when exporting |
| `PROVISIONING_PROFILE` | Provisioning profile in base64 | `base64 -i profile.mobileprovision` |
| `KEYCHAIN_PASSWORD` | Random secure password | Generate with `openssl rand -base64 32` |
| `APPLE_ID` | Your Apple ID email | Your Apple Developer email |
| `TEAM_ID` | Apple Developer Team ID | Found in Apple Developer Portal |
| `ITC_TEAM_ID` | App Store Connect Team ID | Found in App Store Connect |
| `APP_IDENTIFIER` | Your app's bundle identifier | e.g., `com.yourcompany.sfparkingzonefinder` |
| `PROVISIONING_PROFILE_SPECIFIER` | Provisioning profile name | Name shown in Xcode or Apple Developer Portal |

---

## Deploying to TestFlight

### Method 1: Claude Code Slash Command (Recommended)

```bash
/deploy-ios
```

This will:
1. Show deployment configuration
2. Ask for confirmation
3. Trigger the GitHub Actions workflow
4. Provide monitoring links

### Method 2: Run Script Directly

```bash
# Basic deployment
./scripts/deploy-testflight.sh

# Skip tests (faster)
./scripts/deploy-testflight.sh --skip-tests

# Deploy to production
./scripts/deploy-testflight.sh --environment production

# Deploy from specific branch
./scripts/deploy-testflight.sh --branch main
```

### Method 3: GitHub Actions Web UI

1. Go to your repository on GitHub
2. Click "Actions" tab
3. Select "iOS TestFlight Deployment" workflow
4. Click "Run workflow" button
5. Choose options:
   - Branch to deploy from
   - Skip tests (true/false)
   - Environment (beta/production)
6. Click "Run workflow"

### Method 4: GitHub CLI

```bash
# Trigger workflow
gh workflow run ios-testflight.yml --ref main

# With options
gh workflow run ios-testflight.yml \
  --ref main \
  -f skip_tests=false \
  -f environment=beta

# Watch the run
gh run watch
```

### Method 5: Automatic on Push

The workflow is configured to automatically trigger when you push to `main` branch with changes to the iOS app:

```bash
git add .
git commit -m "Update iOS app"
git push origin main
```

To disable auto-deployment, remove the `push:` trigger from `.github/workflows/ios-testflight.yml`.

---

## Deployment Process

When you trigger a deployment, here's what happens:

1. **Checkout Code** - Fetches the latest code from the specified branch
2. **Setup Environment** - Configures Xcode, Ruby, and Fastlane
3. **Install Dependencies** - Installs required gems and tools
4. **Setup Credentials** - Configures certificates and provisioning profiles
5. **Run Tests** (optional) - Executes unit and UI tests
6. **Increment Build Number** - Automatically bumps the build number
7. **Build App** - Compiles and archives the app
8. **Upload to TestFlight** - Submits to App Store Connect
9. **Commit Version Bump** - Commits the new build number
10. **Push Changes** - Pushes the version bump to the repository

The entire process typically takes **15-30 minutes**.

---

## Monitoring Deployments

### View in GitHub Actions

1. Go to Actions tab in your repository
2. See all workflow runs and their status
3. Click on a run to see detailed logs

### Watch with GitHub CLI

```bash
# List recent runs
gh run list --workflow=ios-testflight.yml

# Watch the latest run
gh run watch

# View logs
gh run view --log
```

### TestFlight Processing

After upload:
1. Go to [App Store Connect](https://appstoreconnect.apple.com)
2. Select your app → TestFlight
3. Processing typically takes 5-15 minutes
4. Once complete, it's available to testers

---

## Troubleshooting

### Build Fails: Code Signing Issues

**Error**: "No profile matching 'X' found"

**Solution**:
1. Verify `PROVISIONING_PROFILE_SPECIFIER` matches the profile name exactly
2. Re-download and re-encode the provisioning profile
3. Update GitHub secret `PROVISIONING_PROFILE`

### Build Fails: Certificate Issues

**Error**: "No certificate matching 'X' found"

**Solution**:
1. Check certificate is valid in Apple Developer Portal
2. Verify .p12 export includes private key
3. Re-export and re-encode the certificate
4. Update GitHub secret `CERTIFICATE_P12`

### Build Fails: API Key Issues

**Error**: "Invalid API Key"

**Solution**:
1. Verify `api_key.json` format is correct
2. Check Key ID and Issuer ID match
3. Ensure private key is properly formatted (with line breaks)
4. Regenerate API key if necessary

### Workflow Not Triggering

**Solution**:
1. Check GitHub Actions are enabled for your repository
2. Verify workflow file is in `.github/workflows/`
3. Check workflow YAML syntax
4. Ensure you have permissions to trigger workflows

### TestFlight Upload Succeeds But Not Visible

**Reasons**:
1. Still processing (wait 5-15 minutes)
2. Build rejected (check email from Apple)
3. Missing compliance information (check App Store Connect)

### Need to Debug Locally

```bash
cd SFParkingZoneFinder

# Enable verbose mode
fastlane beta --verbose

# Check Xcode configuration
xcodebuild -list -project SFParkingZoneFinder.xcodeproj

# Verify signing
codesign --verify --verbose ./build/SFParkingZoneFinder.app
```

---

## Best Practices

1. **Always test locally first** before pushing to CI/CD
2. **Use semantic versioning** for your app version
3. **Write meaningful commit messages** for version bumps
4. **Monitor TestFlight builds** in App Store Connect
5. **Keep secrets secure** - never commit certificates or keys
6. **Rotate API keys** periodically for security
7. **Review build logs** to catch issues early
8. **Set up notifications** for failed deployments

---

## File Structure

```
ParkLookup/
├── .github/
│   └── workflows/
│       └── ios-testflight.yml          # GitHub Actions workflow
├── SFParkingZoneFinder/
│   ├── fastlane/
│   │   ├── Fastfile                    # Fastlane lanes
│   │   ├── Appfile                     # App configuration
│   │   ├── .env.default                # Environment template
│   │   ├── .env                        # Your secrets (gitignored)
│   │   └── api_key.json               # App Store Connect API key (gitignored)
│   └── Gemfile                        # Ruby dependencies
├── scripts/
│   └── deploy-testflight.sh           # Deployment script
└── docs/
    └── iOS-Deployment-Guide.md        # This file
```

---

## Additional Resources

- [Fastlane Documentation](https://docs.fastlane.tools/)
- [App Store Connect Help](https://developer.apple.com/app-store-connect/)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [TestFlight Documentation](https://developer.apple.com/testflight/)
- [Code Signing Guide](https://codesigning.guide/)

---

## Support

If you encounter issues:

1. Check the [Troubleshooting](#troubleshooting) section
2. Review GitHub Actions logs
3. Check Fastlane output with `--verbose` flag
4. Verify all secrets are correctly configured
5. Consult Apple Developer forums

---

**Happy Deploying! 🚀**
