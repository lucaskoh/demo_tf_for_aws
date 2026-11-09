#!/usr/bin/env bash
# Prints the value of a key under "common:" of a values.yaml file (quotes and a trailing
# comment removed). Usage: scripts/common-value.sh <values.yaml> <key>
#
# It uses awk, not a YAML parser, so that scripts/tf.sh needs no extra tool. That works as long
# as the key is written as "key: value" on one line directly under "common:". Anything else
# (a flow mapping, a value on the next line, a nested key of the same name above it) can give
# an empty or a wrong value. scripts/validate-values.py compares this script with a real YAML
# parser for state_bucket and region, so such a file is rejected in CI.

set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <values.yaml> <key>" >&2
  exit 2
fi

awk -v key="$2" '
  /^common:/ { in_common = 1; next }
  /^[^ #]/   { in_common = 0 }
  in_common && $1 == key ":" { print $2; exit }
' "$1" | sed -E 's/^["'\'']//; s/["'\'']$//'
