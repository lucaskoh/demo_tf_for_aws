#!/usr/bin/env bash
# Tests scripts/platform.sh (the bootstrapper of an environment repository) together with the
# environment repository mode of scripts/tf.sh and scripts/prepare-platform.sh, in throwaway git
# repositories with a fake `terraform`. No AWS, no network, no real Terraform code.
#
# Usage: scripts/test-external-envs.sh

set -uo pipefail
src="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
plat="$tmp/platform"
envrepo="$tmp/env-repo"
mkdir -p "$tmp/bin" "$plat/scripts" "$plat/layers/network" "$plat/modules/m" "$plat/templates" "$plat/envs/demo" "$envrepo/envs/demo/apps"

cat >"$tmp/bin/terraform" <<'FAKE'
#!/usr/bin/env bash
echo "terraform $*"
FAKE
chmod +x "$tmp/bin/terraform"
export PATH="$tmp/bin:$PATH"

# ---- the platform repository: two releases and a decoy environment of its own ----
cp "$src/scripts/tf.sh" "$src/scripts/common-value.sh" "$src/scripts/prepare-platform.sh" "$plat/scripts/"
cat >"$plat/scripts/validate-values.py" <<'FAKE'
#!/usr/bin/env python3
import os, sys
print("validate-values", " ".join(sys.argv[1:]), "ENVS=" + os.environ.get("PLATFORM_ENVS_DIR", ""))
FAKE
printf 'common:\n  state_bucket: decoy-bucket\n  region: eu-west-1\n' >"$plat/envs/demo/values.yaml"
echo one >"$plat/layers/network/marker.txt"
echo one >"$plat/modules/m/marker.txt"
git -C "$plat" init -q
git -C "$plat" config user.email test@example.com
git -C "$plat" config user.name test
git -C "$plat" add -A && git -C "$plat" commit -q -m one && git -C "$plat" tag v1.0.0
v100="$(git -C "$plat" rev-parse HEAD)"
echo two >"$plat/layers/network/marker.txt"
git -C "$plat" add -A && git -C "$plat" commit -q -m two && git -C "$plat" tag -a v1.1.0 -m "release 1.1.0"
v110="$(git -C "$plat" rev-parse HEAD)"

