#!/usr/bin/env bash
set -euo pipefail

# deploy-package-filter.sh
# Original-style deploy script with no hardcoded values.
# Reads all operational values from config/server.properties (or SERVER_CONFIG env).
#
# Usage:
#   SERVER_CONFIG=config/server.properties \
#   bash .github/scripts/deploy-package-filter.sh <PackagePath> <PackageNamePrefix> <Group> <Project> <Environment> <Instance> <Pool> [debug]

die(){ echo "ERROR: $*" >&2; exit 1; }
info(){ echo "INFO: $*"; }
warn(){ echo "WARN: $*" >&2; }

# --- locate config file ---
if [ -n "${SERVER_CONFIG:-}" ]; then
  CONFIG_FILE="${SERVER_CONFIG}"
else
  CONFIG_FILE="config/server.properties"
fi
[ -f "$CONFIG_FILE" ] || die "Config file not found: $CONFIG_FILE"

# --- load properties ---
declare -A props
while IFS= read -r line || [ -n "$line" ]; do
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ -z "$line" ]] && continue
  key="${line%%=*}"
  val="${line#*=}"
  key="$(echo "$key" | tr -d '[:space:]')"
  val="$(echo "$val" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  val="$(printf "%s" "$val" | sed -E "s/^'(.*)'$/\1/; s/^\"(.*)\"$/\1/")"
  props["$key"]="$val"
done < "$CONFIG_FILE"

get_prop_fail(){
  k="$1"
  v="${props[$k]:-}"
  [ -n "$v" ] || die "Required config key '$k' missing in $CONFIG_FILE"
  printf "%s" "$v"
}
get_prop(){ printf "%s" "${props[$1]:-}"; }

# --- required runtime values ---
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
AEM_BUILD_USER_RAW="$(printf "%s" "$AEM_BUILD_USER_RAW" | sed -E "s/^['\"]//; s/['\"]$//")"
AEM_DEPLOY_USERNAME="$(printf "%s" "$AEM_BUILD_USER_RAW" | awk -F: '{print $1}')"
AEM_DEPLOY_PASSWORD="$(printf "%s" "$AEM_BUILD_USER_RAW" | awk -F: '{print $2}')"

[ -n "$AEM_DEPLOY_USERNAME" ] || die "Invalid aem_build_user value (username missing)"
[ -n "$AEM_DEPLOY_PASSWORD" ] || die "Invalid aem_build_user value (password missing)"

help(){
  echo "Usage:"
  echo "  SERVER_CONFIG=config/server.properties bash $0 <PackagePath> <PackagePrefix> <Group> <Project> <Environment> <Instance> <Pool> [debug]"
}

# ---------- main logic ----------
main(){
  inputpath="$1"
  package="$2"
  group="$3"
  project="$4"
  environment="$5"
  instance="$6"
  pool="$7"
  bDebug="${8:-}"

  info "Processing package: $package from $inputpath"
  if [ -d "$inputpath" ]; then
    jarfileloc="$(ls -t "$inputpath" | grep -E "^${package}" | head -n1 || true)"
    jarfileloc="${inputpath%/}/${jarfileloc}"
  else
    jarfileloc="$inputpath"
  fi

  [ -f "$jarfileloc" ] || die "Package file not found: $jarfileloc"
  info "Package file: $jarfileloc"

  # size check
  if [ -n "$MAX_PACKAGE_SIZE" ]; then
    actualsize=$(du -m "$jarfileloc" | awk '{print $1}')
    if [[ $actualsize -gt $MAX_PACKAGE_SIZE ]]; then
      die "File size ${actualsize}MB exceeds max_package_size ${MAX_PACKAGE_SIZE}MB"
    fi
  fi

  # detect type
  if echo "$jarfileloc" | grep -q "\.zip$"; then
    info "Zip file detected."
  elif echo "$jarfileloc" | grep -q "\.jar$"; then
    info "Jar file detected."
  else
    die "Unsupported package type: $jarfileloc"
  fi

  # here you’d add logic for selecting servers from config, uploading, and installing
  # simplified demo flow:
  info "Would now deploy $package for env=$environment instance=$instance pool=$pool"
}

# ---------- arg parsing ----------
if [ $# -lt 7 ]; then
  help
  exit 1
fi

main "$@"
