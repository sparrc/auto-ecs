#!/bin/bash
set -eou pipefail

clusterName="${1:-}"
if [[ "$clusterName" == "" ]]; then
    tmp=$(head -c150 /dev/urandom | tr -dc 'a-z' | head -c4)
    clusterName="auto-$tmp"
fi

region=$(jq -r .aws_region < ./config.json)
# configure the cluster
ecs-cli configure --cluster "$clusterName" --config-name "$clusterName" --region "$region" --default-launch-type EC2

instance=$(jq -r .ec2_container_instance_type < ./config.json)
key=$(jq -r .ec2_ssh_keypair_name < ./config.json)

# bring the cluster up
upout=$(ecs-cli up --cluster-config "$clusterName" --instance-role ecsInstanceRole --instance-type "$instance" --keypair "$key" --extra-user-data ./user-data.sh 2>&1 | tee /dev/stderr)

# parse all the IDs out of the cluster up output
vpcID=$(echo "$upout" | grep "VPC created" | sed -E 's/.*(vpc-.+$)/\1/')
subnet1ID=$(echo "$upout" | grep "Subnet created" | sed -E 's/.*(subnet-.+$)/\1/' | head -n 1)
subnet2ID=$(echo "$upout" | grep "Subnet created" | sed -E 's/.*(subnet-.+$)/\1/' | grep -v "$subnet1ID")
sgID=$(echo "$upout" | grep "Security Group created" | sed -E 's/.*(sg-.+$)/\1/')

# allow inbound ssh connections in the cluster's security group
aws ec2 authorize-security-group-ingress --group-id "$sgID" --protocol tcp --port 22 --cidr 0.0.0.0/0

serviceName="service-$(head -c150 /dev/urandom | tr -dc 'a-z' | head -c3)"
echo "Composing service name $serviceName"

cat << EOF > ./cluster.json
{
  "clusterName": "$clusterName",
  "serviceName": "$serviceName",
  "vpcID": "$vpcID",
  "sgID": "$sgID",
  "subnet1ID": "$subnet1ID",
  "subnet2ID": "$subnet2ID"
}
EOF

repoURI=$(cat ./repo.json | jq -r .repoURI)

cat << EOF > ./docker-compose.yml
version: '3'
services:
  $serviceName:
    image: $repoURI:latest
    ports:
      - "80:80"
    logging:
      driver: awslogs
      options:
        awslogs-group: auto-ecs-cluster
        awslogs-region: us-west-2
        awslogs-stream-prefix: $clusterName
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

ecs-cli compose --project-name "$serviceName" service up --create-log-groups --cluster-config "$clusterName"
sleep 5

containerARN=$(aws ecs list-container-instances --cluster "$clusterName" | jq -r '.containerInstanceArns[]')
containerID=$(aws ecs describe-container-instances --cluster "$clusterName" --container-instances "$containerARN" | jq -r '.containerInstances[].ec2InstanceId')
publicIP=$(aws ec2 describe-instances --instance-ids "$containerID" | jq -r '.Reservations[].Instances[].PublicIpAddress')

echo "SSH to Your Container Instance: ssh ec2-user@$publicIP"

