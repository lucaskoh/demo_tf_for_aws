#!/usr/bin/env bash
# Destroys one layer, retrying a few times.
#
# Some deletions fail once because AWS finishes an earlier deletion
# asynchronously. For example, deleting the ALB listener right after the NLB
# deregistered the ALB fails with "ResourceInUse: Listener port '80' is in use
# by registered target". A retry a little later succeeds.
#
# Every attempt plans again, because a saved plan is stale once part of the
# layer has been destroyed.
#
# Usage: destroy-layer.sh <environment> <layer>
# Environment: ATTEMPTS (default 3), RETRY_WAIT seconds (default 30)

set -uo pipefail

env_name="${1:?usage: destroy-layer.sh <environment> <layer>}"
layer="${2:?usage: destroy-layer.sh <environment> <layer>}"
TF="scripts/tf.sh $env_name"
attempts="${ATTEMPTS:-3}"
wait_seconds="${RETRY_WAIT:-30}"

$TF "$layer" init -input=false || exit 1

for attempt in $(seq 1 "$attempts"); do
  echo "==> destroy $env_name/$layer (attempt $attempt/$attempts)"

  if $TF "$layer" plan -destroy -no-color -input=false -out=tfplan-destroy &&
    $TF "$layer" apply -no-color -input=false tfplan-destroy; then
    exit 0
  fi

  if [ "$attempt" -lt "$attempts" ]; then
    echo "Attempt $attempt failed; retrying in ${wait_seconds}s ..."
    sleep "$wait_seconds"
  fi
done

echo "Destroy of $env_name/$layer failed after $attempts attempts" >&2
exit 1
