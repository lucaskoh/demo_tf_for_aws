#!/usr/bin/env bash
# Plans every layer of one environment, in apply order.
#
# Usage: plan-layers.sh <environment>   (a folder under envs/)
#
# Layers read what the layers before them published as SSM parameters
# (/tf-platform/<environment>/<layer>/...), so a layer can only be planned once the
# layers it depends on have been applied. When an upstream layer has published
# nothing yet, the layer is reported as "skipped" instead of failing.
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

# Region of the SSM parameters: set by the AWS credentials step in CI, else from values.yaml
REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-$(scripts/common-value.sh "envs/$ENV_NAME/values.yaml" region)}}"

# Number of parameters that a layer has published (0 = not applied, or destroyed).
# A failure (no permission, no network) is an error, never "0": it must not look like "not deployed".
# --no-paginate: with --max-items the CLI adds an empty last page and length() fails on it.
published_count() {
  aws ssm get-parameters-by-path --region "$REGION" --path "/tf-platform/$ENV_NAME/$1" \
    --no-paginate --max-results 1 --query 'length(Parameters)' --output text
}

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
    # An upstream layer that published nothing has not been applied (or was destroyed)
    missing=""
    for up in ${UPSTREAM[$layer]}; do
      if ! count="$(published_count "$up" 2>>"$log")"; then
        echo "Could not read the SSM parameters of the $up layer (see the error above)." >>"$log"
        status="failed"
        break
      fi
      if [ "$count" = "0" ]; then
        missing="$missing $up"
      fi
    done

    if [ "$status" = "failed" ]; then
      :
    elif [ -n "$missing" ]; then
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
