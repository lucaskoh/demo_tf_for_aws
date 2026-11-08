#!/usr/bin/env bash
# Runs terraform for one layer of one environment.
#
# Usage: scripts/tf.sh <environment> <layer> <terraform args...>
#   scripts/tf.sh demo network init
#   scripts/tf.sh demo network plan -out=tfplan
#
# - The layer code lives in layers/<layer>/ and is shared by all environments.
# - The environment is the folder envs/<environment>/ with a values.yaml. It is
#   passed to Terraform as TF_VAR_environment.
# - Backend: layers use a partial S3 backend. On `init`, bucket, region and key
#   are passed with -backend-config, taken from common.state_bucket and
#   common.region of envs/<environment>/values.yaml. These two keys must stay
#   flat (two-space indented, directly under `common:`), because they are read
#   with awk and not with a YAML parser.
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

values="$root/envs/$env_name/values.yaml"
layer_dir="$root/layers/$layer"

if [ ! -f "$values" ]; then
  echo "Unknown environment '$env_name': $values does not exist." >&2
  echo "Available: $(find "$root/envs" -mindepth 2 -maxdepth 2 -name values.yaml | sed -E 's#.*/envs/([^/]+)/values.yaml#\1#' | sort | tr '\n' ' ')" >&2
  exit 2
fi
if [ ! -d "$layer_dir" ]; then
  echo "Unknown layer '$layer': $layer_dir does not exist." >&2
  exit 2
fi

# Value of a flat key under "common:" (comments and quotes removed)
common_value() {
  awk -v key="$1" '
    /^common:/ { in_common = 1; next }
    /^[^ #]/   { in_common = 0 }
    in_common && $1 == key ":" { print $2; exit }
  ' "$values" | sed -E 's/^["'\'']//; s/["'\'']$//'
}

export TF_VAR_environment="$env_name"
export TF_DATA_DIR="$root/.terraform-data/$env_name/$layer"
# One shared provider cache: without it every environment and layer would keep its own
# copy of the (large) AWS provider.
export TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-$root/.terraform-data/plugin-cache}"
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
