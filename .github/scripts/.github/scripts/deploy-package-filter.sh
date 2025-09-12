#!/bin/sh
set -euo pipefail

################################################################################
# Deploy script (no hardcoded values)
#
# Required environment variables (must be exported in caller / CI):
#   CONFIG_FILE        -> path to server.properties (required)
#   WORKSPACE_ROOT     -> root workspace path (required)
#   CURL_BIN           -> path to curl binary (required)
#   JAR_BIN            -> path to jar binary (required)
#   UNZIP_BIN          -> path to unzip binary (required)
# Optional environment variables:
#   CURL_OPTS          -> extra curl options (e.g. "-sS -m 30 --retry 3")
#   DEBUG              -> if "true" enables debug (no install calls)
#
# Script arguments:
#   $1 = PackagePath  (dir containing package files, trailing slash optional)
#   $2 = PackageName  (name prefix to search for)
#   $3 = Group        (group name used in workspace path)
#   $4 = ProjectName  (project name used in workspace path)
#   $5 = Environment  (e.g., dev, stg, prd, devqa, preview, uatkfr, etc.)
#   $6 = Instance     (author|publish|both)
#   $7 = Pool         (kstl|kfr|gen|dam|... — must correspond to keys in server.properties)
#
# Behavior notes:
# - All server host values must be present in CONFIG_FILE (server.properties) and include host:port when needed.
# - The script sources CONFIG_FILE into environment variables (export KEY="value").
# - The script finds server lists by matching exported variable names that contain environment and pool and "author"/"publish".
# - Script will exit if it cannot find required variables in CONFIG_FILE or if any required env var is missing.
################################################################################

# -------------------------
# Helper: error & usage
# -------------------------
die() {
    echo "ERROR: $*" >&2
    exit 1
}

usage() {
    echo "Usage: $0 <PackagePath> <PackageName> <Group> <ProjectName> <Environment> <Instance> <Pool>"
    echo "Please export required environment variables before running (see top of script)."
    exit 1
}

# -------------------------
# Validate required envs
# -------------------------
: "${CONFIG_FILE:?}"       # fail if not set
: "${WORKSPACE_ROOT:?}"
: "${CURL_BIN:?}"
: "${JAR_BIN:?}"
: "${UNZIP_BIN:?}"
# optional
CURL_OPTS=${CURL_OPTS:-}
DEBUG=${DEBUG:-false}

# -------------------------
# Validate args
# -------------------------
[ "$#" -ge 7 ] || usage

inputpath=$1
package=$2
group=$3
project=$4
environment=$5
instance=$6
pool=$7

# normalize
lower() { echo "$1" | tr '[:upper:]' '[:lower:]'; }
environment=$(lower "$environment")
instance=$(lower "$instance")
pool=$(lower "$pool")

# ensure inputpath ends with slash
case "$inputpath" in */) ;; *) inputpath="$inputpath/";; esac

# -------------------------
# Source server.properties safely
# -------------------------
if [ ! -f "$CONFIG_FILE" ]; then
    die "CONFIG_FILE '$CONFIG_FILE' not found"
fi

