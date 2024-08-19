# wordpress plugin related shell helper functions

#
# computes the i18n pot path from the i18n po path containing the locale
#
# example:
#   kambrium.get_pot_path "packages/wp-plugin/cm4all-wp-impex/languages/cm4all-wp-impex-en_US.po"
#   => "packages/wp-plugin/cm4all-wp-impex/languages/cm4all-wp-impex.pot"
#
# @param $1 the po path containing the locale
# @return the computed pot path
#
function kambrium.get_pot_path() {
  local po_path="$1"
  local locale=$([[ "$po_path" =~ ([a-z]+_[A-Z]+)\.po$ ]] && echo ${BASH_REMATCH[1]})
  echo "${po_path%?$locale.*}.pot"
}

#
# computes the makefile dependencies for a i18n pot file
#
# example:
#   kambrium.get_pot_path "packages/wp-plugin/cm4all-wp-impex/languages/cm4all-wp-impex-en_US.po"
#   => "packages/wp-plugin/cm4all-wp-impex/languages/cm4all-wp-impex.pot"
#
# @param $1 the plugin directory
# @return the computed dependencies
#
function kambrium.get_pot_dependencies() {
  local WP_PLUGIN_DIRECTORY="packages/$(kambrium.get_sub_package_type_from_path $1)/$(kambrium.get_sub_package_name_from_path $1)"

  find $WP_PLUGIN_DIRECTORY/src -maxdepth 1 -type f -name '*.mjs' -or -name 'block.json' | sed -e 's/src/build/g' -e 's/.mjs/.js/g'
  find $WP_PLUGIN_DIRECTORY -type f ! -path '*/tests/*' ! -path '*/dist/*' ! -path '*/vendor/*' ! -path '*/build/*' -and \( -name '*.php' -or -name 'theme.json' \)
}

