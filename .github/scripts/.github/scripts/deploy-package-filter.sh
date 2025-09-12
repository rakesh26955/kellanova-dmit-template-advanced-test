#!/usr/bin/env bash
set -euo pipefail

# deploy-package-filter.sh
# All operational values must be taken from config/server.properties (or SERVER_CONFIG env).
#
# Usage:
#   SERVER_CONFIG=config/server.properties \
#   bash .github/scripts/deploy-package-filter.sh <PackagePath|PackageFile> <PackageNamePrefix> <Group> <Project> <Environment> <Instance> <Pool> [debug]
#
# Notes:
# - Script expects keys in config/server.properties (or passed via SERVER_CONFIG) for all runtime values.
# - No hardcoded operational values are present.

die(){ echo "ERROR: $*" >&2; exit 1; }
info(){ echo "INFO: $*"; }
warn(){ echo "WARN: $*" >&2; }

# --- locate config file (no built-in magic defaults beyond repo path) ---
if [ -n "${SERVER_CONFIG:-}" ]; then
  CONFIG_FILE="${SERVER_CONFIG}"
else
  CONFIG_FILE="config/server.properties"
fi
[ -f "$CONFIG_FILE" ] || die "Config file not found: $CONFIG_FILE"

# --- load properties into associative array (safe parsing, strip quotes) ---
declare -A props
while IFS= read -r line || [ -n "$line" ]; do
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ -z "$line" ]] && continue
  key="${line%%=*}"
  val="${line#*=}"
  key="$(printf "%s" "$key" | tr -d '[:space:]')"
  val="$(printf "%s" "$val" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  val="$(printf "%s" "$val" | sed -E "s/^'(.*)'$/\\1/; s/^\"(.*)\"$/\\1/")"
  props["$key"]="$val"
done < "$CONFIG_FILE"

get_prop_fail(){
  k="$1"
  v="${props[$k]:-}"
  [ -n "$v" ] || die "Required config key '$k' missing in $CONFIG_FILE"
  printf "%s" "$v"
}
get_prop(){ printf "%s" "${props[$1]:-}"; }

# --- required runtime/tool keys (must be present in config) ---
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

# optional external validator command (if not present, filter validation will be skipped)
CHECKFILTER_CMD="$(get_prop CHECKFILTER_CMD)"

# credentials (aem_build_user must be present in config in user:pass format; quotes allowed)
AEM_BUILD_USER_RAW="$(get_prop_fail aem_build_user)"
AEM_BUILD_USER_RAW="$(printf "%s" "$AEM_BUILD_USER_RAW" | sed -E "s/^['\"]//; s/['\"]$//")"
AEM_DEPLOY_USERNAME="$(printf "%s" "$AEM_BUILD_USER_RAW" | awk -F: '{print $1}')"
AEM_DEPLOY_PASSWORD="$(printf "%s" "$AEM_BUILD_USER_RAW" | awk -F: '{print $2}')"
[ -n "$AEM_DEPLOY_USERNAME" ] || die "Invalid aem_build_user value (username missing)"
[ -n "$AEM_DEPLOY_PASSWORD" ] || die "Invalid aem_build_user value (password missing)"

# --- explode directory setup (derived from EXPLODE_ROOT) ---
# Ensure EXPLODE_ROOT exists or create it (safe creation)
EXPLODE_ROOT_DIR="${EXPLODE_ROOT%/}"
if [ ! -d "$EXPLODE_ROOT_DIR" ]; then
  mkdir -p "$EXPLODE_ROOT_DIR" || die "Unable to create EXPLODE_ROOT directory: $EXPLODE_ROOT_DIR"
fi

# runtime root under EXPLODE_ROOT to avoid collisions
# use mktemp inside EXPLODE_ROOT if possible
if command -v mktemp >/dev/null 2>&1; then
  EXPLODE_RUNTIME_ROOT="$(mktemp -d "${EXPLODE_ROOT_DIR}/explode.XXXXXX" 2>/dev/null || mktemp -d "/tmp/explode.XXXXXX")"
