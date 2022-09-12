#!/bin/bash
set -u

GITHUB_TOKEN=${GITHUB_TOKEN:?}
CONTAINER_PACKAGE=${CONTAINER_PACKAGE:-calyptia/core}
CONTAINER_INDEX_FILE=${CONTAINER_INDEX_FILE:-container.index.json}

curl -sSfL -H "Authorization: Bearer $GITHUB_TOKEN" https://api.github.com/repos/"${CONTAINER_PACKAGE}"/tags | \
    jq '[.[].name|select(.|test("^v(.*)"))]' | tee "$CONTAINER_INDEX_FILE"
