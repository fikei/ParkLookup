# Quick Start: iOS TestFlight Deployment

Get up and running with automated iOS deployments in 5 steps.

## 1. Install Prerequisites

```bash
# Install GitHub CLI
brew install gh
gh auth login

# Install Fastlane
gem install fastlane

# Verify installation
fastlane --version
gh --version
```

## 2. Configure Apple Developer Credentials

### Get Your IDs

1. **Team ID**: Go to [Apple Developer Portal](https://developer.apple.com/account) → Membership → Team ID
2. **ITC Team ID**: Go to [App Store Connect](https://appstoreconnect.apple.com) → Users and Access → (your account)

### Create App Store Connect API Key

1. App Store Connect → Users and Access → Keys → App Store Connect API
2. Click "+" to create new key
3. Download the `.p8` file (⚠️ only shown once!)
4. Note the **Key ID** and **Issuer ID**

Create `SFParkingZoneFinder/fastlane/api_key.json`:
```json
{
  "key_id": "YOUR_KEY_ID",
  "issuer_id": "YOUR_ISSUER_ID",
  "key": "-----BEGIN PRIVATE KEY-----\nYOUR_P8_FILE_CONTENT\n-----END PRIVATE KEY-----"
}
```

## 3. Get Certificates and Profiles

```bash
cd SFParkingZoneFinder

# Generate certificate (follow prompts)
fastlane cert

# Download provisioning profile (follow prompts)
fastlane sigh

# Export certificate as .p12 from Keychain Access
# 1. Open Keychain Access
# 2. Find "Apple Distribution" certificate
# 3. Right-click → Export → Save as certificate.p12 (set password)
```

## 4. Configure GitHub Secrets

```bash
# Encode certificate
base64 -i certificate.p12 | pbcopy

# Encode provisioning profile
base64 -i ~/Library/MobileDevice/Provisioning\ Profiles/*.mobileprovision | pbcopy

# Generate keychain password
openssl rand -base64 32
```

Go to: **Your GitHub Repo → Settings → Secrets and variables → Actions**

Add these secrets:

| Secret | Value |
|--------|-------|
| `APP_STORE_CONNECT_API_KEY_CONTENT` | Paste content of `api_key.json` |
| `CERTIFICATE_P12` | Paste base64 encoded certificate |
| `CERTIFICATE_PASSWORD` | Your .p12 password |
| `PROVISIONING_PROFILE` | Paste base64 encoded profile |
| `KEYCHAIN_PASSWORD` | Generated password from above |
| `APPLE_ID` | your-email@example.com |
| `TEAM_ID` | Your Team ID from step 2 |
| `ITC_TEAM_ID` | Your ITC Team ID from step 2 |
| `APP_IDENTIFIER` | com.yourcompany.sfparkingzonefinder |
| `PROVISIONING_PROFILE_SPECIFIER` | Name of your provisioning profile |

## 5. Deploy!

### Option A: Claude Code Command (Easiest)

```bash
/deploy-ios
```

### Option B: Direct Script

```bash
./scripts/deploy-testflight.sh
```

### Option C: GitHub Actions UI

1. Go to Actions tab
2. Select "iOS TestFlight Deployment"
3. Click "Run workflow"
4. Choose branch and options
5. Click "Run workflow"

---

## What Happens Next?

1. ⏳ GitHub Actions builds your app (15-30 min)
2. 📤 Uploads to TestFlight
3. ⚙️ Apple processes the build (5-15 min)
4. ✅ Available to testers!

Monitor progress:
- GitHub Actions: `gh run watch`
- TestFlight: [App Store Connect](https://appstoreconnect.apple.com)

---

## Troubleshooting

**Build fails with signing error?**
- Check certificate and provisioning profile are valid
- Verify GitHub secrets are correct
- Re-encode and re-upload if needed

**Can't trigger workflow?**
- Ensure GitHub CLI is authenticated: `gh auth login`
- Check you have write access to the repository
- Verify workflow file exists: `.github/workflows/ios-testflight.yml`

**Need more help?**
- See full guide: `docs/iOS-Deployment-Guide.md`
- Setup checklist: `docs/iOS-Deployment-Setup-Checklist.md`

---

## Next Steps

- [ ] Test the deployment with `--skip-tests` for faster builds
- [ ] Set up TestFlight beta testers in App Store Connect
- [ ] Configure automatic deployments on push to main
- [ ] Add release notes to TestFlight builds
- [ ] Set up notifications for build status

**Happy Deploying! 🚀**
