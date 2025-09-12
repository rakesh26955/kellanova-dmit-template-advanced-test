#!/bin/bash
set -euo pipefail

################################################################################
# deploy-package-filter.sh
# Replaces the old large hardcoded script with a safe, config-driven version.
#
# Usage:
#   CONFIG_FILE=/var/lib/build/config/server.properties \
#   WORKSPACE_ROOT=/var/lib/build/workspace \
#   CURL_BIN=/usr/bin/curl JAR_BIN=jar UNZIP_BIN=unzip DEBUG=true \
#   bash deploy-package-filter.sh <PackagePath> <PackageName> <Group> <Project> <Environment> <Instance> <Pool>
#
# Arguments:
#   $1 PackagePath  - directory (relative or absolute) where .zip/.jar packages are located
#   $2 PackageName  - name prefix (used to find artifact, and to set package property name)
#   $3 Group        - group (used in workspace layout)
#   $4 Project      - project (used in workspace layout)
#   $5 Environment  - dev | stg | prd | devqa | prv | uatkfr | etc.
#   $6 Instance     - author | publish | both
#   $7 Pool         - kstl | kfr | gen | dam | kstl65 | kfr65 | newkstl65 | etc.
#
# Environment variables required:
#   CONFIG_FILE      - path to server.properties containing keys/values
#   WORKSPACE_ROOT   - workspace root (e.g. /var/lib/build/workspace)
#   CURL_BIN         - path to curl binary
#   UNZIP_BIN        - path to unzip binary
#   JAR_BIN          - path to jar (or jar provided by JDK)
# Optional:
#   DEBUG            - if "true" will dry-run install steps
#   CURL_OPTS        - additional options to pass to curl
#   max_package_size - can be set in CONFIG_FILE (MB)
#
################################################################################

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "INFO: $*"; }

if [ $# -ne 7 ]; then
  die "Usage: $0 <PackagePath> <PackageName> <Group> <Project> <Environment> <Instance> <Pool>"
fi

# args
INPUT_PATH="$1"
PACKAGE_PREFIX="$2"
GROUP="$3"
PROJECT="$4"
ENVIRONMENT="$5"
INSTANCE="$6"
POOL="$7"

# env validations
: "${CONFIG_FILE:?CONFIG_FILE must be set (path to server.properties)}"
: "${WORKSPACE_ROOT:?WORKSPACE_ROOT must be set}"
: "${CURL_BIN:?CURL_BIN must be set}"
: "${UNZIP_BIN:?UNZIP_BIN must be set}"
: "${JAR_BIN:?JAR_BIN must be set}"

CURL_OPTS="${CURL_OPTS:-}"
DEBUG="${DEBUG:-true}"

# normalize
lower() { echo "$1" | tr '[:upper:]' '[:lower:]'; }
ENV_LC=$(lower "$ENVIRONMENT")
INST_LC=$(lower "$INSTANCE")
POOL_LC=$(lower "$POOL")

# ensure trailing slash on input path
case "$INPUT_PATH" in */) ;; *) INPUT_PATH="$INPUT_PATH/";; esac

[ -f "$CONFIG_FILE" ] || die "CONFIG_FILE not found at $CONFIG_FILE"

# Load config file into environment variables (handles KEY=val lines, strips comments/empty)
# Preserves quotes for values that contain special chars (e.g., passwords with colon)
TMP_CFG=$(mktemp)
trap 'rm -f "$TMP_CFG"' EXIT
grep -E -v '^\s*#' "$CONFIG_FILE" | sed -E '/^\s*$/d' > "$TMP_CFG"

# Export each KEY=VALUE safely
while IFS='=' read -r key val; do
  [ -z "$key" ] && continue
  key=$(echo "$key" | tr -d '[:space:]')
  # preserve surrounding quotes in value for now, then remove only outer quotes for export
  val=$(echo "$val" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  # remove leading and trailing single or double quotes for export value
  val_unquoted=$(echo "$val" | sed -E "s/^'(.*)'$/\\1/; s/^\"(.*)\"$/\\1/")
  export "$key"="$val_unquoted"
done < "$TMP_CFG"

# parse build user
AEM_DEPLOY_USERNAME=$(echo "$aem_build_user" | awk -F: '{print $1}' | sed -e "s/^'//" -e "s/'$//" -e 's/^"//' -e 's/"$//')
AEM_DEPLOY_PASSWORD=$(echo "$aem_build_user" | awk -F: '{print $2}' | sed -e "s/^'//" -e "s/'$//" -e 's/^"//' -e 's/"$//')
[ -n "$AEM_DEPLOY_USERNAME" ] || die "aem_build_user missing or malformed in $CONFIG_FILE"

# helper: find server variable names that match environment token & pool token
# patterning: keys are like dev_kstl_aem_authors or prd_gen_aem_publishers etc.
# We'll collect authors/publishers/dispatchers for the given pool and environment.
collect_servers() {
  env_token="$1"   # e.g., dev, stg, prd, devqa, prv, uatkfr
  pool_token="$2"  # e.g., kstl, kfr, gen, dam
  role="$3"        # author|publish|dispatchers|all (author/publish selection)
  out=""
  # Use env to list all loaded variables
  while IFS='=' read -r k v; do
    k_lc=$(echo "$k" | tr '[:upper:]' '[:lower:]')
    if echo "$k_lc" | grep -q "^${env_token}_" && echo "$k_lc" | grep -q "_${pool_token}_"; then
      if [ "$role" = "author" ] && echo "$k_lc" | grep -q "author"; then
        out="${out},${v}"
      elif [ "$role" = "publish" ] && echo "$k_lc" | grep -q "publish"; then
        out="${out},${v}"
      elif [ "$role" = "dispatchers" ] && echo "$k_lc" | grep -q "dispatcher"; then
        out="${out},${v}"
      elif [ "$role" = "all" ]; then
        out="${out},${v}"
      fi
    fi
  done < <(env)
  # normalise commas
  echo "$out" | sed -E 's/^,+//; s/,+$//; s/,,+/,/g'
}

# Decide which servers to use based on $INSTANCE
case "$INST_LC" in
  author) ROLE="author" ;;
  publish) ROLE="publish" ;;
  both) ROLE="both" ;;
  *) die "Invalid instance: $INSTANCE (use author|publish|both)" ;;
