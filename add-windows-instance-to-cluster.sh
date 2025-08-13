#!/bin/bash
set -eou pipefail

CLUSTERNAME="${1:-}"
if [ -z "$CLUSTERNAME" ]; then
    echo "You must specify a cluster to add the instance to"
    exit 1
fi

INSTANCE_TYPE="${2:-}"
if [ -z "$INSTANCE_TYPE" ]; then
    echo "No instance type specified, using m5.large"
    INSTANCE_TYPE="m5.large"
fi

if [ -z "$REGION" ]; then
    REGION="us-west-2"
fi
SUBNETID=$(aws cloudformation describe-stacks --region ${REGION} --stack-name ${CLUSTERNAME} --query "Stacks[0].Outputs[?OutputKey=='EcsPublicSubnetId'].OutputValue" --output text)
SGID=$(aws cloudformation describe-stacks --region ${REGION} --stack-name ${CLUSTERNAME} --query "Stacks[0].Outputs[?OutputKey=='EcsSecurityGroupId'].OutputValue" --output text)

# Windows AMI and userdata
AMIID=$(aws ssm get-parameters --names /aws/service/ami-windows-latest/Windows_Server-2022-English-Full-ECS_Optimized/image_id | jq -r ".Parameters[0].Value")

cat << EOF > /tmp/userdata
<powershell>
[Environment]::SetEnvironmentVariable("ECS_ENABLE_SPOT_INSTANCE_DRAINING", "true", "Machine")
Import-Module ECSTools
Initialize-ECSAgent -Cluster '$CLUSTERNAME' -EnableTaskIAMRole -Version 1.95.0
</powershell>
EOF

# User can specify SPOT=0 if they do not want a spot instance
if [ -z "$SPOT" ]; then
    # default to spot instances if not specified
    SPOT=1
fi
if [ $SPOT -ne 0 ]; then
    # get spot price
    price=$(aws ec2 describe-spot-price-history --instance-type "$INSTANCE_TYPE" --region "$REGION" --product-description "Linux/UNIX" --availability-zone "${REGION}a" --query "SpotPriceHistory[0].SpotPrice" --output text)
    bid=$(echo "$price * 2" | bc -l)
    echo "Spot price of instance $INSTANCE_TYPE is approximately \$$price/hour, bidding \$$bid/hour"
    SPOTARG="--instance-market-options MarketType=spot,SpotOptions={MaxPrice=$bid,SpotInstanceType=one-time}"
else
    SPOTARG=""
fi

ID=$(uuidgen | head -c 4)
printf "Launching instance. name=$CLUSTERNAME-$ID amiID=$AMIID type=$INSTANCE_TYPE"
INSTANCE_ID=$(aws ec2 run-instances $SPOTARG \
    --image-id "$AMIID" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$CLUSTERNAME-$ID},{Key=Cluster,Value=$CLUSTERNAME}]" \
    --iam-instance-profile Name=ecsInstanceRole \
    --count 1 \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "auto-ecs" \
    --user-data file:///tmp/userdata \
    --security-group-ids "$SGID" \
    --subnet-id "$SUBNETID" \
    --region "$REGION" \
    --block-device-mapping "[{\"DeviceName\":\"/dev/xvda\",\"Ebs\":{\"VolumeSize\":100}}]" \
    --associate-public-ip-address | jq -r ".Instances[0].InstanceId")

printf " instanceID=$INSTANCE_ID"
sleep 2
PUBLIC_IP_ADDR=$(aws ec2 describe-instances --region "$REGION" --instance-ids "$INSTANCE_ID" | jq -r ".Reservations[0].Instances[0].PublicIpAddress")
echo " publicIPAddress=$PUBLIC_IP_ADDR"
