#!/usr/bin/env bash
# Checks the schemas against the fixtures in schemas/tests:
#   valid/*.yaml    must pass
#   invalid/*.yaml  must fail, and the output must contain the text of the first line
#                   "# expect: <text>". Files called templates-*.yaml use the EC2 template schema.
#
# Usage: scripts/test-schemas.sh        (PYTHON=... to choose the interpreter)

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

PY="${PYTHON:-python3}"
# Plain output: expected failures must not become annotations on a pull request
validate() { env -u GITHUB_ACTIONS "$PY" scripts/validate-values.py "$@" 2>&1; }

failed=0

for f in schemas/tests/valid/*.yaml; do
  if out="$(validate "$f")"; then
    echo "pass  $f"
  else
    echo "FAIL  $f (should be valid)"
    sed 's/^/        /' <<<"$out"
    failed=1
  fi
done

for f in schemas/tests/invalid/*.yaml; do
  expect="$(sed -n '1s/^# expect: //p' "$f")"
  if [ -z "$expect" ]; then
    echo "FAIL  $f (the first line must be '# expect: <text>')"
    failed=1
    continue
  fi

  kind=values
  case "$(basename "$f")" in templates-*) kind=templates ;; esac

  if out="$(validate --kind "$kind" "$f")"; then
    echo "FAIL  $f (should be invalid)"
    failed=1
  elif grep -qF -- "$expect" <<<"$out"; then
    echo "pass  $f"
  else
    echo "FAIL  $f (expected the text: $expect)"
    sed 's/^/        /' <<<"$out"
    failed=1
  fi
done

if [ "$failed" -ne 0 ]; then
  echo "Some schema tests failed." >&2
  exit 1
fi
echo "All schema tests passed."
