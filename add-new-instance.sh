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

#AMIID=$(aws ssm get-parameters --region "$REGION" --names /aws/service/ecs/optimized-ami/amazon-linux-2/recommended | jq -r ".Parameters[0].Value" | jq -r .image_id)
#AMIID="ami-097e3d1cdb541f43e" # 1.33.0 <- cloud-init, docker, and agent updates. yum update -y in cloud-boothook causes ecs agent to fail with result 'depdency'
#AMIID="ami-00afc256a955c31b5" # 1.35.0 <- cloud-init and agent updates, yum update -y worked, although ecs startup delayed a few minutes.
#AMIID="ami-056807e883f197989" # 1.36.2 <- agent update only, ecs startup not delayed.

#AMIID="ami-007571470797b8ffa" # 1.26.0

# AMIID="ami-0315d99b2650530ea" # windows 1.35.0

#AMIID="ami-097e3d1cdb541f43e" # 1.33.0 (us-east-1)
AMIID="ami-0a6a36557ea3b9859" #imdsv2
# Windows userdata:
#cat << EOF > /tmp/userdata
#<powershell>
#[Environment]::SetEnvironmentVariable("ECS_ENABLE_SPOT_INSTANCE_DRAINING", "true", "Machine")
#Import-Module ECSTools
#Initialize-ECSAgent -Cluster '$CLUSTERNAME' -EnableTaskIAMRole
#</powershell>
#EOF

#cat << EOF > /tmp/userdata
##!/bin/bash
#echo ECS_CLUSTER=$CLUSTERNAME >> /etc/ecs/ecs.config
#EOF
#cat ./userdata >> /tmp/userdata

cat ./userdata-dockerboothook > /tmp/userdata

ID=$(head -c120 /dev/urandom | tr -dc 'a-z' | head -c3)
echo "Launching instance. name=$CLUSTERNAME-$ID amiID=$AMIID type=$INSTANCE_TYPE"
aws ec2 run-instances --image-id "$AMIID" --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$CLUSTERNAME-$ID}]" --iam-instance-profile Name=ecsInstanceRole --count 1 --instance-type "$INSTANCE_TYPE" --key-name "$SSH_KEY_NAME" --user-data file:///tmp/userdata --security-group-ids "$SGID" --subnet-id "$SUBNETID" --region "$REGION" --associate-public-ip-address >/dev/null

