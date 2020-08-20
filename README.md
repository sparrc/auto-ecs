# auto-ecs
scripts for auto-setup of an ECS cluster and agent workdir

### Directions:

Pre-req: AWS access configured, awscli, ecscli and jq installed

```bash
# setup config file
cat << EOF > ./config.json
{
  "ssh_keypairs": {
    "us-west-2": "dev-ec2"
  }
}
EOF
# create a cluster in us-west-2 (this will have no instances)
./create-cluster.sh us-west-2 myCluster
# add an m5.2xlarge ec2 container instance to cluster (defaults to m5.xlarge)
./add-instance-to-cluster.sh myCluster m5.2xlarge
# register a task definition
aws ecs register-task-definition --region us-west-2 --cli-input-json file://sampletask.json
# run the task definition "dd" on cluster
./run-task.sh myCluster dd
```

### Teardown:
  
1. Run `delete-cluster.sh CLUSTER_NAME` terminate all instances in cluster and delete it's cloudformation stack.

