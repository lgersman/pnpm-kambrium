# contains generic wordpress plugin  related make settings and rules

KAMBRIUM_SHELL_ALWAYS_PRELOAD += $(KAMBRIUM_MAKEFILE_DIR)/make-wp-plugin.sh

# dynamic variable containing all js source files to transpile (wp-plugin/*/src/*.mjs files)
KAMBRIUM_WP_PLUGIN_JS_SOURCES = $$(wildcard $$(@D)/src/*.mjs)
# dynamic variable containing all transpiled js files (wp-plugin/*/build/*.js files)
KAMBRIUM_WP_PLUGIN_JS_TARGETS = $$(shell echo '$(KAMBRIUM_WP_PLUGIN_JS_SOURCES)' | sed -e 's/src/build/g' -e 's/.mjs/.js/g' )

# docker image containing our bundler imge name
KAMBRIUM_WP_PLUGIN_DOCKER_IMAGE_JS_BUNDLER := lgersman/cm4all-wp-bundle:latest

# HELP<<EOF
# build and tag all outdated wordpress plugins in `packages/wp-plugin/`
#
# EOF
packages/wp-plugin/: $(KAMBRIUM_SUB_PACKAGE_FLAVOR_DEPS) ;

# HELP<<EOF
# build and zip outdated wordpress plugin package by name.
#
# plugin metadata like author/description/version will be taken from sub package file `package.json`
#
# example: `make packages/wp-plugin/foo/`
#
#   will build the wordpress plugin sub package `packages/wp-plugin/foo`
# EOF
packages/wp-plugin/%/: $(KAMBRIUM_SUB_PACKAGE_DEPS) ;

# build and zip wordpress plugin
#
# we utilize file "build-info" to track if the wordpress plugin was build/is up to date
packages/wp-plugin/%/build-info: $$(filter-out $$(wildcard $$(@D)/languages/*.po $$(@D)/languages/*.mo $$(@D)/languages/*.json), $(KAMBRIUM_SUB_PACKAGE_BUILD_INFO_DEPS))
> # inject sub package environments from {.env,.secrets} files
> kambrium.load_env $(@D)
> PACKAGE_JSON=$(@D)/package.json
> PACKAGE_VERSION=$$(jq -r '.version | values' $$PACKAGE_JSON)
> rm -rf $(@D)/{dist,build,build-info}
> $(PNPM) -r --filter "$$(jq -r '.name | values' $$PACKAGE_JSON)" --if-present run pre-build
> if jq --exit-status '.scripts | has("build")' $$PACKAGE_JSON >/dev/null; then
>   $(PNPM)-r --filter "$$(jq -r '.name | values' $$PACKAGE_JSON)" run build
> else
>   mkdir -p $(@D)/build/
>
>   # transpile src/{*.js,*.css} files
>   if [[ -d $(@D)/src ]]; then
>     $(MAKE) $$(find $(@D)/src -maxdepth 1 -type f -name '*.mjs' | sed -e 's/src/build/g' -e 's/.mjs/.js/g')
>     [[ -f $(@D)/src/block.json ]] && $(MAKE) $(@D)/build/block.json
>   else
>     kambrium.log_skipped "js/css transpilation skipped - no ./src directory found"
>   fi
>
>   # compile pot -> po -> mo files
>   if [[ -d $(@D)/languages ]]; then
>     $(MAKE) \
        packages/wp-plugin/$*/languages/$*.pot \
        $(patsubst %.po,%.mo,$(wildcard packages/wp-plugin/$*/languages/*.po))
>   else
>     kambrium.log_skipped "i18n transpilation skipped - no ./languages directory found"
>   fi
> fi
>
> $(PNPM) -r --filter "$$(jq -r '.name | values' $$PACKAGE_JSON)" --if-present run post-build
>
> # update plugin.php metadata
>
> # copy plugin code to dist/[plugin-name]
> mkdir -p $(@D)/dist/$*
> rsync -rupE \
    --exclude=node_modules/ \
    --exclude=package.json \
    --exclude=dist/ \
    --exclude=build/ \
    --exclude=tests/ \
    --exclude=src/ \
    --exclude=composer.* \
    --exclude=vendor/ \
    --exclude=*.kambrium-template \
    --exclude=cm4all-wp-bundle.json \
    $(@D)/ $(@D)/dist/$*
>
# > [[ -d '$(@D)/build' ]] || (echo "don't unable to archive build directory(='$(@D)/build') : directory does not exist" >&2 && false)
# > find $(@D)/dist/$* -executable -name "*.kambrium-template" | xargs -L1 -I{} make $$(basename "{}")
# > find $(@D)/dist/$* -name "*.kambrium-template" -exec rm -v -- {} +
>
> # build js/css in src/ (take package.json src/entry info into account)
> # - generate/update i18n resources pot/mo/po
> # - update plugin.php readme.txt or use readme.txt.template => readme.txt mechnic
> # - resize/generate wordpress.org plugin images
> # - update plugin.php metadata
> # - transpile build/php sources down to 7.4. if needed (lookup required php version from plugin.php)
> # how do we store the original plugin.zip and the transpiled plugin within build/ folder ?
> [[ -d '$(@D)/build' ]] || (echo "don't unable to archive build directory(='$(@D)/build') : directory does not exist" >&2 && false)
> find $(@D)/build -name "*.kambrium-template" -exec rm -v -- {} \;
# > # redirecting into the target zip archive frees us from removing an existing archive first
# > (cd $(@D)/build && zip -9 -r -q - ./* >../dist/$*-$$PACKAGE_VERSION.zip)
# > cat << EOF | tee $@
# > $$(cd $(@D)/dist && ls -1shS *.zip )
# >
# > $$(echo -n "---")
# >
# > $$(unzip -l $(@D)/dist/*.zip)
# > EOF
> touch $@

# HELP<<EOF
# create or update the pot file in a wordpress sub package (`packages/wp-plugin/*`)
#
# example: `make packages/wp-plugin/foo/languages/`
#
#   will create (if not exist) or update (if any of the plugin source files changed) the pot file `packages/wp-plugin/foo/languages/foo.pot`
# EOF
packages/wp-plugin/%/languages/ : packages/wp-plugin/$$*/languages/$$*.pot;

# update plugin.php metadata if any of its metadata sources changed
packages/wp-plugin/%/plugin.php : packages/wp-plugin/%/package.json package.json $$(wildcard .env packages/wp-plugin/$$*/.env)
> # inject sub package environments from {.env,.secrets} files
> kambrium.load_env $(@D)
> PACKAGE_JSON=$(@D)/package.json
> PACKAGE_VERSION=$$(jq -r '.version | values' $$PACKAGE_JSON)
> PACKAGE_AUTHOR="$$(kambrium.author_name $$PACKAGE_JSON) <$$(kambrium.author_email $$PACKAGE_JSON)>"
> PACKAGE_NAME=$$(jq -r '.name | values' $$PACKAGE_JSON | sed -r 's/@//g')
> # update plugin name
> sed -i "s/^ \* Plugin Name: .*/ \* Plugin Name: $*/" $@
> # update plugin uri
> HOMEPAGE=$${HOMEPAGE:-$$(jq -r -e '.homepage | values' $$PACKAGE_JSON || jq -r '.homepage | values' package.json)}
> # we need to escape slashes in the injected variables to not confuse sed (=> $${VAR//\//\\/})
> sed -i "s/^ \* Plugin URI: .*/ \* Plugin URI: $${HOMEPAGE//\//\\/}/" $@
> # update description
> DESCRIPTION=$${DESCRIPTION:-$$(jq -r -e '.description | values' $$PACKAGE_JSON || jq -r '.description | values' package.json)}
> sed -i "s/^ \* Description: .*/ \* Description: $${DESCRIPTION//\//\\/}/" $@
> # update version
> sed -i "s/^ \* Version: .*/ \* Version: $$PACKAGE_VERSION/" $@
> # update tags
> TAGS=$${TAGS:-$$(jq -r -e '.keywords | values | join(", ")' $$PACKAGE_JSON || jq -r '.keywords | values | join(", ")' package.json)}
> sed -i "s/^ \* Tags: .*/ \* Tags: $${TAGS//\//\\/}/" $@
> # update required php version
> PHP_VERSION=$${PHP_VERSION:-$$(jq -r -e '.config.php_version | values' $$PACKAGE_JSON || jq -r '.config.php_version | values' package.json)}
> sed -i "s/^ \* Requires PHP: .*/ \* Requires PHP: $$PHP_VERSION/" $@
> # update requires at least wordpress version if provided
> # @TODO: a plugin can be directly started using wp-env (https://developer.wordpress.org/block-editor/reference-guides/packages/packages-env/#starting-the-environment)
> WORDPRESS_VERSION=$${WORDPRESS_VERSION:-$$(jq -r -e '.config.wordpress_version | values' $$PACKAGE_JSON || jq -r '.config.wordpress_version | values' package.json)}
> [[ "$$WORDPRESS_VERSION" != "" ]] && sed -i "s/^ \* Requires at least: .*/ \* Requires at least: $$WORDPRESS_VERSION/" $@
> # update author
> AUTHORS="$${AUTHORS:-[]}"
> [[ "$$AUTHORS" == '[]' ]] && AUTHORS=$$(jq '[.contributors[]? | .name]' $$PACKAGE_JSON)
> [[ "$$AUTHORS" == '[]' ]] && AUTHORS=$$(jq '[.author.name | select(.|.!=null)]' $$PACKAGE_JSON)
> [[ "$$AUTHORS" == '[]' ]] && AUTHORS=$$(jq '[.contributors[]? | .name]' package.json)
> [[ "$$AUTHORS" == '[]' ]] && AUTHORS=$$(jq '[.author.name | select(.|.!=null)]' package.json)
> # if AUTHORS looks like a json array ([.*]) transform it into a comma separated list
> if [[ "$$AUTHORS" =~ ^\[.*\]$$ ]]; then
>   AUTHORS=$$(echo "$$AUTHORS" | jq -r '. | values | join(", ")')
> fi
> [[ "$$AUTHORS" != "" ]] && sed -i "s/^ \* Author: .*/ \* Author: $${AUTHORS//\//\\/}/" $@
> # update author uri
> VENDOR=$${VENDOR:-}
> [[ "$$VENDOR" != "" ]] && sed -i "s/^ \* Author URI: .*/ \* Author URI: $${VENDOR//\//\\/}/" $@
> # update license
> LICENSE=$$(\
    jq -r -e 'if (.license | type) == "string" then .license else .license.type end | values' $$PACKAGE_JSON || \
    jq -r -e 'if (.license | type) == "string" then .license else .license.type end | values' package.json || \
    true \
  )
> [[ "$$LICENSE" != "" ]] && sed -i "s/^ \* License: .*/ \* License: $$LICENSE/" $@
> # update license uri
> LICENSE_URI=$$(\
    jq -r -e '.license.uri | values' $$PACKAGE_JSON 2>/dev/null || \
    jq -r -e '.license.uri | values' package.json 2>/dev/null || \
    [[ "$$LICENSE" != "" ]] && echo "https://opensource.org/licenses/$$LICENSE" || \
    true \
  )
> [[ "$$LICENSE_URI" != "" ]] && sed -i "s/^ \* License URI: .*/ \* License URI: $${LICENSE_URI//\//\\/}/" $@
> kambrium.log_done "$(@D) : updated wordpress header in plugin.php"

# dynamic definition of dockerized wp-cli
KAMBRIUM_WP_PLUGIN_WPCLI = docker run $(DOCKER_FLAGS) \
  --user '$(shell id -u $(USER)):$(shell id -g $(USER))' \
  -v `pwd`/`dirname $(@D)`:/var/www/html \
  wordpress:cli-php8.2 \
  wp

# tell make that pot file should be kept
.PRECIOUS: packages/wp-plugin/%.pot
# create or update a i18n plugin pot file
packages/wp-plugin/%.pot : $$(shell kambrium.get_pot_dependencies $$@)
> set -x
> $(KAMBRIUM_WP_PLUGIN_WPCLI) i18n make-pot --ignore-domain --exclude=tests/,dist/,package.json,*.readme.txt.template ./ languages/$(@F)

# HELP<<EOF
# create or update a i18n po file in a wordpress sub package (`packages/wp-plugin/*`)
#
# example: `make packages/wp-plugin/foo/languages/foo-pl_PL.po`
#
#   will create (if not exist) or update (if any of the plugin source files changed) the po file `packages/wp-plugin/foo/languages/foo-pl_PL.po`
# EOF
# tell make that pot file should be kept
.PRECIOUS: packages/wp-plugin/%.po
packages/wp-plugin/%.po : $$(shell kambrium.get_pot_path $$(@))
> if [[ -f "$@" ]]; then
>   # update po file
>   $(KAMBRIUM_WP_PLUGIN_WPCLI) i18n update-po languages/$$(basename $^) languages/$(@F)
> else
>   LOCALE=$$([[ "$@" =~ ([a-z]+_[A-Z]+)\.po$$ ]] && echo $${BASH_REMATCH[1]})
>   msginit -i $< -l $$LOCALE --no-translator -o $@
> fi

packages/wp-plugin/%/build/block.json: packages/wp-plugin/%/src/block.json
> cp $< $@

# HELP<<EOF
# create or update a i18n mo file in a wordpress sub package (`packages/wp-plugin/*`)
#
# example: `make packages/wp-plugin/foo/languages/foo-pl_PL.mo`
#
#   will create (if not exist) or update (if any of the plugin source files changed) the mo file `packages/wp-plugin/foo/languages/foo-pl_PL.mo`
# EOF
packages/wp-plugin/%.mo: packages/wp-plugin/%.po
> $(KAMBRIUM_WP_PLUGIN_WPCLI) i18n make-mo languages/$(<F)
> # if a src directory exists we assume that the i18n json files should also be created
> if [[ -d $$(dirname $(@D))/src ]]; then
>   $(KAMBRIUM_WP_PLUGIN_WPCLI) i18n make-json languages/$(<F) --no-purge --pretty-print
> fi

# tell make that transpiled js files should be kept
.PRECIOUS: packages/wp-plugin/build/%.js
# generic rule to transpile a single wp-plugin/*/src/*.mjs source into its transpiled result
packages/wp-plugin/%.js : $$(subst /build/,/src/,packages/wp-plugin/$$*.mjs)
> if [[ -f "$(<D)/../cm4all-wp-bundle.json" ]]; then
>   # using cm4all-wp-bundle if a configuration file exists
>   BUNDLER_CONFIG=$$(sed 's/^ *\/\/.*//' $(<D)/../cm4all-wp-bundle.json | jq .)
>   GLOBAL_NAME=$$(basename -s .mjs $<)
>   # if make was called from GitHub action we need to run cm4all-wp-bundle using --user root to have write permissions to checked out repository
>   # (the cm4all-wp-bundle image will by default use user "node" instead of "root" for security purposes)
>   GITHUB_ACTION_DOCKER_USER=$$( [ "$${GITHUB_ACTIONS:-false}" == "true" ] && echo '--user root' || echo '')
>   for mode in 'development' 'production' ; do
>     printf "$$BUNDLER_CONFIG" | \
      docker run -i --rm $$GITHUB_ACTION_DOCKER_USER --mount type=bind,source=$$(pwd),target=/app $(KAMBRIUM_WP_PLUGIN_DOCKER_IMAGE_JS_BUNDLER) \
        --analyze \
        --global-name="$$GLOBAL_NAME" \
        --mode="$$mode" \
        --outdir='$(@D)' \
        $<
>   done
>   # if runned in GitHub action touch will not work because of wrong permissions as a result of the docker invocation using --user root before
>   # => which was needed to have write access to the checkout out repository
>   [[ "$${GITHUB_ACTIONS:-false}" == "false" ]] && touch -m $@ $(@:.js=.min.js)
> else
>   # using wp-scrips as default
>   echo "[@TODO:] js/css transpilation of wp-plugin ressources using wp-scripts is not jet supported"
>   exit 1
> fi

# HELP<<EOF
# push wordpress plugin to wordpress.org
#
# see supported environment variables on target `wp-plugin-push-%`
# EOF
.PHONY: wp-plugin-push
wp-plugin-push: $(foreach PACKAGE, $(shell find packages/wp-plugin/ -mindepth 1 -maxdepth 1 -type d -printf "%f " 2>/dev/null ||:), $(addprefix wp-plugin-push-, $(PACKAGE))) ;

# HELP<<EOF
# push wordpress plugin to wordpress.org
#
# target will also update
#
#   - the readme.txt description/version/author using the `description` property of sub package file `package.json`
#   - the wordpress images
#
# at wordpress.org using
#
# supported variables are:
#   - `WORDPRESS_TOKEN` (required) the wordpress.org account password
#   - `WORDPRESS_USER` (optional,default=sub package scope without `@`) the wordpress.org identity/username.
#   - `WORDPRESS_PLUGIN` (optional,default=sub package name part after `/`)
#
# environment variables can be provided using:
#   - make variables provided at commandline
#   - `.env` file from sub package
#   - `.env` file from monorepo root
#   - environment
#
# example: `make wp-plugin-push-foo WORDPRESS_USER=foo WORDPRESS_TOKEN=foobar`
#
#    will build (if outdated) the wordpress plugins and push it ot wordpress.org
# EOF
.PHONY: wp-plugin-push-%
wp-plugin-push-%: packages/wp-plugin/$$*/
> # inject sub package environments from {.env,.secrets} files
> kambrium.load_env packages/wp-plugin/$*
> PACKAGE_JSON=packages/wp-plugin/$*/package.json
> PACKAGE_NAME=$$(jq -r '.name | values' $$PACKAGE_JSON | sed -r 's/@//g')
# if WORDPRESS_USER is not set take the package scope (example: "@foo/bar" wordpress user is "foo")
> WORDPRESS_USER=$${WORDPRESS_USER:-$${PACKAGE_NAME%/*}}
# if WORDPRESS_PLUGIN is not set take the package repository (example: "@foo/bar" wordpress plugin is "bar")
> WORDPRESS_PLUGIN=$${WORDPRESS_PLUGIN:-$${PACKAGE_NAME#*/}}
> abort if WORDPRESS_TOKEN is not defined
> : $${WORDPRESS_TOKEN:?"WORDPRESS_TOKEN environment is required but not given"}
> echo "push wordpress plugin $$WORDPRESS_PLUGIN to wordpress.org using user $$WORDPRESS_USER"
> if [[ "$$(jq -r '.private | values' $$PACKAGE_JSON)" != "true" ]]; then
>   PACKAGE_VERSION=$$(jq -r '.version | values' $$PACKAGE_JSON)
>   # @TODO: push plugin to wordpress.org
>   kambrium.log_done
> else
>   kambrium.log_skipped "package.json is marked as private"
> fi
