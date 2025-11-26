# Deployment Scripts

This directory contains automation scripts for the ParkLookup project.

## Available Scripts

### `deploy-testflight.sh`

Triggers the iOS TestFlight deployment pipeline via GitHub Actions.

**Usage:**
```bash
./scripts/deploy-testflight.sh [OPTIONS]
```

**Options:**
- `--skip-tests` - Skip running tests before deployment
- `--environment ENV` - Deployment environment (beta|production) [default: beta]
- `--branch BRANCH` - Branch to deploy from [default: current branch]
- `-h, --help` - Show help message

**Examples:**
```bash
# Deploy from current branch
./scripts/deploy-testflight.sh

# Deploy without running tests (faster)
./scripts/deploy-testflight.sh --skip-tests

# Deploy to production
./scripts/deploy-testflight.sh --environment production

# Deploy from main branch, skip tests
./scripts/deploy-testflight.sh --branch main --skip-tests
```

**Prerequisites:**
- GitHub CLI installed and authenticated (`gh auth login`)
- Repository secrets configured (see `docs/iOS-Deployment-Guide.md`)

**What it does:**
1. Shows deployment configuration
2. Asks for confirmation
3. Triggers GitHub Actions workflow
4. Provides links to monitor progress

## Quick Access via Claude Code

You can also trigger deployments using the slash command:

```bash
/deploy-ios
```

This runs the `deploy-testflight.sh` script.

## Related Documentation

- [iOS Deployment Guide](../docs/iOS-Deployment-Guide.md) - Complete deployment documentation
- [Quick Start Guide](../docs/Quick-Start-iOS-Deployment.md) - Get started in 5 steps
- [Setup Checklist](../docs/iOS-Deployment-Setup-Checklist.md) - Ensure everything is configured

## Adding New Scripts

When adding new scripts to this directory:

1. Make them executable: `chmod +x scripts/your-script.sh`
2. Add usage documentation in this README
3. Consider creating a Claude Code slash command in `.claude/commands/`
4. Add error handling and helpful output messages
5. Follow the existing script patterns for consistency

## Troubleshooting

If the script fails:

1. Check GitHub CLI authentication: `gh auth status`
2. Verify repository permissions
3. Check GitHub Actions workflow exists: `.github/workflows/ios-testflight.yml`
4. Review the help output: `./scripts/deploy-testflight.sh --help`

For deployment issues, see the full troubleshooting guide in `docs/iOS-Deployment-Guide.md`.
