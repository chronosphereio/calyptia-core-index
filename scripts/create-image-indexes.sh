#!/bin/bash
set -u

GITHUB_TOKEN=${GITHUB_TOKEN:?}
CONTAINER_PACKAGE=${CONTAINER_PACKAGE:-calyptia/core}
CONTAINER_INDEX_FILE=${CONTAINER_INDEX_FILE:-container.index.json}

IMAGE_KEY=${GCP_IMAGE_LABEL:-calyptia-core-release}
GCP_INDEX_FILE=${GCP_INDEX_FILE:-gcp.index.json}
AWS_INDEX_FILE=${AWS_INDEX_FILE:-aws.index.json}

# Assumption for GCP is authentication is complete prior to this script
AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID:?}
AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY:?}

GHCR_TOKEN=$(echo "$GITHUB_TOKEN" | base64)

curl --silent -H "Authorization: Bearer $GHCR_TOKEN" https://ghcr.io/v2/"${CONTAINER_PACKAGE}"/tags/list | \
    jq -r '.tags | map(select(.| test("^v(.*)")))' | tee "$CONTAINER_INDEX_FILE"

# For the query make sure to match the current
aws ec2 describe-images --owners self --filters "Name=tag-key,Values=$IMAGE_KEY" \
    --query 'Images[] | sort_by(@, &CreationDate)[].{CreationDate: CreationDate, ImageId: ImageId, Name: Name, Tags: Tags}' --output=json | tee "$AWS_INDEX_FILE"

# Sort by most recent any images with an appropriate label specified
gcloud compute images list --no-standard-images --sort-by='~creationTimestamp' \
    --filter="labels.$IMAGE_KEY ~ .+" --format='json(name,labels)' | tee "$GCP_INDEX_FILE"

