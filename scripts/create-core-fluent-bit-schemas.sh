#!/bin/bash
set -u
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

GITHUB_TOKEN=${GITHUB_TOKEN:?}
CONTAINER_PACKAGE=${CONTAINER_PACKAGE:-calyptia/core/calyptia-fluent-bit}
CONTAINER_RUNTIME=${CONTAINER_RUNTIME:-docker}
SCHEMA_DIR=${SCHEMA_DIR:-$SCRIPT_DIR/../schemas}
SCHEMA_FILENAME=${SCHEMA_FILENAME:-core-fluent-bit}

GHCR_TOKEN=$(echo "$GITHUB_TOKEN" | base64)

TAGS=$(curl --silent -H "Authorization: Bearer $GHCR_TOKEN" https://ghcr.io/v2/"${CONTAINER_PACKAGE}"/tags/list?n=100000 | \
    jq -r '.tags | map(select(.| test("^(22\\.|v)(.*)")))|flatten[]') 
# Test for tags beginning with v* or 22.*: https://github.com/stedolan/jq/issues/1250#issuecomment-252396642

for TAG in $TAGS; do
    mkdir -p "${SCHEMA_DIR}/${TAG}"
    "$CONTAINER_RUNTIME" run --pull=always --rm -t "ghcr.io/${CONTAINER_PACKAGE}:${TAG}" -J > "${SCHEMA_DIR}/${TAG}/${SCHEMA_FILENAME}.json"
    jq -M . "${SCHEMA_DIR}/${TAG}/${SCHEMA_FILENAME}.json" > "${SCHEMA_DIR}/${TAG}/${SCHEMA_FILENAME}-pretty.json"
done
