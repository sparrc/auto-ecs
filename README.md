# auto-ecs
scripts for auto-setup of an ECS cluster and agent workdir

### Directions:

Pre-reqs: 
1. AWS access configured
1. awscli, ecscli and jq installed
1. ssh key imported to desired region(s), ie:
```
aws ec2 import-key-pair --region us-west-2 --key-name "macbook" --public-key-material fileb://~/.ssh/id_rsa.pub
```

```bash
# setup config file with a mapping of regions to ssh keypair names:
cat << EOF > ./config.json
{
  "ssh_keypairs": {
    "us-west-2": "macbook"
  }
}
EOF
# create a cluster in us-west-2 (this will have no instances)
./create-cluster.sh us-west-2 myCluster
# add an m5.large ec2 container instance to cluster (defaults to m5.large)
./add-instance-to-cluster.sh myCluster m5.large
# register a task definition
aws ecs register-task-definition --region us-west-2 --cli-input-json file://sampletask.json
# run the task definition "dd" on cluster
./run-task.sh myCluster dd
```

### Teardown:
  
1. Run `delete-cluster.sh CLUSTER_NAME` terminate all instances in cluster and delete it's cloudformation stack.

