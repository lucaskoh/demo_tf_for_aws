#!/usr/bin/env bash
# Tests scripts/tf.sh and scripts/prepare-platform.sh (common.platform_version) in a throwaway git
# repository with a fake `terraform` that only prints the folder it was asked to run in. No AWS, no
# network, no real Terraform code.
#
# Usage: scripts/test-platform-pin.sh

set -uo pipefail
src="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
repo="$tmp/repo"
mkdir -p "$repo/scripts" "$repo/layers/network" "$repo/modules/m" "$repo/templates" "$repo/assets" "$repo/envs/demo/apps" "$tmp/bin"
cp "$src/scripts/tf.sh" "$src/scripts/common-value.sh" "$src/scripts/prepare-platform.sh" "$repo/scripts/"

# A fake terraform: prints the arguments (the layer folder is in -chdir=...)
cat >"$tmp/bin/terraform" <<'FAKE'
#!/usr/bin/env bash
echo "terraform $*"
FAKE
chmod +x "$tmp/bin/terraform"
export PATH="$tmp/bin:$PATH"

write_values() { # <platform_version line or empty>
  cat >"$repo/envs/demo/values.yaml" <<YAML
common:
  name: demo
  region: ap-northeast-1
  state_bucket: example-bucket
$1
YAML
}

git -C "$repo" init -q
git -C "$repo" config user.email test@example.com
git -C "$repo" config user.name test

# Release 1: the code says "one"
echo one >"$repo/layers/network/marker.txt"
echo one >"$repo/modules/m/marker.txt"
echo one >"$repo/templates/marker.txt"
write_values ""
echo "workloads: {old: true}" >"$repo/envs/demo/apps/a.yaml"
git -C "$repo" add -A && git -C "$repo" commit -q -m one && git -C "$repo" tag v1.0.0
v1_commit="$(git -C "$repo" rev-parse HEAD)"

# Later work on the working tree: the code says "two" (committed), a new layer appears
echo two >"$repo/layers/network/marker.txt"
echo two >"$repo/modules/m/marker.txt"
mkdir -p "$repo/layers/extra" && echo two >"$repo/layers/extra/marker.txt"
git -C "$repo" add -A && git -C "$repo" commit -q -m two && git -C "$repo" tag v2.0.0

failed=0
count=0
ok() { count=$((count + 1)); echo "pass  $1"; }
bad() { count=$((count + 1)); failed=$((failed + 1)); echo "FAIL  $1"; shift; printf '        %s\n' "$@"; }
check() { # <label> <condition: 0 = ok> <details...>
  local label="$1" status="$2"
  shift 2
  if [ "$status" -eq 0 ]; then ok "$label"; else bad "$label" "$@"; fi
}

tf() { (cd "$repo" && bash scripts/tf.sh demo "$@" 2>"$tmp/stderr"); }
chdir_of() { sed -n 's/^terraform -chdir=\([^ ]*\) .*/\1/p' <<<"$1"; }

# 1. No platform_version: the working tree
write_values ""
out="$(tf network validate)"
dir="$(chdir_of "$out")"
check "no platform_version: runs the layer of the working tree" "$([ "$dir" = "$repo/layers/network" ]; echo $?)" "got: $dir"

# 2. platform_version: main (also with a comment): the working tree
write_values "  platform_version: main   # follows the code of this commit"
out="$(tf network validate)"
dir="$(chdir_of "$out")"
check "platform_version main: runs the layer of the working tree" "$([ "$dir" = "$repo/layers/network" ]; echo $?)" "got: $dir"

