#!/bin/bash
set -u

IMAGE_KEY=${IMAGE_KEY:-calyptia-core-release}
GCP_INDEX_FILE=${GCP_INDEX_FILE:-gcp.index.json}
IMAGE_NAME_PREFIX=${IMAGE_NAME_PREFIX:-gold-calyptia-core}

if gcloud config get-value account | grep -q unset; then
    echo "ERROR: authenticate with gcloud first"
    exit 1
else
    # Sort by most recent any images with an appropriate label specified,
    # ensure we exclude PRs and then pick only latest one for a release
    gcloud compute images list --no-standard-images --sort-by='~creationTimestamp' \
        --filter="labels.$IMAGE_KEY ~ .+ AND name ~ $IMAGE_NAME_PREFIX*" \
        --format='json(name,labels,storageLocations)' | jq "unique_by(.labels.\"$IMAGE_KEY\", .storageLocations)" | tee "$GCP_INDEX_FILE"
fi
