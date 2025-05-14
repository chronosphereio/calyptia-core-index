#!/bin/bash
set -eu
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

REPO_ROOT=${REPO_ROOT:-$SCRIPT_DIR/..}
# Set this to the go-fluentbit-config repo root directory
OUTPUT_DIR=${OUTPUT_DIR:?}

mkdir -p "$OUTPUT_DIR"/schemas

# Simple copy of the full set in case we want it in the future
while IFS='' read -r -d '' filename
do
    version=$(basename "$(dirname "$filename")")
    # Copy from 'core-fluent-bit-pretty.json' to 23.4.3.json for example
    cp -fv "$filename" "$OUTPUT_DIR"/schemas/"$version".json
done < <(find "$REPO_ROOT/schemas/" -type f -name 'core-fluent-bit-pretty.json' -print0)

# Now set up latest version
# This lists all the directories inside schemas/ then removes the directory name plus any "v" prefix.
# Then it sorts the versions in reverse order and gets the first one.
latest_version=$(find "$REPO_ROOT/schemas/" -maxdepth 1 -type d | sed -E "s|$REPO_ROOT/schemas/(v)?||g" | sort -rV | head -n 1)
echo "Found latest version: $latest_version"

pushd "$OUTPUT_DIR/schemas/"
    ln -sfv "$latest_version".json latest.txt
popd

# Update the embedded schema in Go code
sed -i -E "s|//go:embed schemas/[0-9]+\.[0-9]+\.[0-9]+\.json|//go:embed schemas/$latest_version.json|g" "$OUTPUT_DIR/schema.go"
