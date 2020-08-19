#!/bin/bash
set -eou pipefail

CLUSTERNAME="${1:-}"
if [[ "$CLUSTERNAME" == "" ]]; then
    echo "You must specify a cluster to add the instance to"
    exit 1
fi

SGID=$(jq -r .sgID < "./clusters/$CLUSTERNAME.json")
SUBNETID=$(jq -r .subnet1ID < "./clusters/$CLUSTERNAME.json")
CLUSTERNAME=$(jq -r .clusterName < "./clusters/$CLUSTERNAME.json")
REGION=$(jq -r .region < "./clusters/$CLUSTERNAME.json")

SSH_KEY_NAME=$(jq -r ".ssh_keypairs.\"$REGION\"" < config.json)
INSTANCE_TYPE=$(jq -r .ec2_container_instance_type < ./config.json)

## Linux AMI and userdata
AMIID=$(aws ssm get-parameters --region "$REGION" --names /aws/service/ecs/optimized-ami/amazon-linux-2/recommended/image_id | jq -r ".Parameters[0].Value")

cat << EOF > /tmp/userdata
#!/bin/bash
echo ECS_CLUSTER=$CLUSTERNAME >> /etc/ecs/ecs.config
EOF
cat ./userdata >> /tmp/userdata
##

## Windows AMI and userdata
#AMIID=$(aws ssm get-parameters --names /aws/service/ami-windows-latest/Windows_Server-2019-English-Full-ECS_Optimized/image_id | jq -r ".Parameters[0].Value")
#
#cat << EOF > /tmp/userdata
#<powershell>
#[Environment]::SetEnvironmentVariable("ECS_ENABLE_SPOT_INSTANCE_DRAINING", "true", "Machine")
#Import-Module ECSTools
#Initialize-ECSAgent -Cluster '$CLUSTERNAME' -EnableTaskIAMRole
#</powershell>
#EOF
##

ID=$(head -c120 /dev/urandom | tr -dc 'a-z' | head -c3)
printf "Launching instance. name=$CLUSTERNAME-$ID amiID=$AMIID type=$INSTANCE_TYPE"
INSTANCE_ID=$(aws ec2 run-instances --image-id "$AMIID" --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$CLUSTERNAME-$ID}]" --iam-instance-profile Name=ecsInstanceRole --count 1 --instance-type "$INSTANCE_TYPE" --key-name "$SSH_KEY_NAME" --user-data file:///tmp/userdata --security-group-ids "$SGID" --subnet-id "$SUBNETID" --region "$REGION" --block-device-mapping "[{\"DeviceName\":\"/dev/xvda\",\"Ebs\":{\"VolumeSize\":100}}]" --associate-public-ip-address | jq -r ".Instances[0].InstanceId")

printf " instanceID=$INSTANCE_ID"
PUBLIC_IP_ADDR=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" | jq -r ".Reservations[0].Instances[0].PublicIpAddress")
echo " publicIPAddress=$PUBLIC_IP_ADDR"