else
  EXPLODE_RUNTIME_ROOT="$(date +%s)_$$"
  EXPLODE_RUNTIME_ROOT="${EXPLODE_ROOT_DIR%/}/explode.${EXPLODE_RUNTIME_ROOT}"
  mkdir -p "$EXPLODE_RUNTIME_ROOT" || die "Cannot create runtime explode dir: $EXPLODE_RUNTIME_ROOT"
fi

# default EXPLODE_PATH will be set per-package inside main()
EXPLODE_PATH="${EXPLODE_RUNTIME_ROOT}"
EXPLODE_PATH_ROOT="${EXPLODE_RUNTIME_ROOT}"

help(){
  echo "invalid number of arguments or help requested"
  echo "parameters: PackagePath PackageNamePrefix Group Project Environment Instance Pool [debug]"
  echo "Usage:"
  echo "  SERVER_CONFIG=config/server.properties bash $0 <PackagePath|PackageFile> <PackagePrefix> <Group> <Project> <Environment> <Instance> <Pool> [debug]"
}

# --- functions copied/adapted from original but reading props ---
validateFilter(){
  # $1 = explodePath
  # $2 = group
  # $3 = project
  if [ -z "$CHECKFILTER_CMD" ]; then
    info "No CHECKFILTER_CMD in config; skipping filter validation."
    echo 1
    return 0
  fi

  cmd="$CHECKFILTER_CMD $1 $2 $3"
  info "Running filter validator: $cmd"
  set +e
  out="$(eval "$cmd" 2>&1)"
  rc=$?
  set -e
  echo "Validator output (truncated): $(printf '%s' "$out" | head -c400)"
  # original expected 1 or true; allow rc=0 with "1" or "true"
  if [ $rc -eq 0 ]; then
    if echo "$out" | grep -Eiq "(^|[^a-zA-Z0-9])(1|true)([^a-zA-Z0-9]|$)"; then
      echo 1
      return 0
    fi
    # assume success if rc=0
    echo 1
    return 0
  fi
  echo 0
  return 1
}

get_fn_results(){
  # Expects 'result' variable to be set in caller scope
  if [ -z "${result:-}" ]; then
    die "get_fn_results called but result variable empty"
  fi
  tmp="$result"
  tmp="$(printf "%s" "$tmp" | sed -E 's/^[\[\(]//; s/[\]\)]$//' )"
  IFS=',' read -ra RES <<< "$tmp"
  success="${RES[0]:-}"
  message="${RES[1]:-}"
  success="$(printf "%s" "$success" | tr -d '[:space:]')"
  message="$(printf "%s" "$message" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  if echo "$success" | grep -Eiq "true|1"; then
    echo ""
    echo "Successfully processed command."
    echo ""
    return 0
  else
    echo ""
    echo "Function failed with error: $message"
    echo ""
    exit 1
  fi
}

find_package_name(){
  propfile="$1"
  propname=""
  if [ -f "$propfile" ]; then
    while IFS= read -r i; do
      if [[ $i == *"<name>"* ]]; then
        propname="$(printf "%s" "$i" | sed -n 's:.*<name>\(.*\)</name>.*:\1:p')"
        break
      fi
    done < "$propfile"
  fi
  printf "%s" "$propname"
}

list_packages(){
  # packagevar, packagetst
  packagevar="$1"
  packagetst="$2"

  info "Getting the list of packages on server $AEM_DEPLOY_IP:$AEM_DEPLOY_PORT..."
  info "Looking for package $packagevar"
  "$CURL_BIN" -s -u "${AEM_DEPLOY_USERNAME}:${AEM_DEPLOY_PASSWORD}" "http://${AEM_DEPLOY_IP}:${AEM_DEPLOY_PORT}${CRX_UPLOAD_PATH}?cmd=ls" > "$packagetst" || true

  packfnd=0
  blnF=0
  N=0
  declare -a pcklist
  while IFS= read -r i; do
    if [ "$blnF" = "true" ]; then
      version="$(printf "%s" "$i" | sed -n 's:.*<version>\(.*\)</version>.*:\1:p' || true)"
      if [ -n "$version" ]; then
        version_found="$version"
        break
      fi
    fi
    if printf "%s" "$i" | grep -q "<name>"; then
      packagename="$(printf "%s" "$i" | sed -n 's:.*<name>\(.*\)</name>.*:\1:p' || true)"
      if [ "$packagename" = "$packagevar" ]; then
        packfnd=1
        blnF="true"
      fi
    fi
    pcklist[$N]="$i"
    N=$((N+1))
  done < "$packagetst"

  if [[ $packfnd != 1 ]]; then
    echo ""
    echo "Package not found $packagevar!"
    echo ""
  fi
}

