#!/usr/bin/env bash
# Prepares the Terraform code of one platform version for one environment and prints the folder
# (it has layers/, modules/, templates/ and assets/, plus envs/<environment>/).
#
# Usage: scripts/prepare-platform.sh <environment> <version>      (version: vMAJOR.MINOR.PATCH)
#        scripts/prepare-platform.sh --from-checkout <environment>
#
# Called by scripts/tf.sh:
# - with <version> when envs/<environment>/values.yaml sets common.platform_version: the code is
#   taken from that git tag of this repository, not from the working tree.
# - with --from-checkout when PLATFORM_ENVS_DIR is set (an environment repository that runs this
#   platform, see scripts/platform.sh): the code is taken from this checkout, which is the platform
#   at the version the environment asked for.
# The tooling (scripts/, Makefile, .github/) and the schemas are never part of the folder.
#
# - envs/<environment>/ (the values and the app files) is copied on every call, from the working
#   tree (or from PLATFORM_ENVS_DIR), so what is planned is always the environment you are looking at.
# - A local layers/<layer>/terraform.tfvars is copied too (it is not in git).
# - The folder is <data>/<environment>/platform/<commit>/ (--from-checkout: .../external/<commit>/),
#   where <data> is PLATFORM_DATA_DIR (default .terraform-data). The code of a commit never changes,
#   so it is copied once and reused; files that Terraform leaves in it (a saved tfplan between plan
#   and apply) stay.
# - The tag must exist locally: git fetch --tags (CI checks out with fetch-depth: 0).

set -euo pipefail

from_checkout=false
if [ "${1:-}" = "--from-checkout" ]; then
  from_checkout=true
  shift
fi

if { [ "$from_checkout" = true ] && [ "$#" -ne 1 ]; } || { [ "$from_checkout" = false ] && [ "$#" -ne 2 ]; }; then
  echo "Usage: $0 <environment> <version> | $0 --from-checkout <environment>" >&2
  exit 2
fi

env_name="$1"
version="${2:-}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
data_root="${PLATFORM_DATA_DIR:-$root/.terraform-data}"
envs_src="${PLATFORM_ENVS_DIR:-$root/envs}"

if ! [[ "$env_name" =~ ^[a-z0-9-]{1,20}$ ]]; then
  echo "Invalid environment name '$env_name'." >&2
  exit 2
fi

if [ "$from_checkout" = true ]; then
  # The code of this checkout (the platform at the version that was fetched)
  commit="$(git -C "$root" rev-parse --verify --quiet HEAD || echo unversioned)"
  dest="$data_root/$env_name/external/$commit"
  copy_code() { # <destination>
    for p in layers modules templates assets; do
      if [ -d "$root/$p" ]; then
        cp -R "$root/$p" "$1/$p"
      fi
    done
  }
else
  if ! [[ "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "common.platform_version must be 'main' or a version tag like v1.2.0, not '$version'." >&2
    exit 2
  fi

  if ! commit="$(git -C "$root" rev-parse --verify --quiet "refs/tags/$version^{commit}")"; then
    echo "Platform version $version of environment '$env_name' does not exist as a git tag here." >&2
    echo "Fetch the tags (git fetch --tags; in CI use fetch-depth: 0), or fix common.platform_version in envs/$env_name/values.yaml." >&2
    exit 1
  fi

  dest="$data_root/$env_name/platform/$commit"
  copy_code() { # <destination>
    local paths=() p
    for p in layers modules templates assets; do
      if git -C "$root" cat-file -e "$commit:$p" 2>/dev/null; then
        paths+=("$p")
      fi
    done
    if ! [[ " ${paths[*]} " == *" layers "* && " ${paths[*]} " == *" modules "* ]]; then
      echo "Tag $version has no layers/ and modules/: it is not a platform release." >&2
      return 1
    fi
    git -C "$root" archive "$commit" -- "${paths[@]}" | tar -x -C "$1"
  }
fi

if [ ! -f "$dest/.complete" ]; then
  tmp="$dest.tmp.$$"
  mkdir -p "$tmp"
  if ! copy_code "$tmp"; then
    rm -rf -- "$tmp"
    exit 1
  fi
  touch "$tmp/.complete"
  rm -rf -- "$dest"
  mv "$tmp" "$dest"
fi

# The environment always comes from the working tree (or from PLATFORM_ENVS_DIR)
rm -rf -- "${dest:?}/envs/$env_name"
mkdir -p "$dest/envs"
cp -R "$envs_src/$env_name" "$dest/envs/$env_name"

for f in "$root"/layers/*/terraform.tfvars; do
  [ -f "$f" ] || continue
  layer="$(basename "$(dirname "$f")")"
  if [ -d "$dest/layers/$layer" ]; then
    cp "$f" "$dest/layers/$layer/terraform.tfvars"
  fi
done

echo "platform code: ${version:-checkout} (${commit:0:10})" >&2
echo "$dest"
