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

OS="${3:-al2}"

SGID=$(jq -r .sgID <"./clusters/$CLUSTERNAME.json")
SUBNETID=$(jq -r .subnet1ID <"./clusters/$CLUSTERNAME.json")
CLUSTERNAME=$(jq -r .clusterName <"./clusters/$CLUSTERNAME.json")
REGION=$(jq -r .region <"./clusters/$CLUSTERNAME.json")

AMIID=""
TYPE_PREFIX="${INSTANCE_TYPE:0:3}"
case $TYPE_PREFIX in
a1. | m6g | c6g | r6g | t4g)
    echo "ARM instance type detected"
    AMIID=$(aws ssm get-parameters --region "$REGION" --names /aws/service/ecs/optimized-ami/amazon-linux-2/arm64/recommended/image_id --query "Parameters[0].Value" --output text)
    ;;
p2. | p3. | p4d | g4d | g3s | g3.)
    echo "GPU instance type detected"
    AMIID=$(aws ssm get-parameters --region "$REGION" --names /aws/service/ecs/optimized-ami/amazon-linux-2/gpu/recommended/image_id --query "Parameters[0].Value" --output text)
    ;;
inf)
    echo "INF instance type detected"
    AMIID=$(aws ssm get-parameters --region "$REGION" --names /aws/service/ecs/optimized-ami/amazon-linux-2/inf/recommended/image_id --query "Parameters[0].Value" --output text)
    ;;
*)
    case $OS in
    bottlerocket)
        AMIID=$(aws ssm get-parameter --region "$REGION" --name "/aws/service/bottlerocket/aws-ecs-1/x86_64/latest/image_id" --query "Parameter.Value" --output text)
        ;;
    al2)
        AMIID=$(aws ssm get-parameters --region "$REGION" --names /aws/service/ecs/optimized-ami/amazon-linux-2/recommended/image_id --query "Parameters[0].Value" --output text)
        ;;
    al1)
        AMIID=$(aws ssm get-parameters --region "$REGION" --names /aws/service/ecs/optimized-ami/amazon-linux/recommended/image_id | jq -r ".Parameters[0].Value")
        ;;
    *)
        AMIID="$OS"
        ;;
    esac
    ;;
esac

# setup userdata
if [[ "$OS" == "bottlerocket" ]]; then
    cat <<EOF > /tmp/userdata
[settings.ecs]
cluster = "$CLUSTERNAME"
EOF
else
    cat ./userdata >/tmp/userdata
    cat <<EOF >>/tmp/userdata
echo ECS_CLUSTER=$CLUSTERNAME >> /etc/ecs/ecs.config
EOF
fi

# get root device name
ROOT_DEVICE_NAME=$(aws ec2 describe-images --image-ids "$AMIID" --query "Images[0].RootDeviceName" --output text)

# get spot price
price=$(aws ec2 describe-spot-price-history --instance-type "$INSTANCE_TYPE" --region "$REGION" --product-description "Linux/UNIX" --availability-zone "${REGION}a" --query "SpotPriceHistory[0].SpotPrice" --output text)
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
    --block-device-mapping "[{\"DeviceName\":\"${ROOT_DEVICE_NAME}\",\"Ebs\":{\"VolumeSize\":100}}]" \
    --associate-public-ip-address \
    --query "Instances[0].InstanceId" --output text)

printf " instanceID=$INSTANCE_ID"
sleep 2
PUBLIC_IP_ADDR=$(aws ec2 describe-instances --region "$REGION" --instance-ids "$INSTANCE_ID" --query "Reservations[0].Instances[0].PublicIpAddress" --output text)
echo " publicIPAddress=$PUBLIC_IP_ADDR"
