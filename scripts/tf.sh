#!/usr/bin/env bash
# Runs terraform for one layer of one environment.
#
# Usage: scripts/tf.sh <environment> <layer> <terraform args...>
#   scripts/tf.sh demo network init
#   scripts/tf.sh demo network plan -out=tfplan
#
# - The layer code lives in layers/<layer>/ and is shared by all environments. An environment can
#   pin a released version of it with common.platform_version (a git tag such as v1.2.0): then the
#   code of that tag is used instead of the working tree (see scripts/prepare-platform.sh).
# - The environment is the folder envs/<environment>/ with a values.yaml. It is
#   passed to Terraform as TF_VAR_environment.
# - Backend: layers use a partial S3 backend. On `init`, bucket, region and key
#   are passed with -backend-config, taken from common.state_bucket and
#   common.region of envs/<environment>/values.yaml. They are read with awk (see
#   scripts/common-value.sh), so they must be written as "key: value" on one line
#   directly under `common:`; scripts/validate-values.py checks that in CI.
# - Environment repository mode: when PLATFORM_ENVS_DIR is set (scripts/platform.sh does it), the
#   environments are read from that folder instead of envs/ of this checkout, and this checkout is the
#   platform at the version the environment asked for. PLATFORM_DATA_DIR (default .terraform-data
#   here) says where the data directories and the plugin cache are kept.
# - The .terraform data directory is kept per environment and layer, so running
#   another environment never reuses the backend of a previous init. Providers
#   are shared through a plugin cache (TF_PLUGIN_CACHE_DIR).

set -euo pipefail

if [ "$#" -lt 3 ]; then
  echo "Usage: $0 <environment> <layer> <terraform args...>" >&2
  exit 2
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
env_name="$1"
layer="$2"
shift 2

if ! [[ "$env_name" =~ ^[a-z0-9-]{1,20}$ ]] || ! [[ "$layer" =~ ^[a-z0-9-]+$ ]]; then
  echo "Invalid environment or layer name (lowercase letters, digits and hyphens only)." >&2
  exit 2
fi

envs_dir="${PLATFORM_ENVS_DIR:-$root/envs}"
data_root="${PLATFORM_DATA_DIR:-$root/.terraform-data}"
values="$envs_dir/$env_name/values.yaml"
layer_dir="$root/layers/$layer"

if [ ! -f "$values" ]; then
  echo "Unknown environment '$env_name': $values does not exist." >&2
  echo "Available: $(find "$envs_dir" -mindepth 2 -maxdepth 2 -name values.yaml | sed -E 's#.*/([^/]+)/values.yaml#\1#' | sort | tr '\n' ' ')" >&2
  exit 2
fi
if [ ! -d "$layer_dir" ]; then
  echo "Unknown layer '$layer': $layer_dir does not exist." >&2
  exit 2
fi

# Value of a key under "common:" (see scripts/common-value.sh for what it can read)
common_value() {
  "$root/scripts/common-value.sh" "$values" "$1"
}

platform_version="$(common_value platform_version)"
if [ -n "${PLATFORM_ENVS_DIR:-}" ]; then
  # An environment repository runs this checkout; it must be the version the environment asked for
  if [ -n "$platform_version" ] && [ "$platform_version" != "main" ] &&
    ! git -C "$root" tag --points-at HEAD 2>/dev/null | grep -qx "$platform_version"; then
    echo "This platform checkout is not $platform_version (common.platform_version of $env_name). Run it through scripts/platform.sh." >&2
    exit 2
  fi
  code_root="$("$root/scripts/prepare-platform.sh" --from-checkout "$env_name")"
  layer_dir="$code_root/layers/$layer"
elif [ -n "$platform_version" ] && [ "$platform_version" != "main" ]; then
  # A pinned environment runs the code of its tag; the values and app files still come from this checkout
  code_root="$("$root/scripts/prepare-platform.sh" "$env_name" "$platform_version")"
  layer_dir="$code_root/layers/$layer"
  if [ ! -d "$layer_dir" ]; then
    echo "Layer '$layer' does not exist in platform version $platform_version." >&2
    exit 2
  fi
fi

export TF_VAR_environment="$env_name"
export TF_DATA_DIR="$data_root/$env_name/$layer"
# One shared provider cache: without it every environment and layer would keep its own
# copy of the (large) AWS provider.
export TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-$data_root/plugin-cache}"
mkdir -p "$TF_PLUGIN_CACHE_DIR"

args=("$@")

if [ "${args[0]}" = "init" ]; then
  skip_backend=false
  for a in "${args[@]}"; do
    [ "$a" = "-backend=false" ] && skip_backend=true
  done

  if [ "$skip_backend" = false ]; then
    bucket="$(common_value state_bucket)"
    region="$(common_value region)"
    if [ -z "$bucket" ] || [ -z "$region" ]; then
      echo "common.state_bucket and common.region must be set in $values" >&2
      exit 2
    fi
    args+=(
      "-reconfigure"
      "-backend-config=bucket=$bucket"
      "-backend-config=region=$region"
      "-backend-config=key=aws-multi-vpc/$env_name/$layer/terraform.tfstate"
    )
  fi
fi

exec terraform -chdir="$layer_dir" "${args[@]}"
