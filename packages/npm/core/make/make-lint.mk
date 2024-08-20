# lint related targets

LINT_IGNORE_PATH := $(shell test -f $(CURDIR)/.lintignore && echo "$(CURDIR)/.lintignore" || echo "$(CURDIR)/node_modules/@pnpmkambrium/core/presets/default/.lintignore")
PRETTIER := $(PNPM) prettier --config "$(shell test -f $(CURDIR)/.prettierrc.js && echo "$(CURDIR)/.prettierrc.js" || echo '$(CURDIR)/node_modules/@pnpmkambrium/core/presets/default/.prettierrc.js')" --ignore-path $(LINT_IGNORE_PATH) --cache --check --log-level silent
ESLINT := ESLINT_USE_FLAT_CONFIG=false $(PNPM) eslint --quiet --config "$(shell test -f $(CURDIR)/.eslintrc.yaml && echo "$(CURDIR)/.eslintrc.yaml" || echo '$(CURDIR)/node_modules/@pnpmkambrium/core/presets/default/.eslintrc.yaml')" --ignore-path $(LINT_IGNORE_PATH) --no-error-on-unmatched-pattern
STYLELINT := $(PNPM) exec stylelint --quiet --config "$(shell test -f $(CURDIR)/.stylelintrc.yml && echo "$(CURDIR)/.stylelintrc.yml" || echo '$(CURDIR)/node_modules/@pnpmkambrium/core/presets/default/.stylelintrc.yml')" --ignore-path=$(LINT_IGNORE_PATH) --allow-empty-input

# HELP<<EOF
# lint sources
# EOF
.PHONY: lint
lint: node_modules/
> pnpm run -r --if-present lint
> # prettier will exit with 1 if there are any fixable errors
> $(PRETTIER) --ignore-unknown . ||:
> $(ESLINT) .
> test command -v $$($(PNPM) bin)/stylelint &>/dev/null && $(STYLELINT) ./packages/**/*.{css,scss}
> {
>   echo "Checking for unwanted tabs in makefiles..."
>   ! git --no-pager grep --no-color --no-exclude-standard --untracked --no-recurse-submodules -n $$'\t' Makefile **/*.mk \
>     | sed -e "s/\t/\x1b\[31m'\\\\t\x1b\[0m/"
>   kambrium.log_done
> }

# HELP<<EOF
# lint the project and apply fixes provided by the linters
# EOF
.PHONY: lint-fix
lint-fix: node_modules/
> pnpm run -r --if-present lint-fix
> # prettier will exit with 1 if there are any fixable errors
> $(PRETTIER) --write . ||:
> $(ESLINT) --fix .
> test command -v $$($(PNPM) bin)/stylelint &>/dev/null && $(STYLELINT) --fix ./packages/**/*.{css,scss}
> # lint-fix make files (poor mans edition): replace tabs with 2 spaces
> (git --no-pager grep --no-color --no-exclude-standard --untracked --no-recurse-submodules -nH --name-only $$'\t' Makefile **/*.mk \
>   | xargs -I '{}' -r bash -c \
>   ' \
>     sed -i -e "s/\t/  /g" {}; \
>     printf "fixed makefile(=%s) : replaced tabs with 2 spaces\n" {} \
> ') ||:
> kambrium.log_done
