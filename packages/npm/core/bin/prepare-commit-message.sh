#!/usr/bin/env bash

set -e pipefail

# GUM='docker run  --pull=always -ti --rm pnpmkambrium/gum'
# GUM='docker run  -ti --rm pnpmkambrium/gum'
function gum() {
  docker run -ti --rm pnpmkambrium/gum "$@"
}

# COMMIT_TYPES=("fix" "feat" "docs" "style" "refactor" "test" "chore" "revert")
# set -x
# COMMIT_TYPE=$(docker run  -ti --rm pnpmkambrium/gum choose --header "Select the type of change that you're committing:" "a" "b")

# shopt -s lastpipe
# gum choose --header "Select the type of change that you're committing:" "a" "b" | read COMMIT_TYPE

gum choose --header "Select the type of change that you're committing:" "a" "b"
gum choose --header "next option" "xxx" "yyy"

echo "COMMIT_TYPE=$COMMIT_TYPE"
