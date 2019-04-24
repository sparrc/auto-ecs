#!/bin/bash
set -eou pipefail

repoURI=$(cat ./repo.json | jq -r .repoURI)
vpcID=$(cat ./cluster.json | jq -r .vpcID)
sgID=$(cat ./cluster.json | jq -r .sgID)
subnet1ID=$(cat ./cluster.json | jq -r .subnet1ID)
subnet2ID=$(cat ./cluster.json | jq -r .subnet2ID)
name=$(cat ./cluster.json | jq -r .clusterName)

serviceID="$name-srvc-$(head -c150 /dev/urandom | tr -dc 'a-z' | head -c4)"
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
        awslogs-group: $name
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

ecs-cli compose --project-name "$name" service up --create-log-groups --cluster-config "$name"

containerARN=$(aws ecs list-container-instances --cluster "$name" | jq -r '.containerInstanceArns[]')
containerID=$(aws ecs describe-container-instances --cluster "$name" --container-instances "$containerARN" | jq -r '.containerInstances[].ec2InstanceId')
publicIP=$(aws ec2 describe-instances --instance-ids "$containerID" | jq -r '.Reservations[].Instances[].PublicIpAddress')

echo "Public IP of your Container Instance: $publicIP"