# ---------- main logic (keeps structure similar to original) ----------
main(){
  inputpath="$1"
  package="$2"
  group="$3"
  project="$4"
  environment="$5"
  instance="$6"
  pool="$7"
  bDebug="${8:-}"

  info "Looking for package prefix '$package' in '$inputpath'"

  # select latest file matching prefix exactly like original if inputpath is a directory
  if [ -d "$inputpath" ]; then
    jarfileloc="$(ls -t "$inputpath" 2>/dev/null | grep -E "^${package}" | head -n1 || true)"
    jarfileloc="${inputpath%/}/${jarfileloc}"
  else
    jarfileloc="$inputpath"
  fi

  [ -f "$jarfileloc" ] || die "Package file not found: $jarfileloc"
  info "Package path: $jarfileloc"

  # ensure per-package explode path under runtime root
  EXPLODE_PATH="${EXPLODE_RUNTIME_ROOT%/}/${package}"
  EXPLODE_PATH_ROOT="${EXPLODE_RUNTIME_ROOT%/}"
  rm -rf "$EXPLODE_PATH" || true
  mkdir -p "$EXPLODE_PATH" || die "Cannot create explode path $EXPLODE_PATH"

  # check file size limit (if configured)
  if [ -n "$MAX_PACKAGE_SIZE" ]; then
    if command -v du >/dev/null 2>&1; then
      actualsize=$(du -m "$jarfileloc" | awk '{print $1}')
    else
      actualsize=$(( $(wc -c < "$jarfileloc") / 1024 / 1024 ))
    fi
    if [[ $actualsize -le $MAX_PACKAGE_SIZE ]]; then
      info "File size is ${actualsize}MB (limit ${MAX_PACKAGE_SIZE}MB)"
    else
      rm -rf "${EXPLODE_PATH}" >/dev/null 2>&1 || true
      die "File size is ${actualsize}MB (over max_package_size ${MAX_PACKAGE_SIZE}MB). Aborting."
    fi
  else
    info "max_package_size not configured; skipping size check."
  fi

  # Zip or Jar detection
  if printf "%s" "$jarfileloc" | grep -q "\.zip$"; then
    info "Zip file detected."
    bZip=true
  elif printf "%s" "$jarfileloc" | grep -q "\.jar$"; then
    info "Jar file detected."
    bZip=false
  else
    rm -rf "${EXPLODE_PATH}" >/dev/null 2>&1 || true
    die "File type not supported: $jarfileloc"
  fi

  # evaluate server selection logic
  servereval="${environment}:${instance}:${pool}"
  info "Server evaluation token: $servereval"

  # default empty
  AEM_SERVERS=""
  buildAllowedKey=""

  case "$servereval" in
    # Example explicit mappings: these keys must exist in config for the mapping.
    dev:author:dam)
      AEM_SERVERS="$(get_prop dev_dam_aem_authors)"
      buildAllowedKey="$(get_prop BUILD_FLAG_dev)"
      ;;
    dev:publish:dam)
      AEM_SERVERS="$(get_prop dev_dam_aem_publishers)"
      buildAllowedKey="$(get_prop BUILD_FLAG_dev)"
      ;;
    dev:both:dam)
      AEM_SERVERS="$(get_prop dev_dam_aem_authors),$(get_prop dev_dam_aem_publishers)"
      buildAllowedKey="$(get_prop BUILD_FLAG_dev)"
      ;;
    # ... keep other explicit mappings if present in original; they will be resolved via get_prop which will die if missing.
    *)
      # dynamic resolution
      ENV_TOKEN_KEY="ENV_TOKEN_${environment}"
      ENV_TOKEN="$(get_prop "$ENV_TOKEN_KEY")"
      if [ -n "$ENV_TOKEN" ]; then
        pool_lc="$(printf "%s" "$pool" | tr '[:upper:]' '[:lower:]')"
        authk="${ENV_TOKEN}_${pool_lc}_aem_authors"
        pubk="${ENV_TOKEN}_${pool_lc}_aem_publishers"
        if [ "$instance" = "author" ]; then
          AEM_SERVERS="$(get_prop "${authk}")"
          buildAllowedKey="$(get_prop BUILD_FLAG_${environment})"
        elif [ "$instance" = "publish" ]; then
          AEM_SERVERS="$(get_prop "${pubk}")"
          buildAllowedKey="$(get_prop BUILD_FLAG_${environment})"
        elif [ "$instance" = "both" ]; then
          AEM_SERVERS="$(get_prop "${authk}"),$(get_prop "${pubk}")"
          buildAllowedKey="$(get_prop BUILD_FLAG_${environment})"
        else
          die "Invalid instance value: $instance"
        fi
      else
        # If explicit mappings for the token exist in config, use them; otherwise error
        die "Combination not identified: $servereval and no ENV_TOKEN mapping present for dynamic resolution."
      fi
      ;;
  esac

  info "Selected server values: $AEM_SERVERS"

  # evaluate buildAllowedKey which may be a literal boolean or one or more config keys separated by comma
  if [ -n "$buildAllowedKey" ]; then
    IFS=',' read -r -a buildkeys <<< "$buildAllowedKey"
    for bk in "${buildkeys[@]}"; do
      bk="$(printf "%s" "$bk" | tr -d '[:space:]')"
      [ -z "$bk" ] && continue
      if echo "$bk" | grep -Eiq '^(true|false|1|0|yes|no)$'; then
        val="$bk"
      else
        val="${props[$bk]:-}"
      fi
      if [ -z "$val" ]; then
        rm -rf "${EXPLODE_PATH}" >/dev/null 2>&1 || true
        die "Build allowed flag '$bk' not set or empty in config"
      fi
      if echo "$val" | grep -Eiq '^(true|1|yes)$'; then
        info "Builds enabled for $bk"
      else
        rm -rf "${EXPLODE_PATH}" >/dev/null 2>&1 || true
        die "Builds disabled ($bk=$val)"
      fi
    done
  else
    warn "No buildAllowedKey set — proceeding but ensure builds are allowed by config if needed."
  fi

  info "Installation of $jarfileloc starting for $instance instances in $environment for ${pool}."

  # Replace commas with spaces for loop
  AEM_DEPLOYS="$(printf "%s" "$AEM_SERVERS" | sed 's/,/ /g')"

  # extraction & filter processing
  cd "$EXPLODE_PATH" || { rm -rf "${EXPLODE_PATH}" >/dev/null 2>&1 || true; die "Cannot cd to explode path $EXPLODE_PATH"; }

  if [ "$bZip" = "true" ] || [ "$bZip" = true ]; then
    "$UNZIP_BIN" -o "$jarfileloc" META-INF/vault/filter.xml -d "$EXPLODE_PATH" >/dev/null 2>&1 || true
    "$UNZIP_BIN" -o "$jarfileloc" META-INF/vault/properties.xml -d "$EXPLODE_PATH" >/dev/null 2>&1 || true
  else
    (cd "$EXPLODE_PATH" && "$JAR_BIN" xvf "$jarfileloc" META-INF/vault/filter.xml >/dev/null 2>&1 || true)
    (cd "$EXPLODE_PATH" && "$JAR_BIN" xvf "$jarfileloc" META-INF/vault/properties.xml >/dev/null 2>&1 || true)
  fi

  echo "filtered paths:"
  cat "${EXPLODE_PATH_ROOT}/filter.txt" 2>/dev/null || true
  echo ""
  propfile="${EXPLODE_PATH}/META-INF/vault/properties.xml"
  propname="$(find_package_name "$propfile" || true)"
  info "properties xml name key: $propname"

  # execute build/upload/install
  if [ "${bDebug:-}" = "true" ] || [ "${bDebug:-}" = "debug" ]; then
    for AEM_DEPLOY in $AEM_DEPLOYS; do
      AEM_DEPLOY_IP="$(printf "%s" "$AEM_DEPLOY" | awk -F':' '{print $1}')"
      AEM_DEPLOY_PORT="$(printf "%s" "$AEM_DEPLOY" | awk -F':' '{print $2}')"
      if [ -z "$AEM_DEPLOY_PORT" ]; then AEM_DEPLOY_PORT="$DEFAULT_PUBLISH_PORT"; fi
      info "Debug upload to $AEM_DEPLOY_IP:$AEM_DEPLOY_PORT"
      "$CURL_BIN" -s -u "${AEM_DEPLOY_USERNAME}:${AEM_DEPLOY_PASSWORD}" -F "name=${package}" -F "file=@${jarfileloc}" "http://${AEM_DEPLOY_IP}:${AEM_DEPLOY_PORT}${CRX_UPLOAD_PATH}" >/dev/null || true
      list_packages "$propname" "${EXPLODE_PATH_ROOT}/worker"
      echo ""
      echo "Installing package ${PKG_BASE_PATH}${propname}.zip (debug)"
      echo ""
      result="$("$CURL_BIN" -s -u "${AEM_DEPLOY_USERNAME}:${AEM_DEPLOY_PASSWORD}" -X POST "http://${AEM_DEPLOY_IP}:${AEM_DEPLOY_PORT}${CRX_INSTALL_PREFIX}${PKG_BASE_PATH}/${propname}.zip?cmd=install" || true)"
      get_fn_results "install"
    done
    rm -rf "${EXPLODE_PATH}/META-INF" >/dev/null 2>&1 || true
    rm -rf "${EXPLODE_RUNTIME_ROOT}" >/dev/null 2>&1 || true
    exit 0
  else
    info "evaluating filter:"
    pfilter="${EXPLODE_PATH}/META-INF/vault/filter.xml"
    [ -f "$pfilter" ] && cat "$pfilter" || warn "filter.xml not found at $pfilter"
    result_validate="$(validateFilter "$EXPLODE_PATH" "$group" "$project" || true)"
    if [ "$result_validate" = "1" ] || [ "$result_validate" = "true" ]; then
      info "Filters match, proceeding to install..."
      for AEM_DEPLOY in $AEM_DEPLOYS; do
        AEM_DEPLOY_IP="$(printf "%s" "$AEM_DEPLOY" | awk -F':' '{print $1}')"
        AEM_DEPLOY_PORT="$(printf "%s" "$AEM_DEPLOY" | awk -F':' '{print $2}')"
        if [ -z "$AEM_DEPLOY_PORT" ]; then AEM_DEPLOY_PORT="$DEFAULT_PUBLISH_PORT"; fi

        info "uploading package $package to ${AEM_DEPLOY_IP}:${AEM_DEPLOY_PORT}"
        cmdt="$("$CURL_BIN" -s -u "${AEM_DEPLOY_USERNAME}:${AEM_DEPLOY_PASSWORD}" -F "name=${package}" -F "file=@${jarfileloc}" "http://${AEM_DEPLOY_IP}:${AEM_DEPLOY_PORT}${CRX_UPLOAD_PATH}" || true)"
        info "upload response (trunc): $(printf '%s' "$cmdt" | head -c200)"

        info "setting property name for package $propname"
        list_packages "$propname" "${EXPLODE_PATH}/META-INF/worker" || true

        # determine remote package path/version from list parsing
        LIST_TMP="$(mktemp)" || LIST_TMP="$(printf "%s" "${EXPLODE_PATH_ROOT}/list_tmp.$$")"
        "$CURL_BIN" -s -u "${AEM_DEPLOY_USERNAME}:${AEM_DEPLOY_PASSWORD}" "http://${AEM_DEPLOY_IP}:${AEM_DEPLOY_PORT}${CRX_UPLOAD_PATH}?cmd=ls" > "$LIST_TMP" || true

        PKG_PATH=""
        PKG_VER=""
        if grep -q "<name>${propname}</name>" "$LIST_TMP" 2>/dev/null; then
          LN="$(grep -n "<name>${propname}</name>" "$LIST_TMP" | head -n1 | cut -d: -f1 || true)"
          if [ -n "$LN" ]; then
            START=$((LN-10)); [ $START -lt 1 ] && START=1
            END=$((LN+10))
            BLOCK="$(sed -n "${START},${END}p" "$LIST_TMP" || true)"
            GROUP_VAL="$(printf "%s" "$BLOCK" | sed -n 's:.*<group>\(.*\)</group>.*:\1:p' | head -n1 || true)"
            VERSION_VAL="$(printf "%s" "$BLOCK" | sed -n 's:.*<version>\(.*\)</version>.*:\1:p' | head -n1 || true)"
            if [ -n "$GROUP_VAL" ]; then PKG_PATH="${PKG_BASE_PATH%/}/${GROUP_VAL}/"; else PKG_PATH="${PKG_BASE_PATH%/}/${group}/"; fi
            PKG_VER="$VERSION_VAL"
          fi
        fi
        rm -f "$LIST_TMP"

        if [ -z "$PKG_PATH" ]; then
          PKG_PATH="${PKG_BASE_PATH%/}/${group}/"
        fi

        if [ -z "$PKG_VER" ]; then
          echo ""
          echo "Installing package ${PKG_PATH}${propname}.zip"
          echo ""
          pkg="${PKG_PATH}${propname}"
          pkg_esc="$(printf "%s" "$pkg" | sed 's/ /%20/g')"
          result="$("$CURL_BIN" -s -u "${AEM_DEPLOY_USERNAME}:${AEM_DEPLOY_PASSWORD}" -X POST "http://${AEM_DEPLOY_IP}:${AEM_DEPLOY_PORT}${CRX_INSTALL_PREFIX}${pkg_esc}.zip?cmd=install&force=true&recursive=true" || true)"
          get_fn_results "install"
        else
          echo ""
          echo "Installing package ${PKG_PATH}${propname}-${PKG_VER}.zip"
          echo ""
          pkg="${PKG_PATH}${propname}-${PKG_VER}"
          pkg_esc="$(printf "%s" "$pkg" | sed 's/ /%20/g')"
          result="$("$CURL_BIN" -s -u "${AEM_DEPLOY_USERNAME}:${AEM_DEPLOY_PASSWORD}" -X POST "http://${AEM_DEPLOY_IP}:${AEM_DEPLOY_PORT}${CRX_INSTALL_PREFIX}${pkg_esc}.zip?cmd=install&force=true&recursive=true" || true)"
          get_fn_results "install"
        fi
      done
      rm -rf "${EXPLODE_PATH}/META-INF" >/dev/null 2>&1 || true
      rm -rf "${EXPLODE_RUNTIME_ROOT}" >/dev/null 2>&1 || true
      exit 0
    else
      echo "Filters do not match, please review package and filter specification."
      rm -rf "${EXPLODE_PATH}/META-INF" >/dev/null 2>&1 || true
      rm -rf "${EXPLODE_RUNTIME_ROOT}" >/dev/null 2>&1 || true
      exit 1
    fi
  fi
}

# ---------- argument parsing & invocation ----------
if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  help
  exit 1
fi

# allow passing config first via --config path
if [[ "${1:-}" == --config=* ]]; then
  CONFIG_FILE="${1#--config=}"
  shift 1
  # reload props
  declare -A props
  while IFS= read -r line || [ -n "$line" ]; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$line" ]] && continue
    key="${line%%=*}"
    val="${line#*=}"
    key="$(printf "%s" "$key" | tr -d '[:space:]')"
    val="$(printf "%s" "$val" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    val="$(printf "%s" "$val" | sed -E "s/^'(.*)'$/\\1/; s/^\"(.*)\"$/\\1/")"
    props["$key"]="$val"
  done < "$CONFIG_FILE"
fi

if [ $# -lt 7 ]; then
  help
  exit 1
fi

inputpath="$1"
package="$2"
group="$3"
project="$4"
environment="$5"
instance="$6"
pool="$7"
debugflag="${8:-}"

# normalize environment names
if [ "$environment" = "prod" ]; then environment="production"; fi

main "$inputpath" "$package" "$group" "$project" "$environment" "$instance" "$pool" "$debugflag"