# 3. Pinned: the code of the tag, not the working tree
write_values "  platform_version: v1.0.0"
out="$(tf network validate)"
dir="$(chdir_of "$out")"
check "pinned: runs the layer of the tag" "$([ "$dir" = "$repo/.terraform-data/demo/platform/$v1_commit/layers/network" ]; echo $?)" "got: $dir"
check "pinned: the layer has the code of the tag (one), the working tree has two" "$([ "$(cat "$dir/marker.txt")" = one ] && [ "$(cat "$repo/layers/network/marker.txt")" = two ]; echo $?)"
check "pinned: modules and templates come from the tag too" "$([ "$(cat "$dir/../../modules/m/marker.txt")" = one ] && [ "$(cat "$dir/../../templates/marker.txt")" = one ]; echo $?)"
check "pinned: the tooling is not copied" "$([ ! -e "$dir/../../scripts" ]; echo $?)"
check "pinned: says which version it uses" "$(grep -q "platform code: v1.0.0" "$tmp/stderr"; echo $?)" "stderr: $(cat "$tmp/stderr")"

# 4. The environment comes from the working tree, every time
check "pinned: envs/<env>/values.yaml is the working tree's" "$(cmp -s "$repo/envs/demo/values.yaml" "$dir/../../envs/demo/values.yaml"; echo $?)"
echo "workloads: {new: true}" >"$repo/envs/demo/apps/b.yaml"
rm -f "$repo/envs/demo/apps/a.yaml"
tf network validate >/dev/null
check "pinned: a new app file appears and a removed one disappears" "$([ -f "$dir/../../envs/demo/apps/b.yaml" ] && [ ! -e "$dir/../../envs/demo/apps/a.yaml" ]; echo $?)"

# 5. The folder is reused, and what Terraform leaves in it stays (a saved plan)
echo plan >"$dir/tfplan"
tf network apply tfplan >/dev/null
check "pinned: a second call keeps files that Terraform left (tfplan)" "$([ -f "$dir/tfplan" ]; echo $?)"

# 6. A local terraform.tfvars is copied
echo 'x = 1' >"$repo/layers/network/terraform.tfvars"
tf network validate >/dev/null
check "pinned: a local terraform.tfvars is copied" "$([ -f "$dir/terraform.tfvars" ]; echo $?)"

# 7. Another version is another folder
write_values "  platform_version: v2.0.0"
out="$(tf network validate)"
dir2="$(chdir_of "$out")"
check "another version uses another folder with its code (two)" "$([ "$dir2" != "$dir" ] && [ "$(cat "$dir2/marker.txt")" = two ]; echo $?)" "got: $dir2"

# 8. A layer that the pinned version does not have
write_values "  platform_version: v1.0.0"
tf extra validate >/dev/null 2>&1
check "pinned: a layer that does not exist in that version is rejected" "$([ $? -ne 0 ]; echo $?)"
# (the layer exists in the working tree, so tf.sh gets past its first check)

# 9. Errors
write_values "  platform_version: v9.9.9"
tf network validate >/dev/null 2>&1; code=$?
check "unknown tag: fails and tells how to fetch tags" "$([ "$code" -ne 0 ] && grep -q "git fetch --tags" "$tmp/stderr"; echo $?)" "exit $code, stderr: $(cat "$tmp/stderr")"

write_values "  platform_version: 1.0"
tf network validate >/dev/null 2>&1; code=$?
check "bad format: fails and names the format" "$([ "$code" -ne 0 ] && grep -q "must be 'main' or a version tag" "$tmp/stderr"; echo $?)" "exit $code, stderr: $(cat "$tmp/stderr")"

# 10. A tag that is not a platform release
git -C "$repo" checkout -q --orphan other && git -C "$repo" rm -rfq . >/dev/null 2>&1
echo x >"$repo/readme.txt" && git -C "$repo" add readme.txt && git -C "$repo" commit -q -m other && git -C "$repo" tag v3.0.0
git -C "$repo" checkout -q -f v2.0.0 2>/dev/null
write_values "  platform_version: v3.0.0"
tf network validate >/dev/null 2>&1; code=$?
check "a tag without layers/ and modules/ is rejected" "$([ "$code" -ne 0 ] && grep -q "not a platform release" "$tmp/stderr"; echo $?)" "exit $code, stderr: $(cat "$tmp/stderr")"

echo
if [ "$failed" -eq 0 ]; then
  echo "All $count platform pin tests passed."
else
  echo "$failed of $count platform pin tests failed."
  exit 1
fi