# ---- the environment repository: only envs/ and the bootstrapper ----
cp "$src/scripts/platform.sh" "$envrepo/platform"
write_values() { # <version line> [<source line>]
  cat >"$envrepo/envs/demo/values.yaml" <<YAML
common:
  name: demo
  region: ap-northeast-1
  state_bucket: env-bucket
${2-  platform_source: file://$plat}
$1
YAML
}
write_values "  platform_version: v1.0.0"
echo "workloads: {web: {}}" >"$envrepo/envs/demo/apps/a.yaml"

failed=0
count=0
ok() { count=$((count + 1)); echo "pass  $1"; }
bad() { count=$((count + 1)); failed=$((failed + 1)); echo "FAIL  $1"; shift; printf '        %s\n' "$@"; }
check() { local label="$1" status="$2"; shift 2; if [ "$status" -eq 0 ]; then ok "$label"; else bad "$label" "$@"; fi; }

run() { (cd "$envrepo" && ./platform demo "$@" 2>"$tmp/stderr"); }
chdir_of() { sed -n 's/^terraform -chdir=\([^ ]*\) .*/\1/p' <<<"$1"; }

# 1. A release runs, with the environment of this repository
out="$(run network init)"
dir="$(chdir_of "$out")"
check "runs the layer of the release in a folder of this repository" "$([ "$dir" = "$envrepo/.terraform-data/demo/external/$v100/layers/network" ]; echo $?)" "got: $dir"
check "the code is the one of v1.0.0 (one)" "$([ "$(cat "$dir/marker.txt")" = one ]; echo $?)"
check "backend: the bucket of the environment repository, not the decoy of the platform" "$(grep -q -- "-backend-config=bucket=env-bucket" <<<"$out"; echo $?)" "$out"
check "the environment folder is the one of this repository" "$(cmp -s "$envrepo/envs/demo/values.yaml" "$dir/../../envs/demo/values.yaml" && ! grep -q decoy "$dir/../../envs/demo/values.yaml"; echo $?)"
check "says which platform and commit it runs" "$(grep -q "platform: file://$plat v1.0.0 (${v100:0:10})" "$tmp/stderr"; echo $?)" "stderr: $(cat "$tmp/stderr")"
check "the release is cached under .platform/ in this repository" "$([ -f "$envrepo/.platform/v1.0.0-${v100:0:10}/.complete" ]; echo $?)"
check "no data directory inside the cached platform" "$([ ! -e "$envrepo/.platform/v1.0.0-${v100:0:10}/.terraform-data" ]; echo $?)"

# 2. The environment is refreshed on every call
echo "workloads: {api: {}}" >"$envrepo/envs/demo/apps/b.yaml"
rm -f "$envrepo/envs/demo/apps/a.yaml"
run network validate >/dev/null
check "a new app file appears and a removed one disappears" "$([ -f "$dir/../../envs/demo/apps/b.yaml" ] && [ ! -e "$dir/../../envs/demo/apps/a.yaml" ]; echo $?)"

# 3. The release is fetched once, and what Terraform leaves in the folder stays
echo keep >"$envrepo/.platform/v1.0.0-${v100:0:10}/cache-marker"
echo plan >"$dir/tfplan"
run network apply tfplan >/dev/null
check "a second call does not fetch again" "$([ -f "$envrepo/.platform/v1.0.0-${v100:0:10}/cache-marker" ]; echo $?)"
check "a saved plan stays between plan and apply" "$([ -f "$dir/tfplan" ]; echo $?)"

# 4. Another version = another folder and its code (an annotated tag)
write_values "  platform_version: v1.1.0"
out="$(run network init)"
dir2="$(chdir_of "$out")"
check "v1.1.0 (annotated tag) runs its own code (two) in its own folder" "$([ "$dir2" = "$envrepo/.terraform-data/demo/external/$v110/layers/network" ] && [ "$(cat "$dir2/marker.txt")" = two ]; echo $?)" "got: $dir2"
check "v1.1.0 is cached under the commit, not the tag object" "$([ -f "$envrepo/.platform/v1.1.0-${v110:0:10}/.complete" ]; echo $?)"

# 5. A tag that moves is another folder
write_values "  platform_version: v1.0.0"
git -C "$plat" tag -f v1.0.0 "$v110" >/dev/null 2>&1
out="$(run network init)"
dir3="$(chdir_of "$out")"
check "a tag that moved is fetched again as another folder" "$([ "$dir3" = "$envrepo/.terraform-data/demo/external/$v110/layers/network" ] && [ -d "$envrepo/.platform/v1.0.0-${v110:0:10}" ]; echo $?)" "got: $dir3"
git -C "$plat" tag -f v1.0.0 "$v100" >/dev/null 2>&1

# 6. validate and --show
write_values "  platform_version: v1.1.0"
out="$(run validate)"
check "validate runs the validator of that version on this environment" "$(grep -q "validate-values $envrepo/envs/demo ENVS=$envrepo/envs" <<<"$out"; echo $?)" "$out"
shown="$(run --show)"
check "--show prints the source and the version" "$([ "$shown" = "file://$plat v1.1.0" ]; echo $?)" "got: $shown"
check "the bootstrapper reads the values like scripts/common-value.sh" "$([ "$(bash "$src/scripts/common-value.sh" "$envrepo/envs/demo/values.yaml" platform_source)" = "file://$plat" ] && [ "$(bash "$src/scripts/common-value.sh" "$envrepo/envs/demo/values.yaml" platform_version)" = v1.1.0 ]; echo $?)"

# 7. Errors
write_values "  platform_version: v9.9.9"
run network init >/dev/null 2>&1; code=$?
check "unknown tag: fails and names it" "$([ "$code" -ne 0 ] && grep -q "v9.9.9 does not exist" "$tmp/stderr"; echo $?)" "$(cat "$tmp/stderr")"

write_values "" "  platform_source: file://$plat"
run network init >/dev/null 2>&1; code=$?
check "source without a version: fails and says what to set" "$([ "$code" -ne 0 ] && grep -q "Set common.platform_source" "$tmp/stderr"; echo $?)" "$(cat "$tmp/stderr")"

write_values "  platform_version: main"
run network init >/dev/null 2>&1; code=$?
check "main with a source: fails (a remote platform must be pinned)" "$([ "$code" -ne 0 ] && grep -q "must be a version tag" "$tmp/stderr"; echo $?)" "$(cat "$tmp/stderr")"

write_values "  platform_version: v1.0.0" ""
run network init >/dev/null 2>&1; code=$?
check "no source: fails and says what to set" "$([ "$code" -ne 0 ] && grep -q "Set common.platform_source" "$tmp/stderr"; echo $?)" "$(cat "$tmp/stderr")"

run unknownlayer >/dev/null 2>&1
(cd "$envrepo" && ./platform nope network init >/dev/null 2>"$tmp/stderr"); code=$?
check "unknown environment: fails" "$([ "$code" -ne 0 ] && grep -q "Unknown environment 'nope'" "$tmp/stderr"; echo $?)" "$(cat "$tmp/stderr")"

# 8. github.com/owner/repo is a shorthand for the https URL
real_git="$(command -v git)"
cat >"$tmp/bin/git" <<FAKE
#!/usr/bin/env bash
if [[ "\$*" == *example-org* ]]; then echo "git: \$*" >>"$tmp/git-calls"; exit 128; fi
exec "$real_git" "\$@"
FAKE
chmod +x "$tmp/bin/git"
write_values "  platform_version: v1.0.0" "  platform_source: github.com/example-org/platform"
run network init >/dev/null 2>&1; code=$?
check "github.com/owner/repo is fetched from https://github.com/owner/repo.git" "$([ "$code" -ne 0 ] && grep -q "ls-remote https://github.com/example-org/platform.git" "$tmp/git-calls"; echo $?)" "$(cat "$tmp/git-calls" 2>/dev/null)"
rm -f "$tmp/bin/git"

# 9. tf.sh of another version than the environment asks for refuses to run
write_values "  platform_version: v1.1.0"
run network init >/dev/null 2>&1
(cd "$plat" && git checkout -q v1.0.0 2>/dev/null && PLATFORM_ENVS_DIR="$envrepo/envs" PLATFORM_DATA_DIR="$envrepo/.terraform-data" bash scripts/tf.sh demo network init >/dev/null 2>"$tmp/stderr"); code=$?
check "tf.sh of v1.0.0 refuses an environment that asks for v1.1.0" "$([ "$code" -ne 0 ] && grep -q "is not v1.1.0" "$tmp/stderr"; echo $?)" "exit $code: $(cat "$tmp/stderr")"

echo
if [ "$failed" -eq 0 ]; then
  echo "All $count environment repository tests passed."
else
  echo "$failed of $count environment repository tests failed."
  exit 1
fi
