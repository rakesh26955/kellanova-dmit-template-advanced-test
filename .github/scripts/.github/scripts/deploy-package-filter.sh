#!/usr/bin/env bash
set -euo pipefail

# deploy-package-filter.sh
# Reads all operational values from config/server.properties.
# No hardcoded values inside this script.

die(){ echo "ERROR: $*" >&2; exit 1; }
info(){ echo "INFO: $*"; }

# --- get config file ---
if [ -n "${SERVER_CONFIG:-}" ]; then
  CONFIG_FILE="${SERVER_CONFIG}"
else
  CONFIG_FILE="config/server.properties"
fi
[ -f "$CONFIG_FILE" ] || die "Config file not found: $CONFIG_FILE"

# --- args ---
if [ $# -lt 7 ]; then
  die "Usage: bash .github/scripts/deploy-package-filter.sh <PackagePath> <PackagePrefix> <Group> <Project> <Environment> <Instance> <Pool> [debug]"
fi

INPUT_PATH="$1"
PACKAGE_PREFIX="$2"
GROUP="$3"
PROJECT="$4"
ENV_IN="$5"       # dev|stage|prod
INSTANCE="$6"     # author|publish|both
POOL="$7"
DEBUG_FLAG="${8:-}"

# --- load props into array ---
declare -A props
while IFS= read -r line || [ -n "$line" ]; do
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ -z "$line" ]] && continue
  key="${line%%=*}"
  val="${line#*=}"
  key="$(echo "$key" | tr -d '[:space:]')"
  val="$(echo "$val" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  val="$(printf "%s" "$val" | sed -E "s/^'(.*)'$/\\1/; s/^\"(.*)\"$/\\1/")"
  props["$key"]="$val"
done < "$CONFIG_FILE"

get_prop_or_fail(){
  k="$1"; v="${props[$k]:-}"
  [ -n "$v" ] || die "Missing key '$k' in $CONFIG_FILE"
  printf "%s" "$v"
}

# --- required config keys ---
CURL_BIN="$(get_prop_or_fail CURL_BIN)"
UNZIP_BIN="$(get_prop_or_fail UNZIP_BIN)"
JAR_BIN="$(get_prop_or_fail JAR_BIN)"
CRX_UPLOAD_PATH="$(get_prop_or_fail CRX_UPLOAD_PATH)"
CRX_INSTALL_PREFIX="$(get_prop_or_fail CRX_INSTALL_PREFIX)"
PKG_BASE_PATH="$(get_prop_or_fail PKG_BASE_PATH)"
DEFAULT_AUTHOR_PORT="$(get_prop_or_fail DEFAULT_AUTHOR_PORT)"
DEFAULT_PUBLISH_PORT="$(get_prop_or_fail DEFAULT_PUBLISH_PORT)"
EXPLODE_ROOT="$(get_prop_or_fail EXPLODE_ROOT)"
AEM_BUILD_USER_RAW="$(get_prop_or_fail aem_build_user)"
MAX_PACKAGE_SIZE="${props[max_package_size]:-}"

ENV_TOKEN="$(get_prop_or_fail ENV_TOKEN_${ENV_IN})"
BUILD_FLAG_NAME="$(get_prop_or_fail BUILD_FLAG_${ENV_IN})"

AEM_USER="$(printf "%s" "$AEM_BUILD_USER_RAW" | awk -F: '{print $1}' | tr -d "'\"")"
AEM_PASS="$(printf "%s" "$AEM_BUILD_USER_RAW" | awk -F: '{print $2}' | tr -d "'\"")"
[ -n "$AEM_USER" ] || die "Bad aem_build_user username"
[ -n "$AEM_PASS" ] || die "Bad aem_build_user password"

BUILD_FLAG_VAL="${props[$BUILD_FLAG_NAME]:-}"
[ "$BUILD_FLAG_VAL" = "true" ] || die "Build disabled for $ENV_IN ($BUILD_FLAG_NAME=$BUILD_FLAG_VAL)"

# --- artifact selection ---
case "$INPUT_PATH" in */) ;; *) INPUT_PATH="${INPUT_PATH}/" ;; esac
ARTIFACT="$(ls -t "$INPUT_PATH" 2>/dev/null | grep -E "^${PACKAGE_PREFIX}" | head -n1 || true)"
[ -n "$ARTIFACT" ] || die "No artifact with prefix '$PACKAGE_PREFIX' in $INPUT_PATH"
ARTIFACT_PATH="${INPUT_PATH}${ARTIFACT}"
info "Using artifact: $ARTIFACT_PATH"