esac

# Collect servers: if both, concat authors and publishers
if [ "$ROLE" = "both" ]; then
  AEM_AUTHORS=$(collect_servers "$ENV_LC" "$POOL_LC" "author" || true)
  AEM_PUBLISHERS=$(collect_servers "$ENV_LC" "$POOL_LC" "publish" || true)
  AEM_SERVERS=""
  [ -n "$AEM_AUTHORS" ] && AEM_SERVERS="${AEM_SERVERS},${AEM_AUTHORS}"
  [ -n "$AEM_PUBLISHERS" ] && AEM_SERVERS="${AEM_SERVERS},${AEM_PUBLISHERS}"
  AEM_SERVERS=$(echo "$AEM_SERVERS" | sed -E 's/^,+//; s/,+$//; s/,,+/,/g')
else
  AEM_SERVERS=$(collect_servers "$ENV_LC" "$POOL_LC" "$ROLE")
fi

[ -n "$AEM_SERVERS" ] || die "No servers resolved for environment='$ENVIRONMENT' pool='$POOL' instance='$INSTANCE'. Check $CONFIG_FILE keys."

info "Resolved AEM servers: $AEM_SERVERS"

# Validate build permission flag naming convention (env_build_allowed)
build_flag_name="${ENV_LC}_build_allowed"
# Find the variable in environment ignoring case
build_allowed=""
while IFS='=' read -r k v; do
  if [ "$(echo "$k" | tr '[:upper:]' '[:lower:]')" = "$build_flag_name" ]; then
    build_allowed="$v"
    break
  fi
done < <(env)

[ -n "$build_allowed" ] || die "Build permission flag '$build_flag_name' not found in $CONFIG_FILE"

if echo "$build_allowed" | grep -qi false; then
  die "Builds not allowed for environment '$ENVIRONMENT' (flag $build_flag_name is false)"
fi

info "Builds allowed for environment '$ENVIRONMENT'"

# find the matching artifact file
ARTIFACT=$(ls -t "$INPUT_PATH" 2>/dev/null | grep -E "^${PACKAGE_PREFIX}.*" | head -n1 || true)
[ -n "$ARTIFACT" ] || die "No artifact matching prefix '^${PACKAGE_PREFIX}' found in $INPUT_PATH"
ARTIFACT_PATH="${INPUT_PATH}${ARTIFACT}"
[ -f "$ARTIFACT_PATH" ] || die "Artifact file not present: $ARTIFACT_PATH"

info "Selected artifact: $ARTIFACT_PATH"

# file size check (max_package_size expected in config)
if [ -n "${max_package_size:-}" ]; then
  MAX_MB=$(echo "$max_package_size" | sed -E 's/[^0-9]*//g')
  if command -v du >/dev/null 2>&1; then
    ACTUAL_MB=$(du -m "$ARTIFACT_PATH" | awk '{print $1}')
  else
    BYTES=$(wc -c < "$ARTIFACT_PATH")
    ACTUAL_MB=$((BYTES / 1024 / 1024))
  fi
  if [ "$ACTUAL_MB" -ge "$MAX_MB" ]; then
    die "Artifact ${ARTIFACT_PATH} size ${ACTUAL_MB}MB >= max_package_size ${MAX_MB}MB"
  fi
  info "Artifact size ${ACTUAL_MB}MB <= ${MAX_MB}MB"
else
  info "max_package_size not defined; skipping size check"
fi

# Determine if zip or jar
IS_ZIP=false
case "$ARTIFACT_PATH" in
  *.zip) IS_ZIP=true ;;
  *.jar) IS_ZIP=false ;;
  *) die "Unsupported artifact type (not .zip or .jar): $ARTIFACT_PATH" ;;
esac

# Extract package property name from META-INF/vault/properties.xml if present
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
if [ "$IS_ZIP" = true ]; then
  "$UNZIP_BIN" -o "$ARTIFACT_PATH" "META-INF/vault/properties.xml" -d "$TMP_DIR" >/dev/null 2>&1 || true
