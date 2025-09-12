#!/bin/sh
set -euo pipefail

# deploy-content-filter.sh
# Wrapper: finds .zip files in workspace and calls deploy-package-filter.sh for each.
# Usage:
#   CONFIG_FILE=/path/to/config/server.properties WORKSPACE_ROOT=/var/lib/build/workspace \
#   CURL_BIN=/usr/bin/curl JAR_BIN=jar UNZIP_BIN=unzip DEBUG=true \
#   bash deploy-content-filter.sh <WORKSPACE> <GROUP> <PROJECT> <ENVIRONMENT> <INSTANCE> <POOL>

[ "$#" -eq 6 ] || { echo "Usage: $0 WORKSPACE GROUP PROJECT ENVIRONMENT INSTANCE POOL"; exit 1; }

WORKSPACE=$1
GROUP=$2
PROJECT=$3
ENVIRONMENT=$4
INSTANCE=$5
POOL=$6

: "${CONFIG_FILE:?CONFIG_FILE must be set}"
: "${WORKSPACE_ROOT:?WORKSPACE_ROOT must be set}"
: "${CURL_BIN:?CURL_BIN must be set}"
: "${JAR_BIN:?JAR_BIN must be set}"
: "${UNZIP_BIN:?UNZIP_BIN must be set}"

DEBUG=${DEBUG:-true}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY_SCRIPT="${SCRIPT_DIR}/deploy-package-filter.sh"
[ -x "$DEPLOY_SCRIPT" ] || { echo "Missing deploy script: $DEPLOY_SCRIPT"; exit 1; }

count=0
find "$WORKSPACE" -maxdepth 1 -type f -name '*.zip' -print0 | while IFS= read -r -d '' pkg; do
  pkgbase=$(basename "$pkg")
  packagename=${pkgbase%.zip}
  echo "Processing package: $pkgbase -> calling deploy script for $packagename"
  if [ "$DEBUG" = "true" ]; then
    echo "[DEBUG] CMD: CONFIG_FILE=$CONFIG_FILE WORKSPACE_ROOT=$WORKSPACE_ROOT CURL_BIN=$CURL_BIN JAR_BIN=$JAR_BIN UNZIP_BIN=$UNZIP_BIN DEBUG=$DEBUG bash \"$DEPLOY_SCRIPT\" \"$WORKSPACE\" \"$packagename\" \"$GROUP\" \"$PROJECT\" \"$ENVIRONMENT\" \"$INSTANCE\" \"$POOL\""
  else
    CONFIG_FILE=$CONFIG_FILE WORKSPACE_ROOT=$WORKSPACE_ROOT CURL_BIN=$CURL_BIN JAR_BIN=$JAR_BIN UNZIP_BIN=$UNZIP_BIN \
      bash "$DEPLOY_SCRIPT" "$WORKSPACE" "$packagename" "$GROUP" "$PROJECT" "$ENVIRONMENT" "$INSTANCE" "$POOL"
    rc=$?
    if [ "$rc" -ne 0 ]; then
      echo "Deploy failed for $packagename (rc=$rc)"; exit $rc
    fi
  fi
  count=$((count+1))
done

if [ "$count" -eq 0 ]; then
  echo "No packages found in $WORKSPACE"; exit 1
fi

echo "Processed $count package(s)."
exit 0
