#!/bin/bash
set -eou pipefail

CLUSTERNAME="${1:-}"
if [ -z "$CLUSTERNAME" ]; then
    echo "You must specify a cluster to stop all tasks on"
    exit 1
fi

CLUSTERNAME=$(jq -r .clusterName <"./clusters/$CLUSTERNAME.json")
REGION=$(jq -r .region <"./clusters/$CLUSTERNAME.json")

for task in $(aws ecs list-tasks --region "$REGION" --cluster "$CLUSTERNAME" | jq -r ".taskArns[]"); do
    aws ecs stop-task --region "$REGION" --task "$task" --cluster "$CLUSTERNAME" &
    sleep 0.25
done

wait
