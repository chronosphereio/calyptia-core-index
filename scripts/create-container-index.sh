#!/bin/bash
set -u

GITHUB_TOKEN=${GITHUB_TOKEN:?}
CONTAINER_PACKAGE=${CONTAINER_PACKAGE:-calyptia/core}
CONTAINER_INDEX_FILE=${CONTAINER_INDEX_FILE:-container.index.json}

GHCR_TOKEN=$(echo "$GITHUB_TOKEN" | base64)

curl --silent -H "Authorization: Bearer $GHCR_TOKEN" https://ghcr.io/v2/"${CONTAINER_PACKAGE}"/tags/list?n=100000 | \
    jq -r '.tags | map(select(.| test("^v(.*)")))' | tee "$CONTAINER_INDEX_FILE"