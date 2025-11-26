Execute the iOS TestFlight deployment script:

```bash
./scripts/deploy-testflight.sh
```

This command will:
1. Show the deployment configuration (branch, environment, etc.)
2. Ask for confirmation before proceeding
3. Trigger the GitHub Actions workflow for building and deploying to TestFlight
4. Provide links to monitor the deployment progress

You can also run with options:
- `./scripts/deploy-testflight.sh --skip-tests` - Skip running tests
- `./scripts/deploy-testflight.sh --environment production` - Deploy to production
- `./scripts/deploy-testflight.sh --branch main` - Deploy from a specific branch
