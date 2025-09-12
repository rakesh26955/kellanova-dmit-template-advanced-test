#!/usr/bin/env bash
set -euo pipefail

die(){ echo "ERROR: $*" >&2; exit 1; }
info(){ echo "INFO: $*"; }
warn(){ echo "WARN: $*" >&2; }

if [ -n "${SERVER_CONFIG:-}" ]; then
  CONFIG_FILE="${SERVER_CONFIG}"
else
  CONFIG_FILE="config/server.properties"
fi
[ -f "$CONFIG_FILE" ] || die "Config file not found: $CONFIG_FILE"

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

get_prop_fail(){ k="$1"; v="${props[$k]:-}"; [ -n "$v" ] || die "Required config key '$k' missing in $CONFIG_FILE"; printf "%s" "$v"; }
get_prop(){ printf "%s" "${props[$1]:-}"; }

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

CHECKFILTER_CMD="$(get_prop CHECKFILTER_CMD)"

AEM_BUILD_USER_RAW="$(get_prop_fail aem_build_user)"
AEM_BUILD_USER_RAW="$(printf "%s" "$AEM_BUILD_USER_RAW" | sed -E "s/^['\"]//; s/['\"]$//")"
AEM_DEPLOY_USERNAME="$(printf "%s" "$AEM_BUILD_USER_RAW" | awk -F: '{print $1}')"
AEM_DEPLOY_PASSWORD="$(printf "%s" "$AEM_BUILD_USER_RAW" | awk -F: '{print $2}')"
[ -n "$AEM_DEPLOY_USERNAME" ] || die "Invalid aem_build_user value (username missing)"
[ -n "$AEM_DEPLOY_PASSWORD" ] || die "Invalid aem_build_user value (password missing)"

EXPLODE_ROOT_DIR="${EXPLODE_ROOT%/}"
if [ ! -d "$EXPLODE_ROOT_DIR" ]; then
  mkdir -p "$EXPLODE_ROOT_DIR" || die "Unable to create EXPLODE_ROOT directory: $EXPLODE_ROOT_DIR"
fi

if command -v mktemp >/dev/null 2>&1; then
  EXPLODE_RUNTIME_ROOT="$(mktemp -d "${EXPLODE_ROOT_DIR}/explode.XXXXXX" 2>/dev/null || mktemp -d "/tmp/explode.XXXXXX")"
else
  EXPLODE_RUNTIME_ROOT="$(date +%s)_$$"
  EXPLODE_RUNTIME_ROOT="${EXPLODE_ROOT_DIR%/}/explode.${EXPLODE_RUNTIME_ROOT}"
  mkdir -p "$EXPLODE_RUNTIME_ROOT" || die "Cannot create runtime explode dir: $EXPLODE_RUNTIME_ROOT"
fi

EXPLODE_PATH="${EXPLODE_RUNTIME_ROOT}"
EXPLODE_PATH_ROOT="${EXPLODE_RUNTIME_ROOT}"

help(){ echo "invalid number of arguments or help requested"; echo "parameters: PackagePath PackageNamePrefix Group Project Environment Instance Pool [debug]"; }

validateFilter(){
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
  if [ $rc -eq 0 ]; then
    if echo "$out" | grep -Eiq "(^|[^a-zA-Z0-9])(1|true)([^a-zA-Z0-9]|$)"; then
      echo 1
      return 0
    fi
    echo 1
    return 0
  fi
  echo 0
  return 1
}

get_fn_results(){
  if [ -z "${result:-}" ]; then
    die "get_fn_results called but result variable empty"
  fi
  tmp="$result"
  tmp="$(printf "%s" "$tmp" | sed -E 's/^[\[\(]//; s/[\]\)]$//')"
  IFS=',' read -ra RES <<< "$tmp"
  success="${RES[0]:-}"
  message="${RES[1]:-}"
  success="$(printf "%s" "$success" | tr -d '[:space:]')"
  message="$(printf "%s" "$message" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  if echo "$success" | grep -Eiq "true|1"; then
    echo ""; echo "Successfully processed command."; echo ""
    return 0
  else
    echo ""; echo "Function failed with error: $message"; echo ""
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
  packagevar="$1"
  packagetst="$2"
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
    echo ""; echo "Package not found $packagevar!"; echo ""
  fi
}

