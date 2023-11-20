#!/bin/bash
set -u
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# Reuse existing scripts but redirect for test images
export IMAGE_KEY=${IMAGE_KEY:-calyptia-core-operator-release}
export GCP_INDEX_FILE=${GCP_INDEX_FILE:-$SCRIPT_DIR/../operator.gcp.test.index.json}
export AWS_INDEX_FILE=${AWS_INDEX_FILE:-$SCRIPT_DIR/../operator.aws.test.index.json}
export IMAGE_NAME_PREFIX=${IMAGE_NAME_PREFIX:-core-operator-test}

if [[ -n "$AWS_ACCESS_KEY_ID" ]]; then
    echo "Detected AWS_ACCESS_KEY_ID so running AWS VM index generation"
    "$SCRIPT_DIR/create-vm-aws-index.sh"
fi

if ! gcloud config get-value account | grep -q unset ; then
    echo "Detected gcloud authentication so running GCP VM index generation"
    "$SCRIPT_DIR/create-vm-gcp-index.sh"
fi