else
  (cd "$TMP_DIR" && "$JAR_BIN" xvf "$ARTIFACT_PATH" "META-INF/vault/properties.xml" >/dev/null 2>&1 || true)
fi

PROP_NAME=""
if [ -f "$TMP_DIR/META-INF/vault/properties.xml" ]; then
  PROP_NAME=$(sed -n 's:.*<name>\(.*\)</name>.*:\1:p' "$TMP_DIR/META-INF/vault/properties.xml" | head -n1 || true)
fi

[ -n "$PROP_NAME" ] || PROP_NAME="$PACKAGE_PREFIX"
info "Package property name: $PROP_NAME"

# Convert AEM_SERVERS csv to array
IFS=',' read -r -a SERVERS <<< "$AEM_SERVERS"

# helper to list packages on server and detect path/version for our package
discover_remote_package() {
  server_host="$1"
  server_port="$2"
  tmpfile="$3"
  "$CURL_BIN" $CURL_OPTS -s -u "${AEM_DEPLOY_USERNAME}:${AEM_DEPLOY_PASSWORD}" "http://${server_host}:${server_port}/crx/packmgr/service.jsp?cmd=ls" > "$tmpfile" 2>/dev/null || true
  if grep -q "<name>${PROP_NAME}</name>" "$tmpfile"; then
    # find enclosing entry to get group and version
    start_line=$(grep -n "<name>${PROP_NAME}</name>" "$tmpfile" | head -n1 | cut -d: -f1)
    # grab a small window around that line
    window_start=$(( start_line - 10 )); [ $window_start -lt 1 ] && window_start=1
    window_end=$(( start_line + 10 ))
    entry_block=$(sed -n "${window_start},${window_end}p" "$tmpfile")
    group_val=$(echo "$entry_block" | sed -n 's:.*<group>\(.*\)</group>.*:\1:p' | head -n1 || true)
    version_val=$(echo "$entry_block" | sed -n 's:.*<version>\(.*\)</version>.*:\1:p' | head -n1 || true)
    if [ -n "$group_val" ]; then
      pkg_path="/etc/packages/${group_val}/"
    else
      # fallback: try to detect path fragment
      guessed=$(echo "$entry_block" | grep -oE '/etc/packages/[A-Za-z0-9._/-]+' | head -n1 || true)
      [ -n "$guessed" ] && pkg_path="${guessed}/" || pkg_path="/etc/packages/"
    fi
    if [ -n "$version_val" ]; then
      pkg_filename="${PROP_NAME}-${version_val}.zip"
    else
      pkg_filename="${PROP_NAME}.zip"
    fi
    echo "${pkg_path}${pkg_filename}"
    return 0
  fi
  return 1
}

# upload & install to each server
for s in "${SERVERS[@]}"; do
  s=$(echo "$s" | sed -e 's/^ *//' -e 's/ *$//')
  host=$(echo "$s" | awk -F: '{print $1}')
  port=$(echo "$s" | awk -F: '{print $2}')
  [ -n "$host" ] || die "Empty host in server entry '$s'"
  [ -n "$port" ] || die "Empty port in server entry '$s'"

  info "Uploading artifact to ${host}:${port}"
  upload_out=$("$CURL_BIN" $CURL_OPTS -s -u "${AEM_DEPLOY_USERNAME}:${AEM_DEPLOY_PASSWORD}" -F "name=${PACKAGE_PREFIX}" -F "file=@${ARTIFACT_PATH}" "http://${host}:${port}/crx/packmgr/service.jsp" || true)
  info "Upload response (truncated): $(printf "%s" "$upload_out" | head -c 400)"

  tmp_list=$(mktemp)
  if discover_remote_package "$host" "$port" "$tmp_list"; then
    remote_pkg_path=$(discover_remote_package "$host" "$port" "$tmp_list")
  else
    remote_pkg_path=""
  fi
  rm -f "$tmp_list"

  if [ -z "$remote_pkg_path" ]; then
    die "Could not determine remote package path for ${PROP_NAME} on ${host}:${port}"
  fi

  # url encode spaces
  pkg_url=$(printf "%s" "$remote_pkg_path" | sed 's/ /%20/g')
  install_url="http://${host}:${port}/crx/packmgr/service/.json${pkg_url}?cmd=install&force=true&recursive=true"
  info "Installing package at ${install_url}"

  if [ "$DEBUG" = "true" ]; then
    info "[DEBUG] Skipping install (DEBUG=true). Install URL: $install_url"
  else
    install_res=$("$CURL_BIN" $CURL_OPTS -s -u "${AEM_DEPLOY_USERNAME}:${AEM_DEPLOY_PASSWORD}" -X POST "$install_url" || true)
    info "Install response (truncated): $(printf "%s" "$install_res" | head -c 400)"
    if ! echo "$install_res" | grep -qi success; then
      die "Install failed on ${host}:${port}"
    fi
  fi

done

info "Deployment finished for ${ARTIFACT_PATH}"
exit 0
