#!/bin/bash
set -eou pipefail

INSTANCE_TYPE="${1:-}"
if [[ "$INSTANCE_TYPE" == "" ]]; then
    echo "You must specify an instance type"
    exit 1
fi

AMIID=$(aws ssm get-parameters --region us-west-2 --names /aws/service/ecs/optimized-ami/amazon-linux-2/recommended | jq -r ".Parameters[0].Value" | jq -r .image_id)
SGID=$(jq -r .sgID < ./cluster.json)
SUBNETID=$(jq -r .subnet1ID < ./cluster.json)
CLUSTERNAME=$(jq -r .clusterName < ./cluster.json)

cat << EOF > /tmp/user-data.sh
#!/bin/bash
echo ECS_CLUSTER=$CLUSTERNAME >> /etc/ecs/ecs.config
echo ECS_LOGLEVEL=warn >> /etc/ecs/ecs.config
EOF

aws ec2 run-instances --image-id "$AMIID" --iam-instance-profile Name=ecsInstanceRole --count 1 --instance-type "$INSTANCE_TYPE" --key-name dev-ec2 --user-data file:///tmp/user-data.sh --security-group-ids "$SGID" --subnet-id "$SUBNETID" --associate-public-ip-address

