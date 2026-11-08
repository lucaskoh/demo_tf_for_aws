#!/usr/bin/env bash
# Plans every layer of one environment, in apply order.
#
# Usage: plan-layers.sh <environment>   (a folder under envs/)
#
# Layers read each other's state (terraform_remote_state), so a layer can only
# be planned once the layers it depends on have been applied. When an upstream
# layer has no outputs yet, the layer is reported as "skipped" instead of
# failing with a confusing remote-state error.
#
# Output (in $OUT_DIR, default plan-output/<environment>):
#   <layer>.txt    log of init + plan for that layer
#   summary.tsv    one "<layer><TAB><status>" line per layer
#                  status is one of: success, skipped, failed
# Exit code is 1 when at least one layer failed (skipped is not a failure).

set -uo pipefail

ENV_NAME="${1:?usage: plan-layers.sh <environment>}"
OUT_DIR="${OUT_DIR:-plan-output/$ENV_NAME}"
TF="scripts/tf.sh $ENV_NAME"

LAYERS=(network compute workloads edge)
declare -A UPSTREAM=(
  [network]=""
  [compute]="network"
  [workloads]="network compute"
  [edge]="network compute"
)

mkdir -p "$OUT_DIR"
: >"$OUT_DIR/summary.tsv"

failed=0

for layer in "${LAYERS[@]}"; do
  log="$OUT_DIR/$layer.txt"
  status="success"

  if ! $TF "$layer" init -input=false -no-color >"$log" 2>&1; then
    status="failed"
  else
    # An upstream layer without outputs has not been applied (or was destroyed)
    missing=""
    for up in ${UPSTREAM[$layer]}; do
      outputs="$($TF "$up" output -json 2>/dev/null | tr -d '[:space:]')"
      if [ "$outputs" = "{}" ]; then
        missing="$missing $up"
      fi
    done

    if [ -n "$missing" ]; then
      status="skipped"
      echo "Skipped: upstream layer(s) not deployed yet:$missing" >>"$log"
    elif ! $TF "$layer" plan -no-color -input=false -out=tfplan >>"$log" 2>&1; then
      status="failed"
    fi
  fi

  [ "$status" = "failed" ] && failed=1
  printf '%s\t%s\n' "$layer" "$status" >>"$OUT_DIR/summary.tsv"
  echo "==> $layer: $status"
done

exit "$failed"
