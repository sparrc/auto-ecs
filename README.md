# auto-ecs
scripts for auto-setup of an ECS cluster and agent workdir

### Directions:

Pre-req: AWS access configured, awscli and ecscli installed

```bash
# setup config file
cat << EOF > ./config.json
{
  "ec2_container_instance_type": "m5.xlarge",
  "ssh_keypairs": {
    "us-west-2": "dev-ec2"
  }
}
EOF
# create a cluster in us-west-2 (this will have no instances)
./up.sh us-west-2 myCluster
# add an ec2 container instance to cluster
./add-new-instance.sh myCluster
# register a task definition
aws ecs register-task-definition --region us-west-2 --cli-input-json file://sampletask.json
# run the task definition "dd" on cluster
./runtask.sh myCluster dd
```

### Teardown:
  
1. Run `down.sh CLUSTER_NAME` to kill the service and teardown the ECS cluster stack.

