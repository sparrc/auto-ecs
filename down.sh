#!/bin/bash
set -eou pipefail

clusterName=$(cat cluster.json | jq -r .clusterName)
echo "Take down cluster $clusterName? (y/n)"
read yn
if [[ "$yn" != "y" ]]; then
    exit 0
fi
serviceName=$(cat cluster.json | jq -r .serviceName)

ecs-cli compose --project-name "$serviceName" service down --cluster-config "$clusterName"
ecs-cli down --force --cluster-config "$clusterName"