main(){ 
  inputpath="$1"; package="$2"; group="$3"; project="$4"; environment="$5"; instance="$6"; pool="$7"; bDebug="${8:-}"
  info "Looking for package prefix '$package' in '$inputpath'"
  if [ -d "$inputpath" ]; then
    jarfileloc="$(ls -t "$inputpath" 2>/dev/null | grep -E "^${package}" | head -n1 || true)"
    jarfileloc="${inputpath%/}/${jarfileloc}"
  else
    jarfileloc="$inputpath"
  fi
  [ -f "$jarfileloc" ] || die "Package file not found: $jarfileloc"
  info "Package path: $jarfileloc"

  EXPLODE_PATH="${EXPLODE_RUNTIME_ROOT%/}/${package}"
  EXPLODE_PATH_ROOT="${EXPLODE_RUNTIME_ROOT%/}"
  rm -rf "$EXPLODE_PATH" || true
  mkdir -p "$EXPLODE_PATH" || die "Cannot create explode path $EXPLODE_PATH"

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
    die "Combination not identified: ${environment}:${instance}:${pool} and no ENV_TOKEN mapping present for dynamic resolution."
  fi

  info "Selected server values: $AEM_SERVERS"
  AEM_DEPLOYS="$(printf "%s" "$AEM_SERVERS" | sed 's/,/ /g')"

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
  fi

  result_validate="$(validateFilter "$EXPLODE_PATH" "$group" "$project" || true)"
  if [ "$result_validate" = "1" ] || [ "$result_validate" = "true" ]; then
    for AEM_DEPLOY in $AEM_DEPLOYS; do
      AEM_DEPLOY_IP="$(printf "%s" "$AEM_DEPLOY" | awk -F':' '{print $1}')"
      AEM_DEPLOY_PORT="$(printf "%s" "$AEM_DEPLOY" | awk -F':' '{print $2}')"
      if [ -z "$AEM_DEPLOY_PORT" ]; then AEM_DEPLOY_PORT="$DEFAULT_PUBLISH_PORT"; fi

      cmdt="$("$CURL_BIN" -s -u "${AEM_DEPLOY_USERNAME}:${AEM_DEPLOY_PASSWORD}" -F "name=${package}" -F "file=@${jarfileloc}" "http://${AEM_DEPLOY_IP}:${AEM_DEPLOY_PORT}${CRX_UPLOAD_PATH}" || true)"
      info "upload response (trunc): $(printf '%s' "$cmdt" | head -c200)"
      list_packages "$propname" "${EXPLODE_PATH}/META-INF/worker" || true

      LIST_TMP="$(mktemp)" || LIST_TMP="${EXPLODE_PATH_ROOT}/list_tmp.$$"
      "$CURL_BIN" -s -u "${AEM_DEPLOY_USERNAME}:${AEM_DEPLOY_PASSWORD}" "http://${AEM_DEPLOY_IP}:${AEM_DEPLOY_PORT}${CRX_UPLOAD_PATH}?cmd=ls" > "$LIST_TMP" || true

      PKG_PATH=""; PKG_VER=""
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

      if [ -z "$PKG_VER" ]; then
        pkg="${PKG_PATH}${propname}"
        pkg_esc="$(printf "%s" "$pkg" | sed 's/ /%20/g')"
        result="$("$CURL_BIN" -s -u "${AEM_DEPLOY_USERNAME}:${AEM_DEPLOY_PASSWORD}" -X POST "http://${AEM_DEPLOY_IP}:${AEM_DEPLOY_PORT}${CRX_INSTALL_PREFIX}${pkg_esc}.zip?cmd=install&force=true&recursive=true" || true)"
        get_fn_results "install"
      else
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
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  help
  exit 1
fi

if [[ "${1:-}" == --config=* ]]; then
  CONFIG_FILE="${1#--config=}"
  shift 1
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

if [ "$environment" = "prod" ]; then environment="production"; fi

main "$inputpath" "$package" "$group" "$project" "$environment" "$instance" "$pool" "$debugflag"
