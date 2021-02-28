#!/bin/sh -l

TAG="$3"
VERSION="$4"
TEMPLATE_REF="$5"

set -eu

TARGET="$1"
REPOSITORY="$2"

# --- Defaults

# --- Functions
function debug() {
    echo "$@" 1>&2
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
    local MATCH="$2"
    printf "%s" "$RELEASE" \
        | jq -r '.assets[] | select(.name | contains("'$MATCH'")) | .browser_download_url' \
        | head -n 1
}

function get_release_url() {
    printf "%s" "$1" | jq -r '.html_url'
}

function fetch_and_hash() {
    if [ ! -z "$1" ]; then
        curl --silent -L "$1" | sha256sum | cut -f 1 -d " "
    fi
}

function fetch_formula_template() {
    curl --silent -L \
        "https://raw.githubusercontent.com/$REPOSITORY/${TEMPLATE_REF:-master}/.homebrew.rb"
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
ASSET_URL=$(get_asset_url "$RELEASE" "macos-amd64")
LINUX_ASSET_URL=$(get_asset_url "$RELEASE" "linux-amd64")
VERSION=$(infer_version "$RELEASE")

debug "=> Generating SHA-256 hash ..."
HASH=$(fetch_and_hash "$ASSET_URL")
LINUX_HASH=$(fetch_and_hash "$LINUX_ASSET_URL")

debug "=> Fetching and substituting formula template ..."
debug "  Version:           $VERSION"
debug "  Asset (MacOS):"
debug "    URL:  $ASSET_URL"
debug "    Hash: $HASH"
debug "  Asset (Linux):"
debug "    URL:  $LINUX_ASSET_URL"
debug "    Hash: $LINUX_HASH"

export HOMEBREW_VERSION="$VERSION"
export HOMEBREW_ASSET_URL="$ASSET_URL"
export HOMEBREW_SHA256="$HASH"
export HOMEBREW_ASSET_URL_LINUX="$LINUX_ASSET_URL"
export HOMEBREW_SHA256_LINUX="$LINUX_HASH"
fetch_formula_template | envsubst > "$TARGET"

exit 0
