#!/bin/bash
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# Limit via credentials to what is required, this also prevents any races with updating the
# same files in multiple PRs or jobs.
if [[ -n "$GITHUB_TOKEN" ]]; then
    echo "Detected GITHUB_TOKEN so running container index generation"
    "$SCRIPT_DIR/create-container-index.sh"
fi

if [[ -n "$AWS_ACCESS_KEY_ID" ]]; then
    echo "Detected AWS_ACCESS_KEY_ID so running AWS VM index generation"
    "$SCRIPT_DIR/create-vm-aws-index.sh"
fi

if [[ -n "$GOOGLE_APPLICATION_CREDENTIALS" ]]; then
    echo "Detected GOOGLE_APPLICATION_CREDENTIALS so running GCP VM index generation"
    "$SCRIPT_DIR/create-vm-gcp-index.sh"
fi
