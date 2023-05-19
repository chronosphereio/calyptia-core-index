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
    jq -r '.tags | map(select(.| test("^([0-9]+\\.|v)(.*)")))|flatten[]') 
# Test for tags beginning with v* or XX.*: https://github.com/stedolan/jq/issues/1250#issuecomment-252396642

for TAG in $TAGS; do
    mkdir -p "${SCHEMA_DIR}/${TAG}"
    # Get Fluent Bit schema
    "$CONTAINER_RUNTIME" run --pull=always --rm -t "ghcr.io/${CONTAINER_PACKAGE}:${TAG}" -J > "${SCHEMA_DIR}/${TAG}/${SCHEMA_FILENAME}.json"
    jq -M . "${SCHEMA_DIR}/${TAG}/${SCHEMA_FILENAME}.json" > "${SCHEMA_DIR}/${TAG}/${SCHEMA_FILENAME}-pretty.json"

    # Get LUA modules schema - has to be copied out
    "$CONTAINER_RUNTIME" rm --force "test" &> /dev/null
    "$CONTAINER_RUNTIME" create --name=test "ghcr.io/${CONTAINER_PACKAGE}:${TAG}"
    if ! "$CONTAINER_RUNTIME" cp "test:/schema.json" "${SCHEMA_DIR}/${TAG}/${SCHEMA_FILENAME}-lua.json" ; then
        echo "WARNING: Unable to find LUA schema for ghcr.io/${CONTAINER_PACKAGE}:${TAG}"
    else
        jq -M . "${SCHEMA_DIR}/${TAG}/${SCHEMA_FILENAME}-lua.json" > "${SCHEMA_DIR}/${TAG}/${SCHEMA_FILENAME}-lua-pretty.json"
    fi

    # Get Enterprise plugins schema
    if ! "$CONTAINER_RUNTIME" cp "test:/opt/calyptia-fluent-bit/etc/plugins.json" "${SCHEMA_DIR}/${TAG}/${SCHEMA_FILENAME}-plugins.json" ; then
        echo "WARNING: Unable to find plugins schema for ghcr.io/${CONTAINER_PACKAGE}:${TAG}"
    else
        jq -M . "${SCHEMA_DIR}/${TAG}/${SCHEMA_FILENAME}-plugins.json" > "${SCHEMA_DIR}/${TAG}/${SCHEMA_FILENAME}-plugins-pretty.json"
    fi

    "$CONTAINER_RUNTIME" rm --force "test" &> /dev/null
done
