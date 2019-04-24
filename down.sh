#!/bin/bash
set -eou pipefail

NAME="${1:-}"
if [[ "$NAME" == "" ]]; then
    NAME=$(cat cluster.json | jq -r .clusterName)
    echo "Take down cluster $NAME? (y/n)"
    read yn
    if [[ "$yn" != "y" ]]; then
        exit 0
    fi
fi

ecs-cli compose --project-name "$NAME" service down --cluster-config "$NAME"
ecs-cli down --force --cluster-config "$NAME"

