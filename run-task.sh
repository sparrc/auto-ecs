#!/bin/bash
set -ex

CLUSTERNAME="${1:-}"
if [ -z "$CLUSTERNAME" ]; then
    echo "you must specify a cluster name"
    echo "Usage:"
    echo "  ./run-task.sh CLUSTERNAME TASKDEF"
    exit 1
fi

TASKDEFINITION="${2:-}"
if [[ "$TASKDEFINITION" == "" ]]; then
    echo "You must specify a task definition to run"
    echo "Usage:"
    echo "  ./run-task.sh CLUSTERNAME TASKDEF"
    exit 1
fi

if [ -z "$REGION" ]; then
    REGION="us-west-2"
fi

#echo --network-configuration "awsvpcConfiguration={subnets=[$SUBNETID_2,$SUBNETID_1],securityGroups=[$SGID],assignPublicIp=DISABLED}"

aws ecs run-task --region "$REGION" --cluster "$CLUSTERNAME" \
   --task-definition "$TASKDEFINITION" \
   --started-by "$(whoami)-auto-ecs"
#--overrides '{"containerOverrides":[{"name":"dd","cpu":100}]}'
#--network-configuration "awsvpcConfiguration={subnets=[$SUBNETID_2,$SUBNETID_1],securityGroups=[$SGID],assignPublicIp=DISABLED}" \
