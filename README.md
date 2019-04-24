# auto-ecs
scripts for auto-setup of an ECS cluster and agent workdir

### Directions:

1. PRE-REQ: have an AWS account and be authorized to create resources. Install aws-cli, ecs-cli, and docker. Use docker to login to ecr (`aws ecr get-login --no-include-email`)
1. Run create-ecr-repo.sh. This will build your docker image and push it to a repo in ECR. It will then create a file called `repo.json` that the next step needs.
1. Run create-ecs-cluster.sh. This will create an ecs cluster and then drop the configuration into a file called `cluster.json`, which will be needed by the next step.
1. Run create-service.sh. This will use `ecs-cli compose` to start an ecs service created from the files `docker-compose.yml` and `ecs-params.yml`.
1. After the service is running it will get the public IP address of the container instance, which will have the amazon-ecs-agent repo cloned to it and ready to modify.

