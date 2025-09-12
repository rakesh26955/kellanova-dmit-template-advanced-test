#!/usr/bin/env bash
set -euo pipefail

# deploy-content-packages.sh
# Strict, no hardcoded operational values inside the script.
# Usage:
#   bash .github/scripts/deploy-content-packages.sh <WorkspacePath> <Group> <Project> <Environment> <Instance> <Pool> [debug]
# The deploy-package-filter.sh script must be present in the same directory as this script.
# The script relies on SERVER_CONFIG env (optional). If SERVER_CONFIG is not set it will use "config/server.properties".

die(){ echo "ERROR: $*" >&2; exit 1; }
info(){ echo "INFO: $*"; }

# --- config file (no internal magic defaults) ---
if [ -n "${SERVER_CONFIG:-}" ]; then
  CONFIG_FILE="${SERVER_CONFIG}"
else
  CONFIG_FILE="config/server.properties"
fi

# --- args ---
if [ $# -lt 6 ]; then
  die "Usage: bash $0 <WorkspacePath> <Group> <Project> <Environment> <Instance> <Pool> [debug]"
fi

WORKSPACE="$1"        # path to workspace (may be relative)
GROUP="$2"
PROJECT="$3"
ENVIRONMENT="$4"      # dev|stage|prod
INSTANCE="$5"         # author|publish|both
POOL="$6"
DEBUG_FLAG="${7:-}"

# --- script locations (no hardcoded paths outside repo) ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY_SCRIPT="${SCRIPT_DIR}/deploy-package-filter.sh"
[ -f "$DEPLOY_SCRIPT" ] || die "Missing deploy script: $DEPLOY_SCRIPT"

# ensure workspace exists
if [ ! -d "$WORKSPACE" ]; then
  die "Workspace directory not found: $WORKSPACE"
fi

# enable nullglob so no-match yields empty array
shopt -s nullglob
files=( "$WORKSPACE"/*.zip )

if [ ${#files[@]} -eq 0 ]; then
  die "No .zip files found in workspace: $WORKSPACE"
fi

# export SERVER_CONFIG for child script if present in environment
if [ -n "${SERVER_CONFIG:-}" ]; then
  export SERVER_CONFIG
fi

# iterate files and call deploy-package-filter.sh for each
for f in "${files[@]}"; do
  pkgname="$(basename "$f" .zip)"
  info "Processing package file: $f (package prefix: $pkgname)"

  # call deploy script with explicit package file path and prefix
  if [ -n "$DEBUG_FLAG" ]; then
    bash "$DEPLOY_SCRIPT" "$f" "$pkgname" "$GROUP" "$PROJECT" "$ENVIRONMENT" "$INSTANCE" "$POOL" "$DEBUG_FLAG"
  else
    bash "$DEPLOY_SCRIPT" "$f" "$pkgname" "$GROUP" "$PROJECT" "$ENVIRONMENT" "$INSTANCE" "$POOL"
  fi

  info "Finished processing $pkgname"
done

info "All packages in workspace processed."
exit 0
