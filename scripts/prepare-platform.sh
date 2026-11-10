#!/usr/bin/env bash
# Prepares the Terraform code of a released platform version for one environment and prints the
# folder (it has layers/, modules/, templates/ and assets/, plus envs/<environment>/).
#
# Usage: scripts/prepare-platform.sh <environment> <version>      (version: vMAJOR.MINOR.PATCH)
#
# Called by scripts/tf.sh when envs/<environment>/values.yaml sets common.platform_version.
#
# - The code (layers/, modules/, templates/, assets/) is taken from the git tag, not from the
#   working tree. The tooling (scripts/, Makefile, .github/) and the schemas always come from the
#   working tree.
# - envs/<environment>/ (the values and the app files) is copied from the working tree on every
#   call, so what is planned is always the environment of the commit you are on.
# - A local layers/<layer>/terraform.tfvars is copied too (it is not in git).
# - The folder is .terraform-data/<environment>/platform/<commit>/. The code of a tag never changes,
#   so it is extracted once and reused; files that Terraform leaves in it (a saved tfplan between
#   plan and apply) stay.
# - The tag must exist locally: git fetch --tags (CI checks out with fetch-depth: 0).

set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <environment> <version>" >&2
  exit 2
fi

env_name="$1"
version="$2"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! [[ "$env_name" =~ ^[a-z0-9-]{1,20}$ ]]; then
  echo "Invalid environment name '$env_name'." >&2
  exit 2
fi
if ! [[ "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "common.platform_version must be 'main' or a version tag like v1.2.0, not '$version'." >&2
  exit 2
fi

if ! commit="$(git -C "$root" rev-parse --verify --quiet "refs/tags/$version^{commit}")"; then
  echo "Platform version $version of environment '$env_name' does not exist as a git tag here." >&2
  echo "Fetch the tags (git fetch --tags; in CI use fetch-depth: 0), or fix common.platform_version in envs/$env_name/values.yaml." >&2
  exit 1
fi

dest="$root/.terraform-data/$env_name/platform/$commit"

if [ ! -f "$dest/.complete" ]; then
  tmp="$dest.tmp.$$"
  mkdir -p "$tmp"
  paths=()
  for p in layers modules templates assets; do
    if git -C "$root" cat-file -e "$commit:$p" 2>/dev/null; then
      paths+=("$p")
    fi
  done
  if ! [[ " ${paths[*]} " == *" layers "* && " ${paths[*]} " == *" modules "* ]]; then
    echo "Tag $version has no layers/ and modules/: it is not a platform release." >&2
    rm -rf -- "$tmp"
    exit 1
  fi
  git -C "$root" archive "$commit" -- "${paths[@]}" | tar -x -C "$tmp"
  touch "$tmp/.complete"
  rm -rf -- "$dest"
  mv "$tmp" "$dest"
fi

# The environment always comes from the working tree
rm -rf -- "${dest:?}/envs/$env_name"
mkdir -p "$dest/envs"
cp -R "$root/envs/$env_name" "$dest/envs/$env_name"

for f in "$root"/layers/*/terraform.tfvars; do
  [ -f "$f" ] || continue
  layer="$(basename "$(dirname "$f")")"
  if [ -d "$dest/layers/$layer" ]; then
    cp "$f" "$dest/layers/$layer/terraform.tfvars"
  fi
done

echo "platform code: $version (${commit:0:10})" >&2
echo "$dest"
