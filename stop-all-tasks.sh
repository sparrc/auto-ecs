#!/bin/bash
set -ex

CLUSTERNAME="${1:-}"
if [ -z "$CLUSTERNAME" ]; then
    echo "you must specify a cluster name"
    echo "Usage:"
    echo "  ./stop-all-tasks.sh CLUSTERNAME"
    exit 1
fi

if [ -z "$REGION" ]; then
    REGION="us-west-2"
fi

for task in $(aws ecs list-tasks --region "$REGION" --cluster "$CLUSTERNAME" | jq -r ".taskArns[]"); do
    aws ecs stop-task --region "$REGION" --task "$task" --cluster "$CLUSTERNAME" &
    sleep 0.25
done

wait
