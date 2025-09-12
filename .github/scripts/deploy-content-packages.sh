#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------------
# deploy-content-packages.sh
# Wrapper: iterate workspace *.zip and call deploy-package-filter.sh
# -------------------------------------------------------------------

die(){ echo "ERROR: $*" >&2; exit 1; }
info(){ echo "INFO: $*"; }

# --- args ---
if [ $# -lt 6 ]; then
  die "Usage: $0 <WorkspacePath> <Group> <Project> <Environment> <Instance> <Pool> [debug]"
fi

WORKSPACE="$1"
GROUP="$2"
PROJECT="$3"
ENVIRONMENT="$4"
INSTANCE="$5"
POOL="$6"
DEBUG_FLAG="${7:-}"

# --- locate script dir and child deploy script ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY_SCRIPT="${SCRIPT_DIR}/deploy-package-filter.sh"
[ -f "$DEPLOY_SCRIPT" ] || die "Missing deploy script: $DEPLOY_SCRIPT"

# --- workspace check ---
if [ ! -d "$WORKSPACE" ]; then
  die "Workspace directory not found: $WORKSPACE"
fi

shopt -s nullglob
files=( "$WORKSPACE"/*.zip )

if [ ${#files[@]} -eq 0 ]; then
  die "No .zip files found in workspace: $WORKSPACE"
fi

# --- config file handling ---
CONFIG_FILE="${SERVER_CONFIG:-.github/config/server.properties}"
info "Using config file: $CONFIG_FILE"

if [ ! -f "$CONFIG_FILE" ]; then
  die "Config file not found: $CONFIG_FILE"
fi

# --- iterate packages and call child deploy script ---
for f in "${files[@]}"; do
  pkgname="$(basename "$f" .zip)"
  info "Processing package file: $f (package prefix: $pkgname)"

  if [ -n "$DEBUG_FLAG" ]; then
    bash "$DEPLOY_SCRIPT" "$WORKSPACE" "$pkgname" "$GROUP" "$PROJECT" "$ENVIRONMENT" "$INSTANCE" "$POOL" "$DEBUG_FLAG"
  else
    bash "$DEPLOY_SCRIPT" "$WORKSPACE" "$pkgname" "$GROUP" "$PROJECT" "$ENVIRONMENT" "$INSTANCE" "$POOL"
  fi

  info "Finished processing $pkgname"
done

info "All packages in workspace processed."
exit 0
