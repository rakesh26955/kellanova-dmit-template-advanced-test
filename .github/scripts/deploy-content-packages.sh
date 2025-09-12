#!/bin/sh
set -euo pipefail

# deploy-content-packages.sh
# Finds .zip packages in workspace and calls deploy-package-filter.sh.

help() {
  echo "Usage: $0 <WORKSPACE> <GROUP> <PROJECT> <ENVIRONMENT> <INSTANCE> <POOL>"
  exit 1
}

if [ $# -ne 6 ]; then
  help
fi

WORKSPACE=$1
GROUP=$2
PROJECT=$3
ENVIRONMENT=$4
INSTANCE=$5
POOL=$6

DEPLOY_SCRIPT="$(cd "$(dirname "$0")" && pwd)/deploy-package-filter.sh"
[ -x "$DEPLOY_SCRIPT" ] || { echo "ERROR: missing $DEPLOY_SCRIPT"; exit 1; }

: "${CONFIG_FILE:=config/server.properties}"
: "${CURL_BIN:=/usr/bin/curl}"
: "${UNZIP_BIN:=unzip}"
: "${JAR_BIN:=jar}"
: "${DEBUG:=false}"

cd "$WORKSPACE" || { echo "Workspace not found: $WORKSPACE"; exit 1; }

found=0
for f in *.zip; do
  [ -e "$f" ] || continue
  found=1
  PACKAGENAME="${f%.zip}"
  echo "Processing package: $f"
  CONFIG_FILE="$CONFIG_FILE" CURL_BIN="$CURL_BIN" UNZIP_BIN="$UNZIP_BIN" JAR_BIN="$JAR_BIN" DEBUG="$DEBUG" \
    bash "$DEPLOY_SCRIPT" "$WORKSPACE" "$PACKAGENAME" "$GROUP" "$PROJECT" "$ENVIRONMENT" "$INSTANCE" "$POOL"
done

[ $found -eq 1 ] || { echo "No .zip packages found in $WORKSPACE"; exit 1; }

echo "All packages processed."
