# auto-ecs
scripts for auto-setup of an ECS cluster and agent workdir

### Directions:

1. Setup your config file:
```
cat << EOF > ./config.json
{
  "github_username": "sparrc",
  "ec2_container_instance_type": "t3.large",
  "ec2_ssh_keypair_name": "my-dev-keypair",
  "aws_region": "us-west-2"
}
EOF
```
1. PRE-REQ: have an AWS account and be authorized to create resources. Install aws-cli, ecs-cli, and docker. Use docker to login to ecr (`aws ecr get-login --no-include-email`)
1. Run create-ecr-repo.sh. This will build your docker image and push it to a repo in ECR. It will then create a file called `repo.json` that the next step needs.
1. PRE-REQ: up.sh expects an ssh keypair named `dev-ec2`. You can modify the script to match yours.
1. Run up.sh. This will create an ecs cluster and start an ecs service created from the files `docker-compose.yml` and `ecs-params.yml`. It will create a file called cluster.json with some data about the cluster.
1. The previous command will print the public IP address of the 

### Teardown:

1. Run `down.sh [CLUSTER_NAME]` to kill the service and teardown the ECS cluster stack. Cluster name is optional and if not passed will be gotten from the cluster.json file.