# create sanitized temp file to export properties
cfg_tmp=$(mktemp)
# drop comments and blanks, wrap values in double quotes if not already, export KEY="value"
grep -E -v '^\s*#' "$CONFIG_FILE" | sed -E '/^\s*$/d' | while IFS= read -r line; do
    # skip if no '='
    echo "$line" | grep -q "=" || continue
    key=$(echo "$line" | cut -d'=' -f1 | tr -d '[:space:]')
    val=$(echo "$line" | cut -d'=' -f2-)
    # trim
    val=$(echo "$val" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    # convert single quotes to double and ensure quoted
    if echo "$val" | grep -q "^'.*'\$"; then
        val=$(echo "$val" | sed -E "s/^'(.*)'$/\"\\1\"/")
    elif echo "$val" | grep -q '^".*"$'; then
        # keep
        :
    else
        val="\"$val\""
    fi
    printf "export %s=%s\n" "$key" "$val" >> "$cfg_tmp"
done

# shellcheck source=/dev/null
. "$cfg_tmp"
rm -f "$cfg_tmp"

# After sourcing, server.properties keys are exported to env (e.g. dev_kstl_aem_authors=...).
# check that build credentials exist (aem_build_user)
if [ -z "${aem_build_user:-}" ]; then
    die "aem_build_user not found in $CONFIG_FILE (expected 'aem_build_user=<user>:<password>')"
fi

# parse username:password (handles quotes)
AEM_DEPLOY_USERNAME=$(echo "$aem_build_user" | awk -F: '{print $1}' | sed -e "s/^'//" -e "s/'$//" -e 's/^"//' -e 's/"$//')
AEM_DEPLOY_PASSWORD=$(echo "$aem_build_user" | awk -F: '{print $2}' | sed -e "s/^'//" -e "s/'$//" -e 's/^"//' -e 's/"$//')

if [ -z "$AEM_DEPLOY_USERNAME" ] || [ -z "$AEM_DEPLOY_PASSWORD" ]; then
    die "Parsed aem_build_user is empty (check CONFIG_FILE). Expected format: user:password"
fi

# -------------------------
# Find matching AEM server variables from exported properties
# Strategy:
#  - Search environment variables (exported from server.properties) for names containing
#    the tokens for environment and pool and either 'author' or 'publish' (case-insensitive).
#  - For instance=both, we collect both author & publisher lists.
# -------------------------
env_token="$environment"
pool_token="$pool"

# helper: lowercased env list of variables
matched_authors=""
matched_publishers=""

# iterate over environment variables and find keys that match tokens
# use 'env' to list exported variables from properties (format KEY=VALUE)
env | while IFS= read -r line; do
    key=$(printf "%s" "$line" | cut -d'=' -f1)
    key_lc=$(lower "$key")
    val=$(printf "%s" "$line" | cut -d'=' -f2-)
    # match both tokens
    if echo "$key_lc" | grep -q "$env_token" && echo "$key_lc" | grep -q "$pool_token"; then
        if echo "$key_lc" | grep -q "author"; then
            # append value (strip surrounding quotes if any)
            # use eval-safe approach to preserve commas in values
            v=$(printf "%s" "$val" | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")
            if [ -z "$matched_authors" ]; then
                matched_authors="$v"
            else
                matched_authors="$matched_authors,$v"
            fi
        fi
        if echo "$key_lc" | grep -q "publish"; then
            v=$(printf "%s" "$val" | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")
            if [ -z "$matched_publishers" ]; then
                matched_publishers="$v"
            else
                matched_publishers="$matched_publishers,$v"
            fi
        fi
    fi
done

# Because the while loop above runs in a subshell, transfer matched values back:
# We'll reconstruct by grepping env again (shell-friendly)
get_matched() {
    pattern_env="$1"
    pattern_pool="$2"
    pattern_role="$3"   # author or publish or both
    out=""
    while IFS= read -r line; do
        k=$(printf "%s" "$line" | cut -d'=' -f1)
        k_lc=$(lower "$k")
        v=$(printf "%s" "$line" | cut -d'=' -f2-)
        v=$(printf "%s" "$v" | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")
        if echo "$k_lc" | grep -q "$pattern_env" && echo "$k_lc" | grep -q "$pattern_pool"; then
            if [ "$pattern_role" = "author" ] && echo "$k_lc" | grep -q "author"; then
                out=$(printf "%s,%s" "$out" "$v")
            elif [ "$pattern_role" = "publish" ] && echo "$k_lc" | grep -q "publish"; then
                out=$(printf "%s,%s" "$out" "$v")
            elif [ "$pattern_role" = "both" ]; then
                if echo "$k_lc" | grep -q "author"; then out=$(printf "%s,%s" "$out" "$v"); fi
                if echo "$k_lc" | grep -q "publish"; then out=$(printf "%s,%s" "$out" "$v"); fi
            fi
        fi
    done <<EOF
$(env)
EOF
    # trim leading comma
    echo "$out" | sed -E 's/^,+//; s/,,+/,/g; s/,$//'
}

case "$instance" in
    author)  AEM_SERVERS=$(get_matched "$env_token" "$pool_token" "author") ;;
    publish) AEM_SERVERS=$(get_matched "$env_token" "$pool_token" "publish") ;;
    both)    AEM_SERVERS=$(get_matched "$env_token" "$pool_token" "both") ;;
    *) die "Unknown instance '$instance'. Use author|publish|both." ;;
