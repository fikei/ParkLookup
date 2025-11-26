#!/bin/bash

# iOS TestFlight Deployment Script
# This script triggers the GitHub Actions workflow for iOS TestFlight deployment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
WORKFLOW_FILE="ios-testflight.yml"
DEFAULT_BRANCH="main"
REPO_OWNER=$(git config --get remote.origin.url | sed -n 's/.*github.com[:/]\([^/]*\).*/\1/p')
REPO_NAME=$(git config --get remote.origin.url | sed -n 's/.*\/\([^.]*\).*/\1/p')

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}   iOS TestFlight Deployment Script${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# Parse arguments
SKIP_TESTS="false"
ENVIRONMENT="beta"
BRANCH=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --skip-tests)
      SKIP_TESTS="true"
      shift
      ;;
    --environment)
      ENVIRONMENT="$2"
      shift 2
      ;;
    --branch)
      BRANCH="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --skip-tests           Skip running tests before deployment"
      echo "  --environment ENV      Deployment environment (beta|production) [default: beta]"
      echo "  --branch BRANCH        Branch to deploy from [default: current branch]"
      echo "  -h, --help             Show this help message"
      echo ""
      echo "Examples:"
      echo "  $0                                    # Deploy from current branch"
      echo "  $0 --skip-tests                       # Deploy without running tests"
      echo "  $0 --environment production           # Deploy to production"
      echo "  $0 --branch main --skip-tests        # Deploy from main, skip tests"
      exit 0
      ;;
    *)
      echo -e "${RED}Error: Unknown option: $1${NC}"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

# Get current branch if not specified
if [ -z "$BRANCH" ]; then
  BRANCH=$(git rev-parse --abbrev-ref HEAD)
fi

echo -e "${YELLOW}Configuration:${NC}"
echo -e "  Repository: ${BLUE}$REPO_OWNER/$REPO_NAME${NC}"
echo -e "  Branch: ${BLUE}$BRANCH${NC}"
echo -e "  Environment: ${BLUE}$ENVIRONMENT${NC}"
echo -e "  Skip Tests: ${BLUE}$SKIP_TESTS${NC}"
echo ""

# Check if gh CLI is installed
if ! command -v gh &> /dev/null; then
  echo -e "${RED}Error: GitHub CLI (gh) is not installed${NC}"
  echo -e "Install it with: ${BLUE}brew install gh${NC}"
  echo -e "Or visit: https://cli.github.com/"
  exit 1
fi

# Check if authenticated
if ! gh auth status &> /dev/null; then
  echo -e "${RED}Error: Not authenticated with GitHub CLI${NC}"
  echo -e "Run: ${BLUE}gh auth login${NC}"
  exit 1
fi

# Confirm deployment
echo -e "${YELLOW}⚠️  This will trigger a TestFlight deployment${NC}"
read -p "Continue? (y/N) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo -e "${YELLOW}Deployment cancelled${NC}"
  exit 0
fi

echo ""
echo -e "${GREEN}🚀 Triggering GitHub Actions workflow...${NC}"
echo ""

# Trigger the workflow
gh workflow run "$WORKFLOW_FILE" \
  --ref "$BRANCH" \
  -f skip_tests="$SKIP_TESTS" \
  -f environment="$ENVIRONMENT"

if [ $? -eq 0 ]; then
  echo ""
  echo -e "${GREEN}✅ Workflow triggered successfully!${NC}"
  echo ""
  echo -e "${BLUE}Monitor the deployment:${NC}"
  echo -e "  Web: https://github.com/$REPO_OWNER/$REPO_NAME/actions"
  echo -e "  CLI: ${BLUE}gh run list --workflow=$WORKFLOW_FILE${NC}"
  echo ""
  echo -e "${BLUE}Watch the latest run:${NC}"
  echo -e "  ${BLUE}gh run watch${NC}"
  echo ""
else
  echo -e "${RED}❌ Failed to trigger workflow${NC}"
  exit 1
fi
