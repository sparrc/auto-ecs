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

repoURI=$(jq -r .repoURI < ./repo.json)
docker build -t "$NAME" .
docker tag "$NAME" "$repoURI"

docker push "$repoURI"

