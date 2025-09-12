#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------------
# deploy-package-filter.sh
# Deploy a single package. Reads runtime values strictly from
# .github/config/server.properties (or SERVER_CONFIG override).
# -------------------------------------------------------------------

die(){ echo "ERROR: $*" >&2; exit 1; }
info(){ echo "INFO: $*"; }
warn(){ echo "WARN: $*" >&2; }

# --- args ---
if [ $# -lt 7 ]; then
  die "Usage: $0 <PackagePath> <PackagePrefix> <Group> <Project> <Environment> <Instance> <Pool> [debug]"
fi

INPUTPATH="$1"
PACK_PREFIX="$2"
GROUP="$3"
PROJECT="$4"
ENVIRONMENT="$5"
INSTANCE="$6"
POOL="$7"
DEBUG_FLAG="${8:-}"

# --- config file ---
CONFIG_FILE="${SERVER_CONFIG:-.github/config/server.properties}"
[ -f "$CONFIG_FILE" ] || die "Config file not found: $CONFIG_FILE"
info "Using config file: $CONFIG_FILE"

# --- load properties ---
declare -A props
while IFS= read -r line || [ -n "$line" ]; do
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ -z "$line" ]] && continue
  key="${line%%=*}"
  val="${line#*=}"
  key="$(printf "%s" "$key" | tr -d '[:space:]')"
  # trim whitespace and strip optional quotes
  val="$(printf "%s" "$val" \
    | sed -e 's/^[[:space:]]*//' \
          -e 's/[[:space:]]*$//' \
          -e "s/^'//; s/'$//" \
          -e 's/^"//; s/"$//')"
  props["$key"]="$val"
done < "$CONFIG_FILE"

get_prop_fail(){ [ -n "${props[$1]:-}" ] || die "Missing required config key '$1'"; printf "%s" "${props[$1]}"; }
get_prop(){ printf "%s" "${props[$1]:-}"; }

# --- runtime keys ---
CURL_BIN="$(get_prop_fail CURL_BIN)"
UNZIP_BIN="$(get_prop_fail UNZIP_BIN)"
JAR_BIN="$(get_prop_fail JAR_BIN)"
CRX_UPLOAD_PATH="$(get_prop_fail CRX_UPLOAD_PATH)"
CRX_INSTALL_PREFIX="$(get_prop_fail CRX_INSTALL_PREFIX)"
PKG_BASE_PATH="$(get_prop_fail PKG_BASE_PATH)"
EXPLODE_ROOT="$(get_prop_fail EXPLODE_ROOT)"
DEFAULT_AUTHOR_PORT="$(get_prop_fail DEFAULT_AUTHOR_PORT)"
DEFAULT_PUBLISH_PORT="$(get_prop_fail DEFAULT_PUBLISH_PORT)"
MAX_PACKAGE_SIZE="${props[max_package_size]:-}"

AEM_BUILD_USER_RAW="$(get_prop_fail aem_build_user)"
AEM_DEPLOY_USERNAME="$(printf "%s" "$AEM_BUILD_USER_RAW" | awk -F: '{print $1}')"
AEM_DEPLOY_PASSWORD="$(printf "%s" "$AEM_BUILD_USER_RAW" | awk -F: '{print $2}')"

# --- locate package file ---
if [ -d "$INPUTPATH" ]; then
  file_found="$(ls -t "$INPUTPATH" | grep -E "^${PACK_PREFIX}" | head -n1 || true)"
  JARFILE="${INPUTPATH%/}/${file_found}"
else
  JARFILE="$INPUTPATH"
fi
[ -f "$JARFILE" ] || die "Package not found: $JARFILE"
info "Package file: $JARFILE"

# --- check size ---
if [ -n "$MAX_PACKAGE_SIZE" ]; then
  actualsize=$(du -m "$JARFILE" | awk '{print $1}')
  [ "$actualsize" -le "$MAX_PACKAGE_SIZE" ] || die "Package $actualsize MB exceeds limit $MAX_PACKAGE_SIZE MB"
