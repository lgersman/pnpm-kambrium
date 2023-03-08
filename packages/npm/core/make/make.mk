# KAMBRIUM_MAKEFILE_DIR points to the directory where this file was loaded from
export KAMBRIUM_MAKEFILE_DIR := $(patsubst %/,%,$(dir $(lastword $(MAKEFILE_LIST))))
include $(KAMBRIUM_MAKEFILE_DIR)/make-common.mk
include $(KAMBRIUM_MAKEFILE_DIR)/make-functions.mk
include $(KAMBRIUM_MAKEFILE_DIR)/make-rules.mk
include $(KAMBRIUM_MAKEFILE_DIR)/make-targets.mk
include $(KAMBRIUM_MAKEFILE_DIR)/make-init.mk
include $(KAMBRIUM_MAKEFILE_DIR)/make-docker.mk
include $(KAMBRIUM_MAKEFILE_DIR)/make-wp-plugin.mk
include $(KAMBRIUM_MAKEFILE_DIR)/make-npm.mk
include $(KAMBRIUM_MAKEFILE_DIR)/make-docs.mk
include $(KAMBRIUM_MAKEFILE_DIR)/make-gh-pages.mk
include $(KAMBRIUM_MAKEFILE_DIR)/make-github.mk

# ensure required utilities are installed
_ := $(call ensure-commands-exists, node sed git touch jq docker tee awk)

# pnpm env use --global $(grep -oP '(?<=use-node-version=).*' ./.npmrc1)
# node version to use by pnpm (defined in .npmrc)
NODE_VERSION != sed -n '/^use-node-version=/ {s///p;q;}' .npmrc

# path to node binary configured in .npmrc
NODE := $(HOME)/.local/share/pnpm/nodejs/$(NODE_VERSION)/bin/node

# pick up npm scope from package.json name
MONOREPO_SCOPE != jq -r '.name | values' package.json

# always run prettier using ignored files from .lintignore 
PRETTIER := $(PNPM) prettier --ignore-path='$(CURDIR)/.lintignore' --cache --check

# always run eslint using ignored files from .lintignore 
ESLINT := $(PNPM) eslint --ignore-path='$(CURDIR)/.lintignore' --no-error-on-unmatched-pattern

# project (path) specific temp directory outside of the checked out repository
KAMBRIUM_TMPDIR := $(shell mktemp -d --suffix ".pnpmkambrium-$$(basename $(CURDIR))")
# delete all KAMBRIUM_TMPDIR's older than one day
$(shell find $(shell dirname $(KAMBRIUM_TMPDIR)) -maxdepth 0 -ctime +1 -name '*.*.pnpmkambrium-$(shell basename $(CURDIR))' -type d -delete)

# please note the variables in the root .env file need to be exported to take effect
# example : "export foo=bar"
-include .env

# this target triggers pnpm to download/install the required nodejs if not yet available 
$(NODE):
# > @$(PNPM) exec node --version 1&>/dev/null
# > touch -m $@

pnpm-lock.yaml: package.json 
>  $(PNPM) install --lockfile-only
> @touch -m pnpm-lock.yaml

node_modules/: pnpm-lock.yaml 
# pnpm bug: "pnpm use env ..." is actually not needed but postinall npx calls fails
> $(PNPM) env use --global $(NODE_VERSION)
>  $(PNPM) install --frozen-lockfile
> @touch -m node_modules

