#!/bin/sh -l

ALT_SELECTOR="$5"
TAG="$6"
VERSION="$7"

set -eu

TEMPLATE="$1"
TARGET="$2"
REPOSITORY="$3"
SELECTOR="$4"

# --- Functions
function debug() {
    echo "$@" 1>&2
}

function output() {
    echo ::set-output name=$1::$2
}

function get_release() {
    if [ -z "$TAG" ]; then
        curl --silent \
            -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/repos/${REPOSITORY}/releases/latest"
    else
        curl --silent \
            -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/repos/${REPOSITORY}/releases/tags/${TAG}"
    fi
}

function get_asset_url() {
    local RELEASE="$1"
    local RESULT=""
    shift

    while [ $# -gt 0 -a -z "$RESULT" ]; do
        if [ ! -z "$1" ]; then
            RESULT=$(printf "%s" "$RELEASE" \
                | jq -r '.assets[] | select(.name | contains("'$1'")) | .browser_download_url' \
                | head -n 1)
        fi
        shift
    done

    printf "%s" "$RESULT"
}

function get_release_url() {
    printf "%s" "$1" | jq -r '.html_url'
}

function fetch_and_hash() {
    if [ ! -z "$1" ]; then
        curl --silent -L "$1" | sha256sum | cut -f 1 -d " "
    fi
}

function infer_version() {
    local RELEASE="$1"
    if [ -z "$VERSION" ]; then
        local RELEASE_TAG=$(printf "%s" "$RELEASE" | jq -r '.tag_name')
        printf "%s" "${RELEASE_TAG#"v"}"
    else
        printf "%s" "$VERSION"
    fi
}

# --- Steps
debug "Importing Homebrew Formula ..."

debug "=> Querying release '$REPOSITORY@${TAG:-latest}' ..."
RELEASE=$(get_release)
RELEASE_URL=$(get_release_url "$RELEASE")
ASSET_URL=$(get_asset_url "$RELEASE" "$SELECTOR")
ASSET_URL_ALT=$(get_asset_url "$RELEASE" "$ALT_SELECTOR")
VERSION=$(infer_version "$RELEASE")

debug "=> Generating SHA-256 hash ..."
HASH=$(fetch_and_hash "$ASSET_URL")
HASH_ALT=$(fetch_and_hash "$ASSET_URL_ALT")

debug "=> Verifying formula data ..."
debug "  Version: $VERSION"
debug "  Asset:"
debug "    URL:   $ASSET_URL"
debug "    Hash:  $HASH"
debug "  Alternative Asset:"
debug "    URL:   $ASSET_URL_ALT"
debug "    Hash:  $HASH_ALT"

if [ -z "$VERSION" ]; then debug "Could not infer/read version!"; exit 1; fi
if [ -z "$ASSET_URL" ]; then debug "Could not find main asset!"; exit 1; fi
if [ -z "$HASH" ]; then debug "Could not calculate main asset hash!"; exit 1; fi

debug "=> Fetching and substituting formula template (-> $TARGET) ..."
export HOMEBREW_VERSION="$VERSION"
export HOMEBREW_ASSET_URL="$ASSET_URL"
export HOMEBREW_SHA256="$HASH"
export HOMEBREW_ASSET_URL_ALT="$ASSET_URL_ALT"
export HOMEBREW_SHA256_ALT="$HASH_ALT"
cat "$TEMPLATE" | envsubst > "$TARGET"
cat "$TARGET"

debug "=> Creating outputs ..."
output "target"     "$TARGET"
output "version"    "$VERSION"
output "releaseUrl" "$RELEASE_URL"

exit 0
