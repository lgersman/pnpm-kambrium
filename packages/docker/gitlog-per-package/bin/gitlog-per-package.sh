#!/usr/bin/env bash

# Desc: Lists the git commits by monorepo package
#
# Usage: execute git-log-by-monorepo-package.sh in the root of a monorepo
#
# script supports git log command customization using environment variable GIT_LOG_OPTIONS.
# Example:
# GIT_LOG_OPTIONS="--stat --abbrev-commit" ./packages/docker/gitlog-per-package/bin/gitlog-per-package.sh
#
# Requires: git, pnpm, wget, fzf >= 0.29.0 (will be installed if not present)
#
# Author: Lars Gersmann<lars.gersmann@gmail.com.com>
# Created: 2022-11-16
# License: See repository LICENSE file.

set -Eeuo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

GIT_ROOT_DIR=$(git rev-parse --show-toplevel)

_package2path() {
  local package="$1"
  local path="$(realpath --relative-to=$GIT_ROOT_DIR $(pnpm --filter=$package exec pwd))"

  echo $path
}

GIT_LOG_OPTIONS=${GIT_LOG_OPTIONS:-""}

_command_info() {
  local package="$1"
  local filter=${2:-''}
  local path="$(_package2path "$package")"

  git --no-pager log --color $GIT_LOG_OPTIONS --grep "$filter" -- $path
}

parse_params() {
  # default values of variables set from params
  flag=0
  param=''

  while :; do
    case "${1-}" in
    _command_info)
      shift
      _command_info "$@"
      exit
    ;;
    -?*) die "Unknown option: $1" ;;
    *) break ;;
    esac
    shift
  done

  args=("$@")

  # check required params and arguments
  #[[ -z "${param-}" ]] && die "Missing required parameter: param"
  #[[ ${#args[@]} -eq 0 ]] && die "Missing script arguments"
}
#echo "'${BASH_SOURCE[0]}' $@" > foo.txt

parse_params "$@"

if ! (command -v "$script_dir/fzf" 1 > /dev/null); then
  (cd "$script_dir/.." && wget -qO- https://raw.githubusercontent.com/junegunn/fzf/master/install | $SHELL -s -- --bin)
fi

PREVIEW_CMD="'${BASH_SOURCE[0]}' _command_info '{}' '{q}'"
package=$("$script_dir/fzf" \
  --no-mouse \
  --reverse \
  --no-sort \
  --select-1 \
  --disabled \
  --no-multi \
  --border=rounded \
  --no-info \
  --exit-0 \
  --prompt='search: ' \
  --header-lines=3 \
  --ansi \
  --preview-window=80% \
  --preview="$PREVIEW_CMD" \
  < <(echo "
monorepo package

$(pnpm list --recursive --filter='*/*' --json | jq -r  '.[].name | select( . != null )')")
)

echo "git --no-pager log --color $GIT_LOG_OPTIONS -- $(_package2path $package)"