# HELP<<EOF
# lint sources
# EOF
.PHONY: lint
lint: node_modules/
> pnpm run -r --if-present lint
> $(PRETTIER) --ignore-unknown .
> $(ESLINT) .
> ! (command -v $$($(PNPM) bin)/stylelint >/dev/null) || \
>   $(PNPM) stylelint --ignore-path='$(CURDIR)/.lintignore' --allow-empty-input ./packages/**/*.{css,scss}
> {
>   echo "Checking for unwanted tabs in makefiles..."
>   ! git --no-pager grep --no-color --no-exclude-standard --untracked --no-recurse-submodules -n $$'\t' Makefile **/*.mk \
>     | sed -e "s/\t/\x1b\[31m'\\\\t\x1b\[0m/" 
>   echo "[done]"
> }

# HELP<<EOF
# lint the project and apply fixes provided by the linters
# EOF
.PHONY: lint-fix
lint-fix: node_modules/
> pnpm run -r --if-present lint-fix
> $(PRETTIER) --cache --check --write .
> $(ESLINT) --fix .
> ! (command -v $$($(PNPM) bin)/stylelint >/dev/null) || \
>   $(PNPM) stylelint --ignore-path='$(CURDIR)/.lintignore' --allow-empty-input --fix ./packages/**/*.{css,scss}
> # lint-fix make files (poor mans edition): replace tabs with 2 spaces
>  (git --no-pager grep --no-color --no-exclude-standard --untracked --no-recurse-submodules -nH --name-only $$'\t' Makefile **/*.mk \
>   | xargs -I '{}' -r bash -c \
>   ' \
>     sed -i -e "s/\t/  /g" {}; \
>     printf "[done] fixed makefile(=%s) : replaced tabs with 2 spaces\n" {} \
>  ')||:


# HELP<<EOF
# delete resources matching `.gitignore` entries except 
# 
#    - `./.node_modules`
#    - any `.env` file (recursive)
#    - `./.pnpm-store`
#    - `./*.code-workspace`
# EOF
.PHONY: clean
clean:
# remove everything matching .gitignore entries (-f is force, you can add -q to suppress command output, exclude node_modules and node_modules/**)
#   => If an untracked directory is managed by a different git repository, it is not removed by default. Use -f option twice if you really want to remove such a directory.
> git clean -Xfd -e '!.secrets' -e '!.env' -e '!/*.code-workspace' -e '!**/node_modules' -e '!**/node_modules/**' -e '!**/.pnpm-store' -e '!**/pnpm-store/**' 
# remove temporary files outside repo
> rm -rf -- $$(dirname $(KAMBRIUM_TMPDIR))/*.pnpmkambrium-$$(basename $(CURDIR))

# HELP<<EOF
# delete any file that are a result of making the project and not matched by `.gitignore` except :
#    - any `.env` file (recursive)
#    - `./*.code-workspace`
#
# ATTENTION: You have to call 'make node_modules/' afterwards to make your environment again work properly
# EOF
# see https://www.gnu.org/software/make/manual/html_node/Standard-Targets.html 
.PHONY: distclean
distclean: clean
> git clean -Xfd -e '!.secrets' -e '!/*.env' -e '!/*.code-workspace'
> rm -f pnpm-lock.yaml
# remove built docker images
> docker image rm -f $$(docker images -q $(MONOREPO_SCOPE)/*) 2>/dev/null ||:
# clean up unused containers. Container, networks, images, and the build cache
# > docker system prune -a
# remove unused volumes
# > docker volumes prune

# HELP<<EOF
#  prints the help screen
#
# by default the help will be rendered for the terminal using a few ansi escape sequences for highlighting
#
# to process the help information in other tools you can use the `FORMAT` variable to output help in JSON format.
#
# supported variables are : 
#   - `VERBOSE` (optional, default=``) enables verbose help parsing informations 
#   - `FORMAT` (optional, default=`text`) the output format of the help information
#      - `text` will print help in text format to terminal
#        - addional option `PAGER=false` may be used to output help without pagination
#     - `json` will print help in json format for further processing
#      - `markdown` will print help in markdown format for integrating output in static documentation
#
# environment variables can be provided using:
#   - make variables provided at commandline
#   - `.env` file from sub package
#   - `.env` file from monorepo root
#   - environment
# EOF
.PHONY: help 
help:
> @
> # import kambrium bash function library
> . "$(KAMBRIUM_MAKEFILE_DIR)/make-bash-functions.sh"
> help=$$( VERBOSE=$${VERBOSE:-}; FORMAT=$${FORMAT:-}; kambrium:help < <(cat $(MAKEFILE_LIST)) )
> if [[ "$${FORMAT:-}" == '' ]]; then
>   if [[ "$${PAGER:-}" != 'false' ]]; then
>     echo -e "$$help" | less -r
>   else 
>     echo -e "$$help" 
>   fi
> elif [[ "$${FORMAT:-}" == 'json' ]]; then 
>   echo $$help | jq .
> elif [[ "$${FORMAT:-}" == 'markdown' ]]; then
>   echo "$$help"
> else 
>    echo "unknown FORMAT option(='$$FORMAT')" >&2 && false
> fi

# HELP<<EOF
# opens a interactive help menu utilizing fzf (https://github.com/junegunn/fzf)
#
# environment variables can be provided using:
#   - make variables provided at commandline
#   - `.env` file from sub package
#   - `.env` file from monorepo root
#   - environment
# EOF
.PHONY: interactive
interactive:
> @ 
> # import kambrium bash function library
> . "$(KAMBRIUM_MAKEFILE_DIR)/make-bash-functions.sh"
> help=$$( VERBOSE=$${VERBOSE:-}; FORMAT=$${FORMAT:-json}; kambrium:help < <(cat $(MAKEFILE_LIST)) )
> HELP_FILE="$$(mktemp)"
> echo "$$help" > $$HELP_FILE
> # execute shaunch if exists locally. otherwise fallback to prepackaged shaunch docker image 
> if command -v ./packages/docker/shaunch/bin/shaunch.sh >/dev/null; then  
>   ./packages/docker/shaunch/bin/shaunch.sh --border-label " Make " --preview-label " Info " --title "Targets" -c "$$HELP_FILE" ||:
> else
>   docker run -it --rm -v $$(dirname $$HELP_FILE):/app pnpmkambrium/shaunch --border-label " Make " --preview-label " Info " --title "Targets" -c "/app/$$(basename $$HELP_FILE)" ||:
> fi
> trap "rm -f -- $$HELP_FILE" EXIT

KAMBRIUM_TRACE ?= false
# print out targets and dependencies before executing if environment variable KAMBRIUM_TRACE is set to true
ifeq ($(KAMBRIUM_TRACE),true)
  # see https://www.cmcrossroads.com/article/tracing-rule-execution-gnu-make
  OLD_SHELL := $(SHELL)
  SHELL = $(warning $(TERMINAL_YELLOW)Building $@$(if $<, (from $<))$(if $?, ($? newer))$(TERMINAL_RESET))$(OLD_SHELL)
endif