esac

[ -n "$AEM_SERVERS" ] || die "No servers found for environment='$environment' pool='$pool' instance='$instance' in $CONFIG_FILE"

# remove duplicate commas and spaces
AEM_SERVERS=$(echo "$AEM_SERVERS" | sed -E 's/,[[:space:]]*/,/g' | sed -E 's/^,+//; s/,+$//')

echo "Resolved AEM_SERVERS: $AEM_SERVERS"

# Determine buildAllowed variable name in properties: look for <env>_build_allowed or fallback to <env>_build_allowed alias
buildAllowedVarCandidates="${environment}_build_allowed ${environment}_build_allowed"
buildAllowed=""
for cand in $buildAllowedVarCandidates; do
    # use env to check
    v=$(env | awk -F= -v k="$cand" '$1==k{print substr($0, index($0, "=")+1)}')
    if [ -n "$v" ]; then
        buildAllowed="$v"
        break
    fi
done
# fallback: try common variants (dev, stage->stage_build_allowed, production->production_build_allowed)
if [ -z "$buildAllowed" ]; then
    buildAllowed=$(env | awk -F= -v pat="${environment}_build_allowed" 'tolower($1)~tolower(pat){print substr($0, index($0,"=")+1)}' || true)
fi

if [ -z "$buildAllowed" ]; then
    die "Could not find build permission variable for environment '$environment' in $CONFIG_FILE (expected e.g. ${environment}_build_allowed)"
fi

# parse buildAllowed and ensure at least one 'true' entry
ok=false
echo "Build policy: $buildAllowed"
for token in $(echo "$buildAllowed" | sed 's/,/ /g'); do
    if echo "$token" | grep -qi "true"; then ok=true; fi
done
if [ "$ok" != "true" ]; then
    die "Builds are not allowed for environment '$environment' per buildAllowed='$buildAllowed'"
fi

# -------------------------
# Find package file and check size
# -------------------------
[ -d "$inputpath" ] || die "inputpath '$inputpath' does not exist"

# find latest file whose name starts with package
jarfileloc=$(ls -t "$inputpath" | grep -E "^$package" | head -n1 || true)
[ -n "$jarfileloc" ] || die "No file matching '^$package' found in $inputpath"
jarfileloc="$inputpath$jarfileloc"
[ -f "$jarfileloc" ] || die "Selected package file '$jarfileloc' does not exist"

echo "Selected package: $jarfileloc"

# file size check — server.properties may expose max_package_size variable name
if [ -n "${max_package_size:-}" ]; then
    # interpret max_package_size as megabytes
    max_mb=$(printf "%s" "$max_package_size" | sed -E 's/[^0-9]*//g')
    if command -v du >/dev/null 2>&1; then
        actual_mb=$(du -m "$jarfileloc" | awk '{print $1}')
    else
        bytes=$(wc -c < "$jarfileloc")
        actual_mb=$((bytes / 1024 / 1024))
    fi
    if [ "$actual_mb" -ge "$max_mb" ]; then
        die "Package size ${actual_mb}MB exceeds allowed max_package_size ${max_mb}MB"
    fi
    echo "Package size ${actual_mb}MB within limit ${max_mb}MB"
