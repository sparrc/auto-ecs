#!/bin/bash
set -eou pipefail

CLUSTERNAME="${1:-}"
if [[ "$CLUSTERNAME" == "" ]]; then
    echo "You must specify a cluster to run the task on"
    exit 1
fi

SGID=$(jq -r .sgID < "./clusters/$CLUSTERNAME.json")
SUBNETID_1=$(jq -r .subnet1ID < "./clusters/$CLUSTERNAME.json")
SUBNETID_2=$(jq -r .subnet2ID < "./clusters/$CLUSTERNAME.json")
CLUSTERNAME=$(jq -r .clusterName < "./clusters/$CLUSTERNAME.json")
REGION=$(jq -r .region < "./clusters/$CLUSTERNAME.json")

aws ecs run-task --region "$REGION" --cluster "$CLUSTERNAME" \
    --task-definition "dd" \
    --started-by "$(whoami)-auto-ecs" \
    --overrides '{"containerOverrides":[{"name":"dd","cpu":5}]}'
    #--network-configuration "awsvpcConfiguration={subnets=[$SUBNETID_2,$SUBNETID_1],securityGroups=[$SGID],assignPublicIp=DISABLED}" \

