#!/usr/bin/env bash
# Checks the schemas and the environment checks of scripts/validate-values.py against the fixtures in
# schemas/tests:
#
#   platform/invalid/*.yaml    single files checked against the platform schema (values.yaml)
#   apps/invalid/*.yaml        single files checked against the apps schema (files under apps/)
#   templates/invalid/*.yaml   single files checked against the EC2 template schema
#     Each must fail, and the output must contain the text of the first line "# expect: <text>".
#
#   envs/valid/<case>/         a whole environment folder (values.yaml and apps/**): must pass
#   envs/invalid/<case>/       a whole environment folder: must fail, and the output must contain the first
#                              line of the file EXPECT in the folder
#
# Usage: scripts/test-schemas.sh        (PYTHON=... to choose the interpreter)

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

PY="${PYTHON:-python3}"
# Plain output: expected failures must not become annotations on a pull request
validate() { env -u GITHUB_ACTIONS "$PY" scripts/validate-values.py "$@" 2>&1; }

failed=0
count=0

must_fail() { # <label> <expected text> <validator args...>
  local label="$1" expect="$2" out
  shift 2
  count=$((count + 1))
  if out="$(validate "$@")"; then
    echo "FAIL  $label (should be invalid)"
    failed=1
  elif [ -z "$expect" ] || grep -qF -- "$expect" <<<"$out"; then
    echo "pass  $label"
  else
    echo "FAIL  $label (expected the text: $expect)"
    sed 's/^/        /' <<<"$out"
    failed=1
  fi
}

for kind in platform apps templates; do
  validator_kind=values
  [ "$kind" = apps ] && validator_kind=apps
  [ "$kind" = templates ] && validator_kind=templates
  for f in schemas/tests/"$kind"/invalid/*.yaml; do
    expect="$(sed -n '1s/^# expect: //p' "$f")"
    if [ -z "$expect" ]; then
      echo "FAIL  $f (the first line must be '# expect: <text>')"
      failed=1
      continue
    fi
    must_fail "$f" "$expect" --kind "$validator_kind" "$f"
  done
done

for d in schemas/tests/envs/valid/*/; do
  count=$((count + 1))
  if out="$(validate "$d")"; then
    echo "pass  $d"
  else
    echo "FAIL  $d (should be valid)"
    sed 's/^/        /' <<<"$out"
    failed=1
  fi
done

for d in schemas/tests/envs/invalid/*/; do
  expect="$(head -n 1 "$d/EXPECT" 2>/dev/null)"
  if [ -z "$expect" ]; then
    echo "FAIL  $d (the folder needs a file EXPECT with the text to look for)"
    failed=1
    continue
  fi
  must_fail "$d" "$expect" "$d"
done

if [ "$failed" -ne 0 ]; then
  echo "Some schema tests failed." >&2
  exit 1
fi
echo "All $count schema tests passed."
