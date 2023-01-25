#!/bin/bash
set -eo pipefail

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

OS="${3:-}"

SGID=$(jq -r .sgID <"./clusters/$CLUSTERNAME.json")
SUBNETID=$(jq -r .subnet1ID <"./clusters/$CLUSTERNAME.json")
CLUSTERNAME=$(jq -r .clusterName <"./clusters/$CLUSTERNAME.json")
REGION=$(jq -r .region <"./clusters/$CLUSTERNAME.json")

AMIID=""
TYPE_PREFIX="${INSTANCE_TYPE:0:3}"

case $OS in
bottlerocket)
    AMIID=$(aws ssm get-parameter --region "$REGION" --name "/aws/service/bottlerocket/aws-ecs-1/x86_64/latest/image_id" --query "Parameter.Value" --output text)
    ;;
al2)
    AMIID=$(aws ssm get-parameters --region "$REGION" --names /aws/service/ecs/optimized-ami/amazon-linux-2/recommended/image_id --query "Parameters[0].Value" --output text)
    ;;
al2022)
    AMIID=$(aws ssm get-parameters --region "$REGION" --names /aws/service/ecs/optimized-ami/amazon-linux-2022/recommended/image_id --query "Parameters[0].Value" --output text)
    ;;
al2-generic)
    AMIID=$(aws ssm get-parameters --region "$REGION" --names "/aws/service/ami-amazon-linux-latest/amzn2-ami-minimal-hvm-x86_64-ebs" --query "Parameters[0].Value" --output text)
    ;;
al2022-minimal)
    AMIID=$(aws ssm get-parameters --region "$REGION" --names /aws/service/ami-amazon-linux-latest/al2022-ami-minimal-kernel-default-x86_64 --query 'Parameters[0].[Value]' --output text)
    ;;
al2022-generic)
    AMIID=$(aws ec2 describe-images --region "$REGION" --owners amazon --filters "Name=name,Values=al2022-ami-minimal-2022.0.*" "Name=architecture,Values=x86_64" --query "reverse(sort_by(Images, &CreationDate))[0].ImageId" --output text)
    ;;
al2022arm-generic)
    AMIID=$(aws ec2 describe-images --region "$REGION" --owners amazon --filters "Name=name,Values=al2022-ami-minimal-2022.0.*" "Name=architecture,Values=arm64" --query "reverse(sort_by(Images, &CreationDate))[0].ImageId" --output text)
    ;;
al1)
    AMIID=$(aws ssm get-parameters --region "$REGION" --names /aws/service/ecs/optimized-ami/amazon-linux/recommended/image_id | jq -r ".Parameters[0].Value")
    ;;
*)
    if [ -z "$OS" ]; then
        case $TYPE_PREFIX in
        a1. | m6g | c6g | r6g | t4g | g5g)
            echo "ARM instance type detected"
            AMIID=$(aws ssm get-parameters --region "$REGION" --names /aws/service/ecs/optimized-ami/amazon-linux-2/arm64/recommended/image_id --query "Parameters[0].Value" --output text)
            ;;
        p2. | p3. | p4d | g4d | g3s | g3. | g5.)
            echo "GPU instance type detected"
            AMIID=$(aws ssm get-parameters --region "$REGION" --names /aws/service/ecs/optimized-ami/amazon-linux-2/gpu/recommended/image_id --query "Parameters[0].Value" --output text)
            ;;
        inf)
            echo "INF instance type detected"
            AMIID=$(aws ssm get-parameters --region "$REGION" --names /aws/service/ecs/optimized-ami/amazon-linux-2/inf/recommended/image_id --query "Parameters[0].Value" --output text)
            ;;
        *)
            echo "Regular instance type, getting AL2 ECS-Optimized AMI"
            AMIID=$(aws ssm get-parameters --region "$REGION" --names /aws/service/ecs/optimized-ami/amazon-linux-2/recommended/image_id --query "Parameters[0].Value" --output text)
            ;;
        esac
    else
        AMIID="$OS"
    fi
    ;;
esac

echo "ami id = $AMIID"

# setup userdata
if [[ $OS == "bottlerocket" ]]; then
    cat <<EOF >/tmp/userdata
[settings.ecs]
cluster = "$CLUSTERNAME"
EOF
else
    cat ./userdata >/tmp/userdata
    cat <<EOF >>/tmp/userdata
echo ECS_CLUSTER=$CLUSTERNAME >> /etc/ecs/ecs.config
EOF
fi

if [ -f ./setup-repos ]; then
    cat ./setup-repos >>/tmp/userdata
fi

# get root device name
ROOT_DEVICE_NAME=$(aws ec2 describe-images --region "$REGION" --image-ids "$AMIID" --query "Images[0].RootDeviceName" --output text)

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
    --block-device-mapping "[{\"DeviceName\":\"${ROOT_DEVICE_NAME}\",\"Ebs\":{\"VolumeSize\":100,\"VolumeType\":\"gp3\"}}]" \
    --associate-public-ip-address \
    --query "Instances[0].InstanceId" --output text)

printf " instanceID=$INSTANCE_ID"
sleep 2
PUBLIC_IP_ADDR=$(aws ec2 describe-instances --region "$REGION" --instance-ids "$INSTANCE_ID" --query "Reservations[0].Instances[0].PublicIpAddress" --output text)
echo " publicIPAddress=$PUBLIC_IP_ADDR"
