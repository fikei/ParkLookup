# iOS TestFlight Deployment Setup Checklist

Use this checklist to ensure you have everything configured correctly for automated iOS deployments.

## Prerequisites Checklist

- [ ] Mac with Xcode 15.0+ installed
- [ ] Apple Developer Program membership ($99/year)
- [ ] GitHub CLI installed (`brew install gh`)
- [ ] Fastlane installed (`gem install fastlane`)
- [ ] Ruby 3.0+ installed

## Apple Developer Portal Setup

### App Store Connect

- [ ] App created in App Store Connect
  - [ ] App name: SF Parking Zone Finder
  - [ ] Bundle ID configured: `com.yourcompany.sfparkingzonefinder`
  - [ ] App information filled out

### API Key Creation

- [ ] App Store Connect API key generated
  - [ ] Key downloaded (.p8 file)
  - [ ] Key ID noted (10 characters)
  - [ ] Issuer ID noted (UUID format)
  - [ ] `api_key.json` created with correct format
  - [ ] API key stored securely

### Certificates

- [ ] Distribution certificate created
  - [ ] Certificate downloaded from Apple Developer Portal
  - [ ] Certificate exported as .p12 with password
  - [ ] .p12 file base64 encoded
  - [ ] Certificate password saved

### Provisioning Profiles

- [ ] App Store provisioning profile created
  - [ ] Profile name noted
  - [ ] Profile downloaded (.mobileprovision)
  - [ ] Profile base64 encoded

## Local Configuration

- [ ] `SFParkingZoneFinder/fastlane/.env` file created from `.env.default`
- [ ] All values in `.env` filled out:
  - [ ] `APPLE_ID`
  - [ ] `TEAM_ID`
  - [ ] `ITC_TEAM_ID`
  - [ ] `APP_IDENTIFIER`
  - [ ] `PROVISIONING_PROFILE_SPECIFIER`
- [ ] `api_key.json` placed in `SFParkingZoneFinder/fastlane/`
- [ ] Ruby dependencies installed (`bundle install`)

## Local Testing

- [ ] Build runs successfully: `fastlane build`
- [ ] Test deployment works: `fastlane beta` (⚠️ uploads to TestFlight)

## GitHub Secrets Configuration

Go to: Repository → Settings → Secrets and variables → Actions → New repository secret

- [ ] `APP_STORE_CONNECT_API_KEY_CONTENT` - Full content of `api_key.json`
- [ ] `CERTIFICATE_P12` - Base64 encoded .p12 file
- [ ] `CERTIFICATE_PASSWORD` - Password for the .p12 file
- [ ] `PROVISIONING_PROFILE` - Base64 encoded .mobileprovision file
- [ ] `KEYCHAIN_PASSWORD` - Random secure password (generate with `openssl rand -base64 32`)
- [ ] `APPLE_ID` - Your Apple Developer email
- [ ] `TEAM_ID` - Apple Developer Team ID
- [ ] `ITC_TEAM_ID` - App Store Connect Team ID
- [ ] `APP_IDENTIFIER` - App bundle identifier
- [ ] `PROVISIONING_PROFILE_SPECIFIER` - Provisioning profile name

## GitHub Actions Verification

- [ ] Workflow file exists: `.github/workflows/ios-testflight.yml`
- [ ] Workflow visible in Actions tab
- [ ] Can trigger workflow manually

## Deployment Script

- [ ] Script exists: `scripts/deploy-testflight.sh`
- [ ] Script is executable (`chmod +x`)
- [ ] Can run script: `./scripts/deploy-testflight.sh --help`

## Claude Code Integration

- [ ] Slash command exists: `.claude/commands/deploy-ios.md`
- [ ] Can run: `/deploy-ios` from Claude Code

## Test Deployment

- [ ] Trigger a test deployment:
  - [ ] Option 1: Run `/deploy-ios` in Claude Code
  - [ ] Option 2: Run `./scripts/deploy-testflight.sh`
  - [ ] Option 3: Trigger via GitHub Actions UI
- [ ] Workflow runs successfully
- [ ] Build appears in TestFlight
- [ ] Version bump is committed and pushed

## Post-Deployment Verification

- [ ] Check App Store Connect → TestFlight
- [ ] Build is processing or available
- [ ] Build number incremented
- [ ] No errors in GitHub Actions logs
- [ ] Repository has new commit with version bump

## Documentation Review

- [ ] Read `docs/iOS-Deployment-Guide.md`
- [ ] Understand deployment process
- [ ] Know how to troubleshoot common issues
- [ ] Bookmarked relevant Apple Developer resources

## Security Checklist

- [ ] `.env` file is gitignored
- [ ] `api_key.json` is gitignored
- [ ] No secrets committed to repository
- [ ] GitHub secrets are properly configured
- [ ] Certificate .p12 file deleted after base64 encoding
- [ ] Local copies of sensitive files secured

## Team Onboarding (if applicable)

- [ ] Team members have Apple Developer access
- [ ] Team members have GitHub repository access
- [ ] Team members can trigger deployments
- [ ] Team members trained on deployment process
- [ ] Emergency contact list created

---

## Quick Reference Commands

### Local Testing
```bash
cd SFParkingZoneFinder
bundle install
fastlane build
fastlane test
fastlane beta
```

### Deployment
```bash
# Claude Code
/deploy-ios

# Direct script
./scripts/deploy-testflight.sh
./scripts/deploy-testflight.sh --skip-tests

# GitHub CLI
gh workflow run ios-testflight.yml --ref main
gh run watch
```

### Encoding Files for GitHub Secrets
```bash
# Certificate
base64 -i certificate.p12 | pbcopy

# Provisioning Profile
base64 -i profile.mobileprovision | pbcopy

# Generate keychain password
openssl rand -base64 32
```

---

## When Everything is Checked ✅

You're ready to deploy! Run:

```bash
/deploy-ios
```

or

```bash
./scripts/deploy-testflight.sh
```

---

## Need Help?

Refer to:
- `docs/iOS-Deployment-Guide.md` - Full deployment guide
- Fastlane docs: https://docs.fastlane.tools/
- GitHub Actions logs in your repository
