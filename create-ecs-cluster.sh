#!/bin/bash
set -eou pipefail

NAME="${1:-}"
if [[ "$NAME" == "" ]]; then
    tmp=$(head -c150 /dev/urandom | tr -dc 'a-z' | head -c4)
    NAME="auto-$tmp"
fi

updown="${2:-up}"
if [[ "$updown" == "down" ]]; then
    ecs-cli compose --project-name "$NAME" service down --cluster-config "$NAME"
    ecs-cli down --force --cluster-config "$NAME"
    exit 0
fi

# configure the cluster
ecs-cli configure --cluster "$NAME" --config-name "$NAME" --region us-west-2 --default-launch-type EC2

# bring the cluster up
upout=$(ecs-cli up --cluster-config "$NAME" --instance-role ecsInstanceRole --instance-type t2.micro --keypair dev-ec2 --extra-user-data ./user-data.sh | tee /dev/stderr)

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

