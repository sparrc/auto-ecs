#!/bin/bash
set -eou pipefail

echo "Did you login to ecr already? (y/n)"
read yn
if [[ "$yn" != "y" ]]; then
    echo "run 'aws ecr get-login --no-include-email'"
    exit 1
fi

NAME="${1:-}"
if [[ "$NAME" == "" ]]; then
    echo "You must specify a container/repo name"
    exit 1
fi

docker build -t "$NAME" .
repoURI=$(aws ecr create-repository --repository-name "$NAME"-repo | jq -r .repository.repositoryUri)
docker tag "$NAME" "$repoURI"

echo "Docker Repo URI: $repoURI"

docker push "$repoURI"

cat << EOF > ./repo.json
{
  "repoURI": "$repoURI"
}
EOF

