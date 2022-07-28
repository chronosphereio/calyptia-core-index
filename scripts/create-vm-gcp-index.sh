#!/bin/bash
set -u

IMAGE_KEY=${IMAGE_KEY:-calyptia-core-release}
GCP_INDEX_FILE=${GCP_INDEX_FILE:-gcp.index.json}

if gcloud config get-value account | grep -q unset; then
    echo "ERROR: authenticate with gcloud first"
    exit 1
else
    # Sort by most recent any images with an appropriate label specified,
    # ensure we exclude PRs and then pick only latest one for a release
    gcloud compute images list --no-standard-images --sort-by='~creationTimestamp' \
        --filter="labels.$IMAGE_KEY ~ .+ AND name ~ gold-calyptia-core*" \
        --format='json(name,labels,storageLocations)' | jq 'unique_by(.labels."calyptia-core-release")' | tee "$GCP_INDEX_FILE"
fi
