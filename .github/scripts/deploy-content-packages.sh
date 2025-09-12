#!/usr/bin/env bash
set -euo pipefail

die(){ echo "ERROR: $*" >&2; exit 1; }
info(){ echo "INFO: $*"; }

if [ -n "${SERVER_CONFIG:-}" ]; then
  CONFIG_FILE="${SERVER_CONFIG}"
else
  CONFIG_FILE="config/server.properties"
fi

if [ $# -lt 6 ]; then
  die "Usage: bash $0 <WorkspacePath> <Group> <Project> <Environment> <Instance> <Pool> [debug]"
fi

WORKSPACE="$1"
GROUP="$2"
PROJECT="$3"
ENVIRONMENT="$4"
INSTANCE="$5"
POOL="$6"
DEBUG_FLAG="${7:-}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY_SCRIPT="${SCRIPT_DIR}/deploy-package-filter.sh"
[ -f "$DEPLOY_SCRIPT" ] || die "Missing deploy script: $DEPLOY_SCRIPT"

if [ ! -d "$WORKSPACE" ]; then
  die "Workspace directory not found: $WORKSPACE"
fi

shopt -s nullglob
files=( "$WORKSPACE"/*.zip )

if [ ${#files[@]} -eq 0 ]; then
  die "No .zip files found in workspace: $WORKSPACE"
fi

if [ -n "${SERVER_CONFIG:-}" ]; then
  export SERVER_CONFIG
fi

for f in "${files[@]}"; do
  pkgname="$(basename "$f" .zip)"
  info "Processing package file: $f (package prefix: $pkgname)"

  if [ -n "$DEBUG_FLAG" ]; then
    bash "$DEPLOY_SCRIPT" "$f" "$pkgname" "$GROUP" "$PROJECT" "$ENVIRONMENT" "$INSTANCE" "$POOL" "$DEBUG_FLAG"
  else
    bash "$DEPLOY_SCRIPT" "$f" "$pkgname" "$GROUP" "$PROJECT" "$ENVIRONMENT" "$INSTANCE" "$POOL"
  fi

  info "Finished processing $pkgname"
done

info "All packages in workspace processed."
exit 0