fi

# --- explode path ---
RUN_ID="$(date +%s)-$$"
EXPLODE_PATH="${EXPLODE_ROOT%/}/explode-${RUN_ID}"

# Try to create explode dir; fallback if not writable
if ! mkdir -p "$EXPLODE_PATH" 2>/dev/null; then
  warn "EXPLODE_ROOT $EXPLODE_ROOT not writable, falling back to ${GITHUB_WORKSPACE:-$(pwd)}/build"
  EXPLODE_ROOT="${GITHUB_WORKSPACE:-$(pwd)}/build"
  EXPLODE_PATH="${EXPLODE_ROOT%/}/explode-${RUN_ID}"
  mkdir -p "$EXPLODE_PATH"
fi

info "Using explode path: $EXPLODE_PATH"

# --- extract metadata ---
if echo "$JARFILE" | grep -q "\.zip$"; then
  "$UNZIP_BIN" -o "$JARFILE" META-INF/vault/filter.xml -d "$EXPLODE_PATH" >/dev/null 2>&1 || true
  "$UNZIP_BIN" -o "$JARFILE" META-INF/vault/properties.xml -d "$EXPLODE_PATH" >/dev/null 2>&1 || true
else
  (cd "$EXPLODE_PATH" && "$JAR_BIN" xvf "$JARFILE" META-INF/vault/filter.xml >/dev/null 2>&1 || true)
  (cd "$EXPLODE_PATH" && "$JAR_BIN" xvf "$JARFILE" META-INF/vault/properties.xml >/dev/null 2>&1 || true)
fi

# --- determine servers ---
pool_lc="$(echo "$POOL" | tr '[:upper:]' '[:lower:]')"
auth_key="${ENVIRONMENT}_${pool_lc}_aem_authors"
pub_key="${ENVIRONMENT}_${pool_lc}_aem_publishers"
AEM_SERVERS=""
if [ "$INSTANCE" = "author" ]; then
  AEM_SERVERS="$(get_prop "$auth_key")"
elif [ "$INSTANCE" = "publish" ]; then
  AEM_SERVERS="$(get_prop "$pub_key")"
else
  AEM_SERVERS="$(get_prop "$auth_key"),$(get_prop "$pub_key")"
fi
[ -n "$AEM_SERVERS" ] || die "No servers configured for $ENVIRONMENT:$POOL:$INSTANCE"

# --- deploy loop ---
IFS=',' read -r -a SERVERS <<< "$AEM_SERVERS"
for S in "${SERVERS[@]}"; do
  HOST="$(echo "$S" | cut -d: -f1)"
  PORT="$(echo "$S" | cut -d: -f2)"
  [ -n "$PORT" ] || PORT="$DEFAULT_PUBLISH_PORT"

  if [ "${SKIP_DEPLOY:-false}" = "true" ]; then
    warn "Skipping deployment to $HOST:$PORT (SKIP_DEPLOY=true)"
    continue
  fi

  info "Uploading to $HOST:$PORT"
  "$CURL_BIN" -s -u "$AEM_DEPLOY_USERNAME:$AEM_DEPLOY_PASSWORD" \
    -F "name=${PACK_PREFIX}" -F "file=@${JARFILE}" \
    "http://${HOST}:${PORT}${CRX_UPLOAD_PATH}"

  info "Installing on $HOST:$PORT"
  "$CURL_BIN" -s -u "$AEM_DEPLOY_USERNAME:$AEM_DEPLOY_PASSWORD" \
    -X POST "http://${HOST}:${PORT}${CRX_INSTALL_PREFIX}${PKG_BASE_PATH}/${GROUP}/${PACK_PREFIX}.zip?cmd=install&force=true&recursive=true"
done

rm -rf "$EXPLODE_PATH" >/dev/null 2>&1 || true
info "Deployment finished for $PACK_PREFIX"
