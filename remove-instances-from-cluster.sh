#!/bin/bash
set -e

CLUSTERNAME="${1:-}"
if [ -z "$CLUSTERNAME" ]; then
    echo "You must specify a cluster to take down"
    exit 1
fi

if [ -z "$REGION" ]; then
    REGION="us-west-2"
fi

# find all instances that are part of the cluster:
for instanceID in $(aws ec2 describe-instances --region "$REGION" --filters "Name=tag:Cluster,Values=$CLUSTERNAME" "Name=instance-state-name,Values=running" --query "Reservations[].Instances[].InstanceId" --output text); do
    echo "Terminating $instanceID"
    aws ec2 terminate-instances --region "$REGION" --instance-ids $instanceID | jq .
done
