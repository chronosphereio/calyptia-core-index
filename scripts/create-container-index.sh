#!/bin/bash
set -u
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

GITHUB_TOKEN=${GITHUB_TOKEN:?}
OPERATOR_PACKAGE=${OPERATOR_PACKAGE:-calyptia/core-operator}
OPERATOR_INDEX_FILE=${OPERATOR_INDEX_FILE:-$SCRIPT_DIR/../operator.index.json}

GHCR_TOKEN=$(echo "$GITHUB_TOKEN" | base64)

curl --silent -H "Authorization: Bearer $GHCR_TOKEN" https://ghcr.io/v2/"${OPERATOR_PACKAGE}"/tags/list?n=100000 | \
    jq -r '.tags | map(select(.| test("^v(\\d*\\.\\d*\\.\\d*)$")))' | tee "$OPERATOR_INDEX_FILE"
