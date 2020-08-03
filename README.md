# auto-ecs
scripts for auto-setup of an ECS cluster and agent workdir

### Directions:

1. Setup your config file (ssh_keypairs is the name of your ssh keypair to use for the ecs container instance):
```
cat << EOF > ./config.json
{
  "ec2_container_instance_type": "m5.xlarge",
  "ssh_keypairs": {
    "us-east-1": "us-east-1",
    "us-west-2": "dev-ec2"
  }
}
EOF
```
1. PRE-REQ: have an AWS account and be authorized to create resources. Install aws-cli, ecs-cli, and docker.
1. Run up.sh. This will create an ecs cluster with one container instance registered. It creates a file in the clusters/ directory with some necessary metadata for adding instances and other operations.
1. Create a task definition with something like the following command: `aws ecs register-task-definition --region us-west-2 --cli-input-json file://sampletask.json`
1. Run runtask.sh to run a task, editing the task definition name as needed.

### Teardown:
  
1. Run `down.sh [CLUSTER_NAME]` to kill the service and teardown the ECS cluster stack. Cluster name is optional and if not passed will be gotten from the cluster.json file.