else
    echo "Warning: max_package_size not defined in $CONFIG_FILE — skipping size check"
fi

# detect zip or jar
bZip=false
case "$jarfileloc" in
    *.zip) bZip=true ;;
    *.jar) bZip=false ;;
    *) die "Unsupported package type (not .zip or .jar): $jarfileloc" ;;
esac

# -------------------------
# Prepare workspace / temp paths (no hardcoded root - use WORKSPACE_ROOT)
# -------------------------
explodePathRoot="${WORKSPACE_ROOT%/}/${group}/${project}"
explodePath="${explodePathRoot}/temp"
mkdir -p "$explodePath"
# ensure filter.txt exists (mimic original behaviour) but keep location controlled by WORKSPACE_ROOT
if [ ! -f "${explodePathRoot}/../filter.txt" ]; then
    # create at workspace level if missing
    mkdir -p "$(dirname "${explodePathRoot}/../filter.txt")" || true
    echo '/' > "${explodePathRoot}/../filter.txt"
fi

# -------------------------
# Extract META-INF/vault/{filter.xml,properties.xml}
# -------------------------
if [ "$bZip" = "true" ]; then
    "$UNZIP_BIN" -o "$jarfileloc" "META-INF/vault/filter.xml" -d "$explodePath" >/dev/null 2>&1 || true
    "$UNZIP_BIN" -o "$jarfileloc" "META-INF/vault/properties.xml" -d "$explodePath" >/dev/null 2>&1 || true
else
    # use jar to extract into explodePath, with fallback to copying whole META-INF if needed
    (cd "$explodePath" && "$JAR_BIN" xvf "$jarfileloc" "META-INF/vault/filter.xml" >/dev/null 2>&1 || true)
    (cd "$explodePath" && "$JAR_BIN" xvf "$jarfileloc" "META-INF/vault/properties.xml" >/dev/null 2>&1 || true)
fi

propfile="${explodePath}/META-INF/vault/properties.xml"
propname=""
if [ -f "$propfile" ]; then
    while IFS= read -r i; do
        if echo "$i" | grep -q "<name>"; then
            propname=$(echo "$i" | cut -f2 -d">" | cut -f1 -d"<")
            break
        fi
    done < "$propfile"
fi
# fallback to package name if not found
if [ -z "$propname" ]; then
    propname="$package"
fi
echo "Package property name: $propname"

# -------------------------
# list_packages function (uses CURL_BIN and AEM credentials)
# returns: sets global variables 'pkg_path' and 'pkg_version' (if found)
# -------------------------
pkg_path=""
pkg_version=""
list_packages() {
    local server_ip="$1"
    local server_port="$2"
    local tmpout="$3"
    pkg_path=""
    pkg_version=""
    "$CURL_BIN" $CURL_OPTS -u "${AEM_DEPLOY_USERNAME}:${AEM_DEPLOY_PASSWORD}" \
        "http://${server_ip}:${server_port}/crx/packmgr/service.jsp?cmd=ls" > "$tmpout" 2>/dev/null || true

    # parse XML-style output for <name> entries and the preceding group
    # We attempt to find <name>propname</name> and then look back for the group node
    if grep -q "<name>$propname</name>" "$tmpout"; then
        # find the line number of matched <name>
        line_no=$(grep -n "<name>$propname</name>" "$tmpout" | head -n1 | cut -d: -f1)
        # look backwards for the group entry (approximate by finding previous <group>...</group> or parent path)
        # simpler approach: attempt to extract parent path from previous lines
        # fallback to /etc/packages/<group> if not discovered
        group_line=$(sed -n "$((line_no-5)),$line_no p" "$tmpout" | grep -Eo "<group>[^<]*</group>" | tail -n1 || true)
        if [ -n "$group_line" ]; then
            groupval=$(echo "$group_line" | sed -E 's/<\/?group>//g' | tr -d '[:space:]')
            pkg_path="/etc/packages/${groupval}/"
        else
            # best-effort: look for path-like token in previous lines
            path_guess=$(sed -n "$((line_no-5)),$line_no p" "$tmpout" | grep -Eo "/etc/packages/[^<[:space:]]+" | head -n1 || true)
            if [ -n "$path_guess" ]; then
                pkg_path="$path_guess/"
            else
                # fallback: empty (we will fail later if install cannot be constructed)
                pkg_path=""
            fi
        fi
        # attempt to find version from following lines (if any)
        version_line=$(sed -n "$line_no,$((line_no+5)) p" "$tmpout" | grep -Eo "<version>[^<]*</version>" | head -n1 || true)
        if [ -n "$version_line" ]; then
            pkg_version=$(echo "$version_line" | sed -E 's/<\/?version>//g' | tr -d '[:space:]')
        fi
    fi
}

