#!/bin/bash
set -e

CLUSTERNAME="${1:-}"
if [ -z "$CLUSTERNAME" ]; then
    echo "You must specify a cluster to list instances from"
    exit 1
fi

if [ -z "$REGION" ]; then
    REGION="us-west-2"
fi

instances=$(aws ec2 describe-instances --region "$REGION" --filters "Name=tag:Cluster,Values=$CLUSTERNAME" "Name=instance-state-name,Values=running")
echo "$instances" | jq .
# find all instances that are part of the cluster:
for instance in $(echo "$instances" | jq -c ".Reservations[].Instances[]"); do
    echo "$instance"
    id=$(echo "$instance" | jq -r .InstanceId)
    imageid=$(echo "$instance" | jq -r .ImageId)
    imagename=$(aws ec2 describe-images --region "$REGION" --image-ids "$imageid" | jq -r '.Images[0].Name')
    instancetype=$(echo "$instance" | jq -r .InstanceType)
    ip=$(echo "$instance" | jq -r .PublicIpAddress)
    lifecycle=$(echo "$instance" | jq -r .InstanceLifecycle)
    printf "$id:\n   imageID=$imageid\n   imageName=$imagename\n   instanceType=$instancetype\n   address=$ip\n   lifecycle=$lifecycle\n\n"
done
