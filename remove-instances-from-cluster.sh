#!/bin/bash
set -eou pipefail

CLUSTERNAME="${1:-}"
if [ -z "$CLUSTERNAME" ]; then
    echo "You must specify a cluster to take down"
    exit 1
fi

if [ ! -f "./clusters/$CLUSTERNAME.json" ]; then
    echo "./clusters/$CLUSTERNAME.json config file not found"
    exit 1
fi

REGION=$(jq -r .region <"./clusters/$CLUSTERNAME.json")

# find all instances that are part of the cluster:
for instanceID in $(aws ec2 describe-instances --region "$REGION" --filters "Name=tag:Cluster,Values=$CLUSTERNAME" | jq -r ".Reservations[].Instances[].InstanceId"); do
    echo "Terminating $instanceID"
    aws ec2 terminate-instances --region "$REGION" --instance-ids $instanceID | jq .
done
