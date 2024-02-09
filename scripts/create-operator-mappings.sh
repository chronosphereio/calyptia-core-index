#!/bin/bash
set -u
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# Used to authenticate with gh api CLI
export GH_TOKEN=${GITHUB_TOKEN:?}
OPERATOR_REPO=${OPERATOR_REPO:-chronosphereio/calyptia-core-operator-releases}
SCHEMA_FILENAME=${SCHEMA_FILENAME:-$SCRIPT_DIR/../operator/core-fluent-bit-default-versions.json}

TAGS=$(gh api \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  /repos/"${OPERATOR_REPO}"/releases --jq '.[].tag_name')

rm -fv "$SCHEMA_FILENAME"
echo '{' > "$SCHEMA_FILENAME"

for TAG in $TAGS; do
  echo "Operator release: $TAG"
    # mkdir -p "${SCHEMA_DIR}/${TAG}"
    # Grab the manifest for each release
  MANIFEST_URL=$(gh api \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    /repos/"${OPERATOR_REPO}"/releases/tags/"${TAG}" --jq '.assets[]|select(.name == "manifest.yaml")|.browser_download_url')
  echo "manifest.yaml: $MANIFEST_URL"

  # Select the CRD for pipelines then extract the image field from that
  CORE_FLUENT_BIT_VERSION=$(curl -sSfL "$MANIFEST_URL" | yq 'select(.kind == "CustomResourceDefinition")| select(.metadata.name == "pipelines.core.calyptia.com")|.spec.versions[0].schema.openAPIV3Schema.properties.spec.properties.image.default')

  echo "$TAG : $CORE_FLUENT_BIT_VERSION"
  echo "\"$TAG\": \"$CORE_FLUENT_BIT_VERSION\"," >> "$SCHEMA_FILENAME"
done

# Add latest at end to close off the object fields - no need to cope with commas not at end of last entry then
MANIFEST_URL=$(gh api \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  /repos/"${OPERATOR_REPO}"/releases/latest --jq '.assets[]|select(.name == "manifest.yaml")|.browser_download_url')
echo "manifest.yaml: $MANIFEST_URL"

CORE_FLUENT_BIT_VERSION=$(curl -sSfL "$MANIFEST_URL" | yq 'select(.kind == "CustomResourceDefinition")| select(.metadata.name == "pipelines.core.calyptia.com")|.spec.versions[0].schema.openAPIV3Schema.properties.spec.properties.image.default')
echo "\"latest\": \"$CORE_FLUENT_BIT_VERSION\"" >> "$SCHEMA_FILENAME"

echo '}' >> "$SCHEMA_FILENAME"
