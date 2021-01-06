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

# other options:
#   9
DEBIAN_VERSION="${3:-10}"
echo "Using debian version: $DEBIAN_VERSION"

SGID=$(jq -r .sgID <"./clusters/$CLUSTERNAME.json")
SUBNETID=$(jq -r .subnet1ID <"./clusters/$CLUSTERNAME.json")
CLUSTERNAME=$(jq -r .clusterName <"./clusters/$CLUSTERNAME.json")
REGION=$(jq -r .region <"./clusters/$CLUSTERNAME.json")

AMIID=""
ROOT_DEVICE=""
TYPE_PREFIX="${INSTANCE_TYPE:0:3}"
case $TYPE_PREFIX in
a1. | m6g | c6g | r6g | t4g)
    echo "ARM instance type detected"
    if [[ "$DEBIAN_VERSION" == "10" ]]; then
        AMIID=$(aws ec2 describe-images --owners 136693071363 --filters "Name=state,Values=available" "Name=name,Values=debian-10-arm64-*" --query "reverse(sort_by(Images, &CreationDate))[:1].ImageId" --output text)
        ROOT_DEVICE=$(aws ec2 describe-images --owners 136693071363 --filters "Name=state,Values=available" "Name=name,Values=debian-10-arm64-*" --query "reverse(sort_by(Images, &CreationDate))[:1].RootDeviceName" --output text)
    else
        AMIID=$(aws ec2 describe-images --owners 379101102735 --filters "Name=state,Values=available" "Name=name,Values=debian-stretch-hvm-arm64*" --query "reverse(sort_by(Images, &CreationDate))[:1].ImageId" --output text)
        ROOT_DEVICE=$(aws ec2 describe-images --owners 379101102735 --filters "Name=state,Values=available" "Name=name,Values=debian-stretch-hvm-arm64*" --query "reverse(sort_by(Images, &CreationDate))[:1].RootDeviceName" --output text)
    fi
    ;;
p2. | p3. | p4d | g4d | g3s | g3.)
    echo "GPU instance type detected"
    exit 1
    ;;
*)
    if [[ "$DEBIAN_VERSION" == "10" ]]; then
        AMIID=$(aws ec2 describe-images --owners 136693071363 --filters "Name=state,Values=available" "Name=name,Values=debian-10-amd64-*" --query "reverse(sort_by(Images, &CreationDate))[:1].ImageId" --output text)
        ROOT_DEVICE=$(aws ec2 describe-images --owners 136693071363 --filters "Name=state,Values=available" "Name=name,Values=debian-10-amd64-*" --query "reverse(sort_by(Images, &CreationDate))[:1].RootDeviceName" --output text)
    else
        AMIID=$(aws ec2 describe-images --owners 379101102735 --filters "Name=state,Values=available" "Name=name,Values=debian-stretch-hvm-x86_64*" --query "reverse(sort_by(Images, &CreationDate))[:1].ImageId" --output text)
        ROOT_DEVICE=$(aws ec2 describe-images --owners 379101102735 --filters "Name=state,Values=available" "Name=name,Values=debian-stretch-hvm-x86_64*" --query "reverse(sort_by(Images, &CreationDate))[:1].RootDeviceName" --output text)
    fi
    ;;
esac

# setup userdata
cat ./userdata-debian >/tmp/userdata
cat <<EOF >>/tmp/userdata
echo ECS_CLUSTER=$CLUSTERNAME >> /etc/ecs/ecs.config
systemctl start ecs
EOF

# get spot price
price=$(aws ec2 describe-spot-price-history --instance-type "$INSTANCE_TYPE" --region "$REGION" --product-description "Linux/UNIX" --availability-zone "${REGION}a" | jq -r ".SpotPriceHistory[0].SpotPrice")
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
    --block-device-mapping "[{\"DeviceName\":\"${ROOT_DEVICE}\",\"Ebs\":{\"VolumeSize\":100}}]" \
    --associate-public-ip-address | jq -r ".Instances[0].InstanceId")

printf " instanceID=$INSTANCE_ID"
sleep 2
PUBLIC_IP_ADDR=$(aws ec2 describe-instances --region "$REGION" --instance-ids "$INSTANCE_ID" | jq -r ".Reservations[0].Instances[0].PublicIpAddress")
echo " publicIPAddress=$PUBLIC_IP_ADDR"
