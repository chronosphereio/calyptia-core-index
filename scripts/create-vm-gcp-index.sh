
#!/bin/bash
set -u

GOOGLE_APPLICATION_CREDENTIALS=${GOOGLE_APPLICATION_CREDENTIALS:?}

IMAGE_KEY=${IMAGE_KEY:-calyptia-core-release}
GCP_INDEX_FILE=${GCP_INDEX_FILE:-gcp.index.json}

# Try to keep any auth as private as possible
# https://serverfault.com/a/849910
CLOUDSDK_CONFIG=$(mktemp -d)

gcloud auth activate-service-account --key-file="$GOOGLE_APPLICATION_CREDENTIALS"

# Sort by most recent any images with an appropriate label specified
gcloud compute images list --no-standard-images --sort-by='~creationTimestamp' \
    --filter="labels.$IMAGE_KEY ~ .+" --format='json(name,labels)' | tee "$GCP_INDEX_FILE"

rm -rf "$CLOUDSDK_CONFIG"
