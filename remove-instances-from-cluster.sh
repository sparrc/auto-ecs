#!/bin/bash
set -eou pipefail

CLUSTERNAME="${1:-}"
if [[ "$CLUSTERNAME" == "" ]]; then
    echo "You must specify a cluster to remove instances from"
    exit 1
fi

# find all instances that are part of the cluster:
for instanceID in $(aws ec2 describe-instances --filters "Name=tag:Cluster,Values=$CLUSTERNAME" | jq -r ".Reservations[].Instances[].InstanceId"); do
    echo "Terminating $instanceID"
    aws ec2 terminate-instances --instance-ids $instanceID | jq .
done