#
# computes the plugin metadata like authors and stuff and exposes them as exports
#
# example:
#   kambrium.get_wp_plugin_metadata "packages/wp-plugin/cm4all-wp-impex"
#
# @param $1 the plugin directory
# @return the names of all exported variables
#
function kambrium.get_wp_plugin_metadata() {
  local CURRENT_ALLEXPORT_STATE="$(shopt -po allexport)"
  set -a
  local WP_PLUGIN_DIRECTORY="packages/$(kambrium.get_sub_package_type_from_path $1)/$(kambrium.get_sub_package_name_from_path $1)"
  # inject sub package environments from {.env,.secrets} files
  kambrium.load_env "$WP_PLUGIN_DIRECTORY"
  PACKAGE_JSON="$WP_PLUGIN_DIRECTORY/package.json"
  PACKAGE_VERSION=${PACKAGE_VERSION:-$(jq -r '.version | values' $PACKAGE_JSON)}
  PACKAGE_AUTHOR="${PACKAGE_AUTHOR:-$(kambrium.author_name $PACKAGE_JSON) <$(kambrium.author_email $PACKAGE_JSON)>}"
  FQ_PACKAGE_NAME=$(jq -r '.name | values' $PACKAGE_JSON | sed -r 's/@//g')
  PACKAGE_NAME=${PACKAGE_NAME:-${FQ_PACKAGE_NAME#*/}}
  HOMEPAGE=${HOMEPAGE:-$(jq -r -e '.homepage | values' $PACKAGE_JSON || jq -r -e '.homepage | values' package.json || echo "${VENDOR:-}")}
  DESCRIPTION=${DESCRIPTION:-$(jq -r -e '.description | values' $PACKAGE_JSON || jq -r '.description | values' package.json)}
  TAGS=${TAGS:-$(jq -r -e '.keywords | values | join(", ")' $PACKAGE_JSON || jq -r '.keywords | values | join(", ")' package.json)}
  PHP_VERSION=${PHP_VERSION:-$(jq -r -e '.config.php_version | values' $PACKAGE_JSON || jq -r '.config.php_version | values' package.json)}
  WORDPRESS_VERSION=${WORDPRESS_VERSION:-$(jq -r -e '.config.wordpress_version | values' $PACKAGE_JSON || jq -r '.config.wordpress_version | values' package.json)}
  AUTHORS="${AUTHORS:-[]}"
  [[ "$AUTHORS" == '[]' ]] && AUTHORS=$(jq '[.contributors[]? | .name]' $PACKAGE_JSON)
  [[ "$AUTHORS" == '[]' ]] && AUTHORS=$(jq '[.author.name | select(.|.!=null)]' $PACKAGE_JSON)
  [[ "$AUTHORS" == '[]' ]] && AUTHORS=$(jq '[.contributors[]? | .name]' package.json)
  [[ "$AUTHORS" == '[]' ]] && AUTHORS=$(jq '[.author.name | select(.|.!=null)]' package.json)
  # if AUTHORS looks like a json array ([.*]) transform it into a comma separated list
  if [[ "$AUTHORS" =~ ^\[.*\]$ ]]; then
    AUTHORS=$(echo "$AUTHORS" | jq -r '. | values | join(", ")')
  fi
  VENDOR=${VENDOR:-}
  LICENSE=${LICENSE:-$(\
    jq -r -e 'if (.license | type) == "string" then .license else .license.type end | values' $PACKAGE_JSON || \
    jq -r -e 'if (.license | type) == "string" then .license else .license.type end | values' package.json || \
    true \
  )}
  LICENSE_URI=${LICENSE_URI:-$(\
    jq -r -e '.license.uri | values' $PACKAGE_JSON 2>/dev/null || \
    jq -r -e '.license.uri | values' package.json 2>/dev/null || \
    [[ "$LICENSE" != "" ]] && echo "https://opensource.org/licenses/$LICENSE" || \
    true \
  )}

  REQUIRES_AT_LEAST_WORDPRESS_VERSION=${REQUIRES_AT_LEAST_WORDPRESS_VERSION:-$WORDPRESS_VERSION}

  #  @TODO: convert markdown to readme.txt markdown and strip 1st line containing sub package name
  CHANGELOG=${CHANGELOG:-$([[ -f "$WP_PLUGIN_DIRECTORY/CHANGELOG.md" ]] && sed 's/^### \(.*\)/*\1*/g;s/^## \(.*\)/= \1 =/g;' "$WP_PLUGIN_DIRECTORY/CHANGELOG.md" ||:)}

  local NAMES=( \
    PACKAGE_JSON \
    PACKAGE_VERSION \
    PACKAGE_AUTHOR \
    FQ_PACKAGE_NAME \
    PACKAGE_NAME \
    HOMEPAGE \
    DESCRIPTION \
    TAGS \
    PHP_VERSION \
    WORDPRESS_VERSION \
    AUTHORS \
    VENDOR \
    LICENSE \
    LICENSE_URI \
    CHANGELOG \
    REQUIRES_AT_LEAST_WORDPRESS_VERSION \
  )

  # print names each on a new line
  NAMES=$(printf "\n%s" "${NAMES[@]}")
  echo "${NAMES:1}"

  # restore the value of allexport option to its original value.
  eval "$CURRENT_ALLEXPORT_STATE" >/dev/null
}

#
# generates the readme.txt file in the dist folder of a wordpress plugin
# based on the plugin specific template or the default readme.txt template (if not present)
#
# if the plugin doesnt provide any screenshots they will be copied from the default template
# (./node_modules/@pnpmkambrium/core/presets/default/wp-plugin)
#
# example:
#   kambrium.wp_plugin_dist_readme_txt "cm4all-wp-impex"
#
# @param $1 the plugin name
#
function kambrium.wp_plugin_dist_readme_txt() {
  local plugin_name=$1
  local plugin_path="packages/wp-plugin/$plugin_name"
  local readme_txt="$plugin_path/dist/$plugin_name/readme.txt"

  VARIABLES=$(kambrium.get_wp_plugin_metadata packages/wp-plugin/$1)

  # prefer plugin specific readme.txt over default fallback
  if [[ -f "$plugin_path/readme.txt1" ]]; then
    README_TXT="$plugin_path/readme.txt"
  else
    README_TXT='./node_modules/@pnpmkambrium/core/presets/default/wp-plugin/readme.txt'

    # copy dummy screenshots/icon to dist directory
    # generate dummy images:
    #    screenshot-1.png: convert -size 640x480 +delete xc:white -background lightgrey -fill gray -pointsize 24 -gravity center label:'Screenshot-1' ./screenshot-1.png
    #    banner-772x250.png: convert -size 772x250 +delete xc:white -background lightgrey -fill gray -pointsize 24 -gravity center label:'Banner 772 x 250 px' ./banner-772x250.png
    #    banner-1544x500.png: convert -size 1544x500 +delete xc:white -background lightgrey -fill gray -pointsize 24 -gravity center label:'Banner 1544 x 500 px' ./banner-1544x500.png
    find ./node_modules/@pnpmkambrium/core/presets/default/wp-plugin \
      -maxdepth 1 \
      -type f \
      \( -name "*.png" -o -name "*.jpeg" -o -name "*.jpg" -o -name "*.gif" -o -name "icon.svg" \) \
      -print0 \
    | xargs -0 -I {} cp -v {} $plugin_path/dist/$plugin_name/
  fi

  # convert variables list into envsubst compatible form
  VARIABLES=$(echo "$VARIABLES" | sed 's/.*/$${&}/')

  # process readme.txt and write output to dist/readme.txt
  envsubst "$VARIABLES" < "$README_TXT" > $readme_txt
}
