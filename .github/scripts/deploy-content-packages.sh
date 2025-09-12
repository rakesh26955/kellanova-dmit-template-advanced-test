#!/bin/sh
set -euo pipefail

# Deploy content wrapper script
# Usage:
#   ./deploy-content.sh <WORKSPACE> <GROUP> <PROJECT> <ENVIRONMENT> <INSTANCE> <POOL>
#
# Args:
#   $1 = WORKSPACE (directory containing package zip files)
#   $2 = Group (agency|partner or similar)
#   $3 = ProjectName (output etc.)
#   $4 = Environment (dev|stg|prd|devqa|prv|uatkfr etc.)
#   $5 = Instance (author|publish|both)
#   $6 = Pool (kstl|kfr|gen|dam etc.)
#
# Environment variables (optional):
#   DEPLOY_SCRIPT     -> path to deploy-package script to call for each package
#                        default: "$GITHUB_WORKSPACE/temp/.github/scripts/deploy-package-filter.sh"
#   DEBUG             -> if "true" the script will only print actions (dry-run)
#
# Example:
#   export DEPLOY_SCRIPT=/path/to/deploy-package-filter.sh
#   ./deploy-content.sh /home/jenkins/workspace/ui/target agency output dev author kstl

help() {
    cat <<EOF
Usage: $0 <WORKSPACE> <GROUP> <PROJECT> <ENVIRONMENT> <INSTANCE> <POOL>
Example: $0 /var/lib/build/workspace/mygroup/ui target agency output dev author kstl

Environment variables:
  DEPLOY_SCRIPT  - full path to per-package deploy script (default: \$GITHUB_WORKSPACE/temp/.github/scripts/deploy-package-filter.sh)
  DEBUG          - if set to "true" do a dry-run (commands printed but not executed)
EOF
    exit 1
}

# support --help flags
if [ "$#" -eq 1 ]; then
    case "$1" in
        --help|-h|-help) help ;;
    esac
fi

# require exactly 6 args
if [ "$#" -ne 6 ]; then
    echo "ERROR: invalid number of arguments."
    help
fi

WORKSPACE=$1
GROUP=$2
PROJECT=$3
ENVIRONMENT=$4
INSTANCE=$5
POOL=$6

# Default path to per-package deploy script (can be overridden)
: "${DEPLOY_SCRIPT:=${GITHUB_WORKSPACE:-}/temp/.github/scripts/deploy-package-filter.sh}"
DEBUG=${DEBUG:-false}

# Validate inputs
[ -n "$WORKSPACE" ] || { echo "ERROR: WORKSPACE is empty"; exit 1; }
[ -d "$WORKSPACE" ] || { echo "ERROR: WORKSPACE directory not found: $WORKSPACE"; exit 1; }

if [ ! -x "$DEPLOY_SCRIPT" ]; then
    echo "WARNING: DEPLOY_SCRIPT not executable or not found at: $DEPLOY_SCRIPT"
    echo "If the script exists but is not executable, run: chmod +x $DEPLOY_SCRIPT"
    # do not fail here if user intentionally wants to only list packages; we will fail later on attempt to call
fi

echo "INFO: workspace: $WORKSPACE"
echo "INFO: group: $GROUP"
echo "INFO: project: $PROJECT"
echo "INFO: environment: $ENVIRONMENT"
echo "INFO: instance: $INSTANCE"
echo "INFO: pool: $POOL"
echo "INFO: deploy script: $DEPLOY_SCRIPT"
echo "INFO: debug mode: $DEBUG"
echo

# Gather zip packages safely using find (handles spaces/newlines)
PACKAGES_FOUND=0

# Use a subshell to iterate with NUL-separated filenames
find "$WORKSPACE" -maxdepth 1 -type f -name '*.zip' -print0 | while IFS= read -r -d '' pkgfile; do
    PACKAGES_FOUND=$((PACKAGES_FOUND + 1))
    pkgbase=$(basename "$pkgfile")
    packagename=${pkgbase%.zip}

    echo "-----------------------------"
    echo "Processing package: $pkgbase"
    echo "Package base name: $packagename"
    echo "Calling deploy script with: workspace='$WORKSPACE' package='$packagename' group='$GROUP' project='$PROJECT' environment='$ENVIRONMENT' instance='$INSTANCE' pool='$POOL'"
    echo "Command: bash \"$DEPLOY_SCRIPT\" \"$WORKSPACE\" \"$packagename\" \"$GROUP\" \"$PROJECT\" \"$ENVIRONMENT\" \"$INSTANCE\" \"$POOL\""
    if [ "$DEBUG" = "true" ]; then
        echo "[DEBUG] Skipping actual execution because DEBUG=true"
    else
        if [ ! -x "$DEPLOY_SCRIPT" ]; then
            echo "ERROR: Deploy script not found or not executable at: $DEPLOY_SCRIPT"
            exit 1
        fi
        # Execute the deploy script (use bash to preserve original behavior)
        bash "$DEPLOY_SCRIPT" "$WORKSPACE" "$packagename" "$GROUP" "$PROJECT" "$ENVIRONMENT" "$INSTANCE" "$POOL"
        rc=$?
        if [ "$rc" -ne 0 ]; then
            echo "ERROR: Deploy script failed for package $packagename with exit code $rc"
            exit $rc
        fi
    fi
done

# find runs in a subshell; PACKAGES_FOUND won't be updated in parent. Recompute with a simple check:
# (this avoids relying on the while loop's counter)
count=$(find "$WORKSPACE" -maxdepth 1 -type f -name '*.zip' | wc -l | tr -d '[:space:]' || echo 0)
if [ "$count" -eq 0 ]; then
    echo "ERROR: no packages found in $WORKSPACE"
    exit 1
fi

echo "INFO: processed $count package(s) from $WORKSPACE"
echo "Done."
exit 0
