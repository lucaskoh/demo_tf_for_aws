#!/usr/bin/env bash
# The bootstrapper of an environment repository: a repository that holds only envs/<environment>/
# (values.yaml and apps/**) and names the platform to run in common.platform_source (a git URL) and
# common.platform_version (a tag). Copy this file to the root of that repository as `platform`.
#
# Usage: ./platform <environment> <layer> <terraform args...>     (like scripts/tf.sh)
#        ./platform <environment> validate                        (checks the files against the schemas of that version)
#        ./platform <environment> --show                          (prints the source and the version)
#
# It fetches that version of the platform into .platform/<version>-<commit>/ (once) and runs the
# scripts of that very version, so the code and the scripts always match. The data directories of
# Terraform go to .terraform-data/ of this repository. Needs bash and git. Add .platform/ and
# .terraform-data/ to .gitignore.
#
# The platform code runs with your AWS credentials: only use a source you trust, and protect its
# version tags (a tag that moves is fetched again as another folder and the commit is printed).

set -euo pipefail

here="${ENV_REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <environment> <layer> <terraform args...> | $0 <environment> validate | $0 <environment> --show" >&2
  exit 2
fi
env_name="$1"
shift

if ! [[ "$env_name" =~ ^[a-z0-9-]{1,20}$ ]]; then
  echo "Invalid environment name '$env_name'." >&2
  exit 2
fi
values="$here/envs/$env_name/values.yaml"
if [ ! -f "$values" ]; then
  echo "Unknown environment '$env_name': $values does not exist." >&2
  exit 2
fi

# Value of a key under "common:" (the same reader as scripts/common-value.sh: a test compares them)
common_value() {
  awk -v key="$1" '
    /^common:/ { in_common = 1; next }
    /^[^ #]/   { in_common = 0 }
    in_common && $1 == key ":" { print $2; exit }
  ' "$values" | sed -E 's/^["'\'']//; s/["'\'']$//'
}

source_url="$(common_value platform_source)"
version="$(common_value platform_version)"

if [ "$1" = "--show" ]; then
  echo "$source_url $version"
  exit 0
fi

if [ -z "$source_url" ] || [ -z "$version" ]; then
  echo "Set common.platform_source (a git URL) and common.platform_version (a tag such as v1.1.0) in $values." >&2
  exit 2
fi
if ! [[ "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "common.platform_version must be a version tag like v1.1.0 when platform_source is set, not '$version'." >&2
  exit 2
fi
case "$source_url" in
  github.com/*) url="https://$source_url.git" ;;
  *) url="$source_url" ;;
esac

# Which commit does the tag point to? (an annotated tag has a second line with ^{})
refs="$(git ls-remote "$url" "refs/tags/$version" "refs/tags/$version^{}")" || {
  echo "Could not read the tags of $url." >&2
  exit 1
}
commit="$(awk '/\^\{\}$/ { print $1; exit }' <<<"$refs")"
[ -n "$commit" ] || commit="$(awk 'NR == 1 { print $1 }' <<<"$refs")"
if [ -z "$commit" ]; then
  echo "Platform version $version does not exist in $url." >&2
  exit 1
fi

cache="$here/.platform/$version-${commit:0:10}"
if [ ! -f "$cache/.complete" ]; then
  mkdir -p "$here/.platform"
  tmp="$here/.platform/.tmp.$$"
  git clone --quiet --depth 1 --branch "$version" "$url" "$tmp"
  if [ "$(git -C "$tmp" rev-parse HEAD)" != "$commit" ]; then
    echo "The tag $version changed while it was fetched. Try again." >&2
    rm -rf -- "$tmp"
    exit 1
  fi
  touch "$tmp/.complete"
  rm -rf -- "$cache"
  mv "$tmp" "$cache"
fi
echo "platform: $source_url $version (${commit:0:10})" >&2

export PLATFORM_ENVS_DIR="$here/envs"
export PLATFORM_DATA_DIR="$here/.terraform-data"

if [ "$1" = "validate" ]; then
  exec "${PYTHON:-python3}" "$cache/scripts/validate-values.py" "$here/envs/$env_name"
fi
exec "$cache/scripts/tf.sh" "$env_name" "$@"
