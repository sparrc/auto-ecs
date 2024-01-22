#!/bin/bash
set -eo pipefail

CLUSTERNAME="${1:-}"
if [ -z "$CLUSTERNAME" ]; then
    echo "You must specify a cluster to add the instance to"
    exit 1
fi

INSTANCE_TYPE="${2:-}"
if [ -z "$INSTANCE_TYPE" ]; then
    echo "You must specify instance type"
    exit 1
fi

OS="${3:-}"
if [ -z "$OS" ]; then
    echo "You must specify OS"
    exit 1
fi

SGID=$(jq -r .sgID <"./clusters/$CLUSTERNAME.json")
SUBNETID=$(jq -r .subnet1ID <"./clusters/$CLUSTERNAME.json")
CLUSTERNAME=$(jq -r .clusterName <"./clusters/$CLUSTERNAME.json")
REGION=$(jq -r .region <"./clusters/$CLUSTERNAME.json")

AMIID=""
DEFAULT_USER="ec2-user"
TYPE_PREFIX="${INSTANCE_TYPE:0:3}"
case $TYPE_PREFIX in
a1. | m6g | c6g | r6g | t4g)
    echo "ARM instance type detected"
    case $OS in
    ubuntu)
        AMIID=$(aws ssm get-parameters --names "/aws/service/canonical/ubuntu/server/20.04/stable/current/arm64/hvm/ebs-gp2/ami-id" --query "Parameters[0].Value" --output text)
        DEFAULT_USER="ubuntu"
        ;;
    debian)
        AMIID=$(aws ec2 describe-images --owners 136693071363 --filters "Name=state,Values=available" "Name=name,Values=debian-10-arm64-*" --query "reverse(sort_by(Images, &CreationDate))[:1].ImageId" --output text)
        DEFAULT_USER="admin"
        ;;
    centos)
        AMIID=$(aws ec2 describe-images --owners 125523088429 --filters "Name=state,Values=available" "Name=name,Values=CentOS 8*" "Name=architecture,Values=arm64" --query "reverse(sort_by(Images, &CreationDate))[:1].ImageId" --output text)
        DEFAULT_USER="centos"
        ;;
    al2)
        AMIID=$(aws ssm get-parameters --region "$REGION" --names /aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-arm64-gp2 --query "Parameters[0].Value" --output text)
        ;;
    sles)
        AMIID=$(aws ec2 describe-images --owners 013907871322 --filters "Name=state,Values=available" "Name=name,Values=suse-sles-15-sp?-v????????-hvm*" "Name=architecture,Values=arm64" --query "reverse(sort_by(Images, &CreationDate))[:1].ImageId" --output text)
        ;;
    esac
    ;;
p2. | p3. | p4d | g4d | g3s | g3.)
    echo "GPU instance type detected"
    echo "GPU not supported"
    exit 1
    ;;
inf)
    echo "INF instance type detected"
    echo "INF not supported"
    exit 1
    ;;
*)
    case $OS in
    ubuntu-18)
        AMIID=$(aws ssm get-parameters --names "/aws/service/canonical/ubuntu/server/18.04/stable/current/amd64/hvm/ebs-gp2/ami-id" --query "Parameters[0].Value" --output text)
        DEFAULT_USER="ubuntu"
        ;;
    ubuntu)
        AMIID=$(aws ssm get-parameters --names "/aws/service/canonical/ubuntu/server/20.04/stable/current/amd64/hvm/ebs-gp2/ami-id" --query "Parameters[0].Value" --output text)
        DEFAULT_USER="ubuntu"
        ;;
    ubuntu-22)
        AMIID=$(aws ssm get-parameters --names "/aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp2/ami-id" --query "Parameters[0].Value" --output text)
        DEFAULT_USER="ubuntu"
        ;;
    debian-10)
        AMIID=$(aws ec2 describe-images --owners 136693071363 --filters "Name=state,Values=available" "Name=name,Values=debian-10-amd64-*" --query "reverse(sort_by(Images, &CreationDate))[:1].ImageId" --output text)
        DEFAULT_USER="admin"
        ;;
    debian-11)
        AMIID=$(aws ec2 describe-images --owners 136693071363 --filters "Name=state,Values=available" "Name=name,Values=debian-11-amd64-*" --query "reverse(sort_by(Images, &CreationDate))[:1].ImageId" --output text)
        DEFAULT_USER="admin"
        ;;
    centos)
        AMIID=$(aws ec2 describe-images --owners 125523088429 --filters "Name=state,Values=available" "Name=name,Values=CentOS Stream 8*" "Name=architecture,Values=x86_64" --query "reverse(sort_by(Images, &CreationDate))[:1].ImageId" --output text)
        DEFAULT_USER="centos"
        ;;
    al2)
        AMIID=$(aws ssm get-parameters --region "$REGION" --names /aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2 --query "Parameters[0].Value" --output text)
        ;;
    al1)
        AMIID=$(aws ssm get-parameters --region "$REGION" --names /aws/service/ami-amazon-linux-latest/amzn-ami-hvm-x86_64-gp2 --query "Parameters[0].Value" --output text)
        ;;
    sles)
        AMIID=$(aws ec2 describe-images --owners 013907871322 --filters "Name=state,Values=available" "Name=name,Values=suse-sles-15-sp?-v????????-hvm*" "Name=architecture,Values=x86_64" --query "reverse(sort_by(Images, &CreationDate))[:1].ImageId" --output text)
        ;;
    *)
        AMIID="$OS"
    esac
    ;;
esac

echo "Using AMI ID: $AMIID"

# setup userdata
cat ./anywhere-userdata | sed "s/DEFAULT_USER/$DEFAULT_USER/g" >/tmp/userdata
cat <<EOF >>/tmp/userdata
echo ECS_CLUSTER=$CLUSTERNAME >> /etc/ecs/ecs.config
EOF

# get root device name
ROOT_DEVICE_NAME=$(aws ec2 describe-images --image-ids "$AMIID" --query "Images[0].RootDeviceName" --output text)

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
    --count 1 \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "auto-ecs-ed25519" \
    --user-data file:///tmp/userdata \
    --security-group-ids "$SGID" \
    --subnet-id "$SUBNETID" \
    --region "$REGION" \
    --block-device-mapping "[{\"DeviceName\":\"${ROOT_DEVICE_NAME}\",\"Ebs\":{\"VolumeSize\":100,\"VolumeType\":\"gp3\"}}]" \
    --associate-public-ip-address \
    --instance-initiated-shutdown-behavior "terminate" \
    --query "Instances[0].InstanceId" --output text)

printf " instanceID=$INSTANCE_ID"
sleep 2
PUBLIC_IP_ADDR=$(aws ec2 describe-instances --region "$REGION" --instance-ids "$INSTANCE_ID" --query "Reservations[0].Instances[0].PublicIpAddress" --output text)
echo " publicIPAddress=$DEFAULT_USER@$PUBLIC_IP_ADDR"
