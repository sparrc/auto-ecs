#!/bin/bash
set -eou pipefail

region="${1:-}"
if [[ "$region" == "" ]]; then
    echo "you must specify a region to create the cluster"
    exit 1
fi

tmp=$(head -c120 /dev/urandom | tr -dc 'a-z0-9' | head -c2)
clusterName="$tmp"

# configure the cluster
ecs-cli configure --cluster "$clusterName" --config-name "$clusterName" --region "$region" --default-launch-type EC2

instance=$(jq -r .ec2_container_instance_type < ./config.json)
key=$(jq -r ".ssh_keypairs.\"$region\"" < config.json)

# bring the cluster up
upout=$(ecs-cli up --cluster-config "$clusterName" --instance-role ecsInstanceRole --instance-type "$instance" --keypair "$key" --extra-user-data ./userdata 2>&1 | tee /dev/stderr)

# parse all the IDs out of the cluster up output
vpcID=$(echo "$upout" | grep "VPC created" | sed -E 's/.*(vpc-.+$)/\1/')
subnet1ID=$(echo "$upout" | grep "Subnet created" | sed -E 's/.*(subnet-.+$)/\1/' | head -n 1)
subnet2ID=$(echo "$upout" | grep "Subnet created" | sed -E 's/.*(subnet-.+$)/\1/' | grep -v "$subnet1ID")
sgID=$(echo "$upout" | grep "Security Group created" | sed -E 's/.*(sg-.+$)/\1/')

# allow inbound ssh connections in the cluster's security group
aws ec2 authorize-security-group-ingress --region "$region" --group-id "$sgID" --protocol tcp --port 22 --cidr 0.0.0.0/0
# allow inbound windows RDP connections (this is used my windows remote desktop)
aws ec2 authorize-security-group-ingress --region "$region" --group-id "$sgID" --protocol tcp --port 3389 --cidr 0.0.0.0/0

cat << EOF > "./clusters/$clusterName.json"
{
  "clusterName": "$clusterName",
  "vpcID": "$vpcID",
  "sgID": "$sgID",
  "subnet1ID": "$subnet1ID",
  "subnet2ID": "$subnet2ID",
  "region": "$region"
}
EOF

