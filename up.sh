#!/bin/bash
set -eou pipefail

NAME="${1:-}"
if [[ "$NAME" == "" ]]; then
    tmp=$(head -c150 /dev/urandom | tr -dc 'a-z' | head -c4)
    NAME="auto-$tmp"
fi

# configure the cluster
ecs-cli configure --cluster "$NAME" --config-name "$NAME" --region us-west-2 --default-launch-type EC2

# bring the cluster up
upout=$(ecs-cli up --cluster-config "$NAME" --instance-role ecsInstanceRole --instance-type m5.large --keypair dev-ec2 --extra-user-data ./user-data.sh | tee /dev/stderr)

# parse all the IDs out of the cluster up output
vpcID=$(echo "$upout" | grep "VPC created" | sed -E 's/.*(vpc-.+$)/\1/')
subnet1ID=$(echo "$upout" | grep "Subnet created" | sed -E 's/.*(subnet-.+$)/\1/' | head -n 1)
subnet2ID=$(echo "$upout" | grep "Subnet created" | sed -E 's/.*(subnet-.+$)/\1/' | grep -v "$subnet1ID")
sgID=$(echo "$upout" | grep "Security Group created" | sed -E 's/.*(sg-.+$)/\1/')

# allow inbound ssh connections in the cluster's security group
aws ec2 authorize-security-group-ingress --group-id "$sgID" --protocol tcp --port 22 --cidr 0.0.0.0/0

cat << EOF > ./cluster.json
{
  "clusterName": "$NAME",
  "vpcID": "$vpcID",
  "sgID": "$sgID",
  "subnet1ID": "$subnet1ID",
  "subnet2ID": "$subnet2ID"
}
EOF

repoURI=$(cat ./repo.json | jq -r .repoURI)

serviceID="$NAME-srvc-$(head -c150 /dev/urandom | tr -dc 'a-z' | head -c4)"
echo "Composing service ID $serviceID"

cat << EOF > ./docker-compose.yml
version: '3'
services:
  $serviceID:
    image: $repoURI:latest
    ports:
      - "80:80"
    logging:
      driver: awslogs
      options:
        awslogs-group: $NAME
        awslogs-region: us-west-2
        awslogs-stream-prefix: $serviceID
EOF

cat << EOF > ecs-params.yml
version: 1
task_definition:
  task_execution_role: ecsTaskExecutionRole
  ecs_network_mode: awsvpc
  task_size:
    mem_limit: 0.5GB
    cpu_limit: 256
run_params:
  network_configuration:
    awsvpc_configuration:
      subnets:
        - "$subnet1ID"
        - "$subnet2ID"
      security_groups:
        - "$sgID"
      assign_public_ip: DISABLED
EOF

ecs-cli compose --project-name "$NAME" service up --create-log-groups --cluster-config "$NAME"

containerARN=$(aws ecs list-container-instances --cluster "$NAME" | jq -r '.containerInstanceArns[]')
containerID=$(aws ecs describe-container-instances --cluster "$NAME" --container-instances "$containerARN" | jq -r '.containerInstances[].ec2InstanceId')
publicIP=$(aws ec2 describe-instances --instance-ids "$containerID" | jq -r '.Reservations[].Instances[].PublicIpAddress')

echo "SSH to Your Container Instance: ssh ec2-user@$publicIP"