# -------------------------
# Upload & Install loop
# -------------------------
# Convert AEM_SERVERS (comma separated) to words
IFS=',' read -r -a server_array <<EOF
$AEM_SERVERS
EOF

for server in "${server_array[@]}"; do
    server=$(echo "$server" | sed -e 's/^ *//' -e 's/ *$//')
    # extract host and port (if provided)
    host=$(echo "$server" | awk -F: '{print $1}')
    port=$(echo "$server" | awk -F: '{print $2}')
    if [ -z "$host" ]; then
        echo "Skipping empty server entry"
        continue
    fi
    if [ -z "$port" ]; then
        die "Server entry '$server' missing port. Please ensure CONFIG_FILE has host:port entries for all servers."
    fi

    echo "Uploading to $host:$port"

    # Upload package
    upload_response=$("$CURL_BIN" $CURL_OPTS -s -u "${AEM_DEPLOY_USERNAME}:${AEM_DEPLOY_PASSWORD}" \
        -F "name=${package}" -F "file=@${jarfileloc}" \
        "http://${host}:${port}/crx/packmgr/service.jsp" || true)
    echo "Upload response (truncated): $(printf "%s" "$upload_response" | head -c 400)"

    # create a temporary listing file
    tmp_listing="$(mktemp)"
    list_packages "$host" "$port" "$tmp_listing"

    if [ -z "${pkg_path:-}" ]; then
        rm -f "$tmp_listing"
        die "Could not determine package path on server $host:$port for package '$propname'. list_packages failed to extract path."
    fi

    # prepare install URL (choose versioned name if pkg_version found)
    if [ -n "${pkg_version}" ]; then
        pkg_full="${pkg_path}${propname}-${pkg_version}.zip"
    else
        pkg_full="${pkg_path}${propname}.zip"
    fi

    # url-encode spaces (basic)
    pkg_url=$(printf "%s" "$pkg_full" | sed 's/ /%20/g')

    install_url="http://${host}:${port}/crx/packmgr/service/.json${pkg_url}?cmd=install&force=true&recursive=true"
    echo "Installing $pkg_full on $host:$port"

    if [ "$DEBUG" = "true" ]; then
        echo "[DEBUG] SKIPPING install call: $install_url"
    else
        result=$("$CURL_BIN" $CURL_OPTS -s -u "${AEM_DEPLOY_USERNAME}:${AEM_DEPLOY_PASSWORD}" -X POST "$install_url" || true)
        # basic success check
        if echo "$result" | grep -qi "success"; then
            echo "Install reported success on $host"
        else
            echo "Install response (truncated): $(printf "%s" "$result" | head -c 400)"
            rm -f "$tmp_listing"
            die "Installation failed or did not return success on $host:$port"
        fi
    fi

    rm -f "$tmp_listing"
done

# cleanup extracted META-INF if present
rm -rf "${explodePath}/META-INF" || true

echo "Deployment completed successfully."
exit 0
