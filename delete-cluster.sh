#!/bin/bash
set -ex

CLUSTERNAME="${1:-}"
if [ -z "$CLUSTERNAME" ]; then
    echo "You must specify a cluster to take down"
    exit 1
fi

if [ -z "$REGION" ]; then
    REGION="us-west-2"
fi

# find all instances that are part of the cluster:
for instanceID in $(aws ec2 describe-instances --region "$REGION" --filters "Name=tag:Cluster,Values=$CLUSTERNAME" | jq -r ".Reservations[].Instances[].InstanceId"); do
    echo "Terminating $instanceID"
    aws ec2 terminate-instances --region "$REGION" --instance-ids $instanceID | jq .
done

aws cloudformation delete-stack --region "$REGION" --stack-name ${CLUSTERNAME}
echo "Waiting for stack deletion to complete"
aws cloudformation wait stack-delete-complete --region "$REGION" --stack-name ${CLUSTERNAME}