if [ -n "$MAX_PACKAGE_SIZE" ]; then
  SIZE_MB=$(du -m "$ARTIFACT_PATH" | awk '{print $1}')
  [ "$SIZE_MB" -lt "$MAX_PACKAGE_SIZE" ] || die "Artifact too large (${SIZE_MB}MB)"
fi

# --- extract package name ---
TMP_EX="$(mktemp -d)"
trap 'rm -rf "$TMP_EX"' EXIT
if echo "$ARTIFACT_PATH" | grep -q "\.zip$"; then
  "$UNZIP_BIN" -o "$ARTIFACT_PATH" META-INF/vault/properties.xml -d "$TMP_EX" >/dev/null 2>&1 || true
else
  (cd "$TMP_EX" && "$JAR_BIN" xvf "$ARTIFACT_PATH" META-INF/vault/properties.xml >/dev/null 2>&1 || true)
fi
PROP_NAME="$(sed -n 's:.*<name>\(.*\)</name>.*:\1:p' "$TMP_EX/META-INF/vault/properties.xml" 2>/dev/null || true)"
[ -n "$PROP_NAME" ] || PROP_NAME="$PACKAGE_PREFIX"
info "Package logical name: $PROP_NAME"

# --- explode workspace ---
EXPLODE_DIR="${EXPLODE_ROOT}/${GROUP}/${PROJECT}"
mkdir -p "${EXPLODE_DIR}/temp"
[ -f "${EXPLODE_DIR}/filter.txt" ] || echo '/' > "${EXPLODE_DIR}/filter.txt"

# --- resolve servers ---
POOL_LC="$(echo "$POOL" | tr '[:upper:]' '[:lower:]')"
AUTH_KEY="${ENV_TOKEN}_${POOL_LC}_aem_authors"
PUBL_KEY="${ENV_TOKEN}_${POOL_LC}_aem_publishers"

if [ "$INSTANCE" = "author" ]; then
  SERVERS="${props[$AUTH_KEY]:-}"
elif [ "$INSTANCE" = "publish" ]; then
  SERVERS="${props[$PUBL_KEY]:-}"
elif [ "$INSTANCE" = "both" ]; then
  SERVERS="${props[$AUTH_KEY]:-},${props[$PUBL_KEY]:-}"
else
  die "Bad instance '$INSTANCE'"
fi
[ -n "$SERVERS" ] || die "No servers for $ENV_IN/$POOL/$INSTANCE"

info "Servers: $SERVERS"

# --- deploy loop ---
IFS=',' read -r -a ARR <<< "$SERVERS"
for srv in "${ARR[@]}"; do
  HOST="$(echo "$srv" | cut -d: -f1)"
  PORT="$(echo "$srv" | cut -d: -f2 -s)"
  [ -n "$PORT" ] || { [ "$INSTANCE" = "author" ] && PORT="$DEFAULT_AUTHOR_PORT" || PORT="$DEFAULT_PUBLISH_PORT"; }

  info "Uploading $ARTIFACT_PATH to ${HOST}:${PORT}"
  "$CURL_BIN" -s -u "${AEM_USER}:${AEM_PASS}" -F "name=${PACKAGE_PREFIX}" -F "file=@${ARTIFACT_PATH}" \
    "http://${HOST}:${PORT}${CRX_UPLOAD_PATH}" >/dev/null

  REMOTE_PKG="${PKG_BASE_PATH}/${GROUP}/${PROP_NAME}.zip"
  REMOTE_PKG_ESC="$(printf "%s" "$REMOTE_PKG" | sed 's/ /%20/g')"
  INSTALL_URL="http://${HOST}:${PORT}${CRX_INSTALL_PREFIX}${REMOTE_PKG_ESC}?cmd=install&force=true&recursive=true"

  if [ "$DEBUG_FLAG" = "debug" ]; then
    echo "[DEBUG] Would POST to $INSTALL_URL"
    continue
  fi

  OUT="$("$CURL_BIN" -s -u "${AEM_USER}:${AEM_PASS}" -X POST "$INSTALL_URL" || true)"
  echo "Response: $(printf '%s' "$OUT" | head -c200)"

  echo "$OUT" | grep -Eq "success|ok|installed" || die "Install failed on ${HOST}:${PORT}"
done

info "Deployment finished for $PROP_NAME"
