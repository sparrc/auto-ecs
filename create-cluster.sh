#!/bin/bash
set -eou pipefail

REGION="${1:-}"
if [ -z "$REGION" ]; then
    echo "you must specify a region to create the cluster"
    echo "Usage:"
    echo "  ./create-cluster.sh REGION CLUSTERNAME [basic|awsvpc]"
    exit 1
fi

CLUSTERNAME="${2:-}"
if [ -z "$CLUSTERNAME" ]; then
    echo "you must specify a cluster name"
    echo "Usage:"
    echo "  ./create-cluster.sh REGION CLUSTERNAME [basic|awsvpc]"
    exit 1
fi

STACKTYPE="${3:-}"
if [ -z "$STACKTYPE" ]; then
    STACKTYPE="basic"
fi

aws cloudformation create-stack --stack-name ${CLUSTERNAME} --region ${REGION} --template-body "file://cfn/ecs-${STACKTYPE}-stack.yaml" --capabilities CAPABILITY_NAMED_IAM

echo "Waiting for stack creation to complete"
aws cloudformation wait stack-create-complete --region ${REGION} --stack-name ${CLUSTERNAME}
aws cloudformation describe-stacks --region ${REGION} --stack-name ${CLUSTERNAME} | jq .
