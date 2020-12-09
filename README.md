# auto-ecs
scripts for auto-setup of an ECS cluster and agent workdir


### Pre-reqs: 

1. AWS access configured
2. awscli, ecs-cli and jq installed
3. create an IAM role called ecsInstanceRole with the following policy attached: AmazonEC2ContainerServiceforEC2Role. see [here](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/instance_IAM_role.html) for more details on this role.
4. [your ssh key](https://help.github.com/articles/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent/) imported to all regions:
```
./create-key-pairs.sh ~/.ssh/id_rsa.pub
```

### Directions:

```bash
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
 
1. Run `remove-instances-from-cluster.sh CLUSTER_NAME` to terminate all instances in cluster, but keep the cluster.
1. Run `delete-cluster.sh CLUSTER_NAME` to terminate all instances in cluster and delete it's cloudformation stack.

