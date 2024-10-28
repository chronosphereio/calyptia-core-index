#!/bin/bash
set -u
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# Used to authenticate with gh api CLI
export GH_TOKEN=${GITHUB_TOKEN:?}
OPERATOR_REPO=${OPERATOR_REPO:-chronosphereio/calyptia-core-operator-releases}
BACKEND_REPO=${BACKEND_REPO:-chronosphereio/calyptia-backend}
SCHEMA_FILENAME=${SCHEMA_FILENAME:-$SCRIPT_DIR/../operator/core-fluent-bit-default-versions.json}

TAGS=$(gh api \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  /repos/"${OPERATOR_REPO}"/releases --jq '.[].tag_name')

rm -fv "$SCHEMA_FILENAME"
echo '{' > "$SCHEMA_FILENAME"

for TAG in $TAGS; do
  echo "Operator release: $TAG"

  CORE_FLUENT_BIT_VERSION=""
    # mkdir -p "${SCHEMA_DIR}/${TAG}"
    # Grab the manifest for each release
  MANIFEST_URL=$(gh api \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    /repos/"${OPERATOR_REPO}"/releases/tags/"${TAG}" --jq '.assets[]|select(.name == "manifest.yaml")|.browser_download_url')
  if [[ -z "$MANIFEST_URL" ]]; then
    echo No manifest found so attempting to retrieve value from release info
    CORE_FB_IMAGE=$(gh release view "$TAG" --repo "$BACKEND_REPO" | grep 'ghcr.io/calyptia/core/calyptia-fluent-bit')
    CORE_FLUENT_BIT_VERSION="ghcr.io/calyptia/core/calyptia-fluent-bit:${CORE_FB_IMAGE##*ghcr.io/calyptia/core/calyptia-fluent-bit:}"
  else
    echo "manifest.yaml: $MANIFEST_URL"

    # Select the CRD for pipelines then extract the image field from that
    CORE_FLUENT_BIT_VERSION=$(curl -sSfL "$MANIFEST_URL" | yq 'select(.kind == "CustomResourceDefinition")| select(.metadata.name == "pipelines.core.calyptia.com")|.spec.versions[0].schema.openAPIV3Schema.properties.spec.properties.image.default')
  fi
  if [[ -n "$CORE_FLUENT_BIT_VERSION" ]]; then
    echo "$TAG : $CORE_FLUENT_BIT_VERSION"
    echo "\"$TAG\": \"$CORE_FLUENT_BIT_VERSION\"," >> "$SCHEMA_FILENAME"
  else
    echo "ERROR: unable to retrieve Core FB version for $TAG"
    exit 1
  fi
done

MANIFEST_URL=$(gh api \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  /repos/"${OPERATOR_REPO}"/releases/latest --jq '.assets[]|select(.name == "manifest.yaml")|.browser_download_url')

CORE_FLUENT_BIT_VERSION=""
if [[ -z "$MANIFEST_URL" ]]; then
  echo No manifest found so attempting to retrieve value from release info
  CORE_FB_IMAGE=$(gh release view "$(gh release list --json name,isLatest --jq '.[] | select(.isLatest)|.name' --repo "$OPERATOR_REPO")" --repo "$BACKEND_REPO" | grep 'ghcr.io/calyptia/core/calyptia-fluent-bit')
  CORE_FLUENT_BIT_VERSION="ghcr.io/calyptia/core/calyptia-fluent-bit:${CORE_FB_IMAGE##*ghcr.io/calyptia/core/calyptia-fluent-bit:}"
else
  echo "manifest.yaml: $MANIFEST_URL"

  # Select the CRD for pipelines then extract the image field from that
  CORE_FLUENT_BIT_VERSION=$(curl -sSfL "$MANIFEST_URL" | yq 'select(.kind == "CustomResourceDefinition")| select(.metadata.name == "pipelines.core.calyptia.com")|.spec.versions[0].schema.openAPIV3Schema.properties.spec.properties.image.default')
fi
if [[ -n "$CORE_FLUENT_BIT_VERSION" ]]; then
  echo "$TAG : $CORE_FLUENT_BIT_VERSION"
  echo "\"latest\": \"$CORE_FLUENT_BIT_VERSION\"" >> "$SCHEMA_FILENAME"
else
  echo "ERROR: unable to retrieve Core FB version for $TAG"
  exit 1
fi

echo '}' >> "$SCHEMA_FILENAME"
