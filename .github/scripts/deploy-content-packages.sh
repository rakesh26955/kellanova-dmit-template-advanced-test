#!/usr/bin/env bash
set -euo pipefail

# ---- Argument parsing (your original code likely already does this) ----
workspace=$1
group=$2
project=$3
environment=$4
instance=$5
pool=$6

echo "Arguments received:"
echo "  workspace=$workspace"
echo "  group=$group"
echo "  project=$project"
echo "  environment=$environment"
echo "  instance=$instance"
echo "  pool=$pool"

# ---- Navigate to workspace ----
if [ ! -d "$workspace" ]; then
  echo "❌ Workspace directory $workspace does not exist!"
  exit 1
fi

cd "$workspace"

# ---- Look for .zip packages ----
echo "Looking for .zip packages in $(pwd)..."
X=$(ls *.zip 2>/dev/null | wc -l)

if [ "$X" -eq 0 ]; then
  echo "⚠️ No packages found in path $(pwd). Skipping deployment."
  exit 0   # Exit successfully instead of failing
fi

echo "✅ Found $X package(s):"
ls -1 *.zip

# ---- Continue with your deployment logic below ----
# For example:
# for pkg in *.zip; do
#   echo "Deploying $pkg ..."
#   # deployment command here
# done
