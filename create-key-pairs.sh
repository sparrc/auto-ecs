#!/usr/bin/env bash

ID_RSA_FILE="${1:-}"
if [ -z "$ID_RSA_FILE" ]; then
    echo "You must specify a public key file (ie, ~/.ssh/id_rsa.pub)"
    exit 1
fi

REGIONS="us-east-2
us-east-1
us-west-1
us-west-2
ap-south-1
ap-northeast-3
ap-northeast-2
ap-southeast-1
ap-southeast-2
ap-northeast-1
ca-central-1
eu-central-1
eu-west-1
eu-west-2
eu-west-3
eu-north-1"

for region in $(echo $REGIONS); do
    echo "Creating ec2 keypair in $region"
    aws ec2 import-key-pair --region "$region" --key-name "auto-ecs" --public-key-material "fileb://$ID_RSA_FILE"
done
