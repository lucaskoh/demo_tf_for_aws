#!/usr/bin/env bash
# Applies one layer of one environment: init, plan, then apply the saved plan.
#
# Usage: apply-layer.sh <environment> <layer>

set -euo pipefail

env_name="${1:?usage: apply-layer.sh <environment> <layer>}"
layer="${2:?usage: apply-layer.sh <environment> <layer>}"
TF="scripts/tf.sh $env_name"

$TF "$layer" init -input=false
$TF "$layer" plan -no-color -input=false -out=tfplan
$TF "$layer" apply -no-color -input=false tfplan
