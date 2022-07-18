#!/bin/bash
set -u

GITHUB_TOKEN=${GITHUB_TOKEN:?}
CONTAINER_PACKAGE=${CONTAINER_PACKAGE:-calyptia/core}
CONTAINER_INDEX_FILE=${CONTAINER_INDEX_FILE:-container.index.json}

IMAGE_KEY=${GCP_IMAGE_LABEL:-calyptia-core-release}
GCP_INDEX_FILE=${GCP_INDEX_FILE:-gcp.index.json}
AWS_INDEX_FILE=${AWS_INDEX_FILE:-aws.index.json}

# Assumption for AWS and GCP is authentication is complete prior to this script

GHCR_TOKEN=$(echo "$GITHUB_TOKEN" | base64)

curl --silent -H "Authorization: Bearer $GHCR_TOKEN" https://ghcr.io/v2/"${CONTAINER_PACKAGE}"/tags/list | \
    jq -r '.tags | map(select(.| test("^v(.*)")))' | tee "$CONTAINER_INDEX_FILE"

# Sort by most recent any images with an appropriate label specified
gcloud compute images list --no-standard-images --sort-by='~creationTimestamp' \
    --filter="labels.$IMAGE_KEY ~ .+" --format='json(name,labels)' | tee "$GCP_INDEX_FILE"

# For the query make sure to use a capital letter for relabelling
aws ec2 describe-images --owners self --filters "Name=tag-key,Values=$IMAGE_KEY" \
    --query 'Images[] | sort_by(@, &CreationDate)[].{ImageId: Id, Name: Name, Tags: Tags}' --output=json | tee "$AWS_INDEX_FILE"
