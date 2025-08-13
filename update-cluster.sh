#!/bin/bash
set -eou pipefail

REGION="${1:-}"
if [ -z "$REGION" ]; then
    echo "you must specify a region to update the cluster"
    echo "Usage:"
    echo "  ./update-cluster.sh REGION CLUSTERNAME [basic|awsvpc]"
    exit 1
fi

CLUSTERNAME="${2:-}"
if [ -z "$CLUSTERNAME" ]; then
    echo "you must specify a cluster name"
    echo "Usage:"
    echo "  ./update-cluster.sh REGION CLUSTERNAME [basic|awsvpc]"
    exit 1
fi

STACKTYPE="${3:-}"
if [ -z "$STACKTYPE" ]; then
    STACKTYPE="basic"
fi

aws cloudformation update-stack --stack-name ${CLUSTERNAME} --region ${REGION} --template-body "file://cfn/ecs-${STACKTYPE}-stack.yaml" --parameters ParameterKey=EcsClusterName,ParameterValue=${CLUSTERNAME} --capabilities CAPABILITY_NAMED_IAM

echo "Waiting for stack update to complete"
aws cloudformation wait stack-update-complete --region ${REGION} --stack-name ${CLUSTERNAME}
aws cloudformation describe-stacks --region ${REGION} --stack-name ${CLUSTERNAME} | jq .
