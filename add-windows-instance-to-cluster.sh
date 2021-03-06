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

SGID=$(jq -r .sgID <"./clusters/$CLUSTERNAME.json")
SUBNETID=$(jq -r .subnet1ID <"./clusters/$CLUSTERNAME.json")
CLUSTERNAME=$(jq -r .clusterName <"./clusters/$CLUSTERNAME.json")
REGION=$(jq -r .region <"./clusters/$CLUSTERNAME.json")

# Windows AMI and userdata
AMIID=$(aws ssm get-parameters --names /aws/service/ami-windows-latest/Windows_Server-2019-English-Full-ECS_Optimized/image_id | jq -r ".Parameters[0].Value")

cat << EOF > /tmp/userdata
<powershell>
[Environment]::SetEnvironmentVariable("ECS_ENABLE_SPOT_INSTANCE_DRAINING", "true", "Machine")
Import-Module ECSTools
Initialize-ECSAgent -Cluster '$CLUSTERNAME' -EnableTaskIAMRole
</powershell>
EOF

# get spot price
price=$(aws ec2 describe-spot-price-history --instance-type "$INSTANCE_TYPE" --region "$REGION" --product-description "Windows" --availability-zone "${REGION}a" | jq -r ".SpotPriceHistory[0].SpotPrice")
bid=$(echo "$price * 2" | bc -l)
echo "Spot price of instance $INSTANCE_TYPE is approximately \$$price/hour, bidding \$$bid/hour"

ID=$(python -c "import string; import random; print(''.join(random.choice(string.ascii_lowercase) for i in range(4)))")
printf "Launching instance. name=$CLUSTERNAME-$ID amiID=$AMIID type=$INSTANCE_TYPE"
INSTANCE_ID=$(aws ec2 run-instances \
    --instance-market-options "MarketType=spot,SpotOptions={MaxPrice=$bid,SpotInstanceType=one-time}" \
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
