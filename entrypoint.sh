#!/bin/sh -l

ALT_SELECTOR="$4"
TAG="$5"
VERSION="$6"
TEMPLATE_PATH="$7"
TEMPLATE_REF="$8"

set -eu

TARGET="$1"
REPOSITORY="$2"
SELECTOR="$3"

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

function fetch_formula_template() {
    curl --silent -L \
        "https://raw.githubusercontent.com/$REPOSITORY/${TEMPLATE_REF:-master}/${TEMPLATE_PATH:-.homebrew.rb}"
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

debug "=> Fetching and substituting formula template ..."
export HOMEBREW_VERSION="$VERSION"
export HOMEBREW_ASSET_URL="$ASSET_URL"
export HOMEBREW_SHA256="$HASH"
export HOMEBREW_ASSET_URL_ALT="$ASSET_URL_ALT"
export HOMEBREW_SHA256_ALT="$HASH_ALT"
fetch_formula_template | envsubst > "$TARGET"

exit 0
