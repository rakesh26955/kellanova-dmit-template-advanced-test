#!/bin/bash
set -euo pipefail

# deploy-package-filter.sh
# Deploys a single package to AEM servers based on environment, instance, and pool.

die() { echo "ERROR: $*" >&2; exit 1; }

if [ $# -ne 7 ]; then
  die "Usage: $0 <PackagePath> <PackageName> <Group> <Project> <Environment> <Instance> <Pool>"
fi

INPUT_PATH="$1"
PACKAGE_NAME="$2"
GROUP="$3"
PROJECT="$4"
ENVIRONMENT=$(echo "$5" | tr '[:upper:]' '[:lower:]')
INSTANCE=$(echo "$6" | tr '[:upper:]' '[:lower:]')
POOL=$(echo "$7" | tr '[:upper:]' '[:lower:]')

: "${CONFIG_FILE:=config/server.properties}"
: "${CURL_BIN:=/usr/bin/curl}"
: "${UNZIP_BIN:=unzip}"
: "${JAR_BIN:=jar}"
: "${DEBUG:=false}"

[ -f "$CONFIG_FILE" ] || die "Config file not found: $CONFIG_FILE"

# Load config
set -o allexport
. "$CONFIG_FILE"
set +o allexport

USERNAME=$(echo "$aem_build_user" | awk -F: '{print $1}' | tr -d "'")
PASSWORD=$(echo "$aem_build_user" | awk -F: '{print $2}' | tr -d "'")

# Build flag check
flag_var="${ENVIRONMENT}_build_allowed"
flag_val=$(eval echo "\$$flag_var")
if [ "$flag_val" != "true" ]; then
  die "Builds not allowed for environment: $ENVIRONMENT"
fi

# Resolve servers
key="${ENVIRONMENT}_${POOL}_aem_${INSTANCE}s"
SERVERS=$(eval echo "\$$key")
[ -n "$SERVERS" ] || die "No servers found for key: $key"

# Find artifact
case "$INPUT_PATH" in */) ;; *) INPUT_PATH="$INPUT_PATH/";; esac
ARTIFACT=$(ls -t "$INPUT_PATH" | grep -E "^${PACKAGE_NAME}.*" | head -n1 || true)
[ -n "$ARTIFACT" ] || die "No artifact found for prefix: $PACKAGE_NAME"
ARTIFACT_PATH="${INPUT_PATH}${ARTIFACT}"

# Deploy to each server
IFS=',' read -ra SRVLIST <<< "$SERVERS"
for srv in "${SRVLIST[@]}"; do
  HOST=$(echo "$srv" | cut -d: -f1)
  PORT=$(echo "$srv" | cut -d: -f2)

  echo "Uploading $ARTIFACT_PATH to $HOST:$PORT"
  $CURL_BIN -s -u "$USERNAME:$PASSWORD" \
    -F "name=$PACKAGE_NAME" \
    -F "file=@$ARTIFACT_PATH" \
    "http://$HOST:$PORT/crx/packmgr/service.jsp"

  INSTALL_URL="http://$HOST:$PORT/crx/packmgr/service/.json/etc/packages/${GROUP}/${PACKAGE_NAME}.zip?cmd=install&force=true&recursive=true"

  if [ "$DEBUG" = "true" ]; then
    echo "[DEBUG] Skipping install: $INSTALL_URL"
  else
    RES=$($CURL_BIN -s -u "$USERNAME:$PASSWORD" -X POST "$INSTALL_URL")
    echo "Install response: $(echo "$RES" | head -c200)"
  fi
done
