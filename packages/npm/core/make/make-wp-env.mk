# contains wp-env related make settings and rules
KAMBRIUM_SHELL_ALWAYS_PRELOAD += $(KAMBRIUM_MAKEFILE_DIR)/make-wp-env.sh

export WP_ENV_HOME := $(shell pwd)/wp-env-home

# dynamic variable to retrieve the wp-env install path
WP_ENV_INSTALL_PATH = $(shell $(MAKE) -s wp-env COMMAND=install-path 2> /dev/null)

#
# generates wp-env configuration file '.wp-env.json'
# (https://developer.wordpress.org/block-editor/reference-guides/packages/packages-env/#wp-env-json)
#
.wp-env.json:
> # nullglob is needed because we want to skip the loop if no plugins/theme packages are found
> shopt -s nullglob
>
> PLUGINS='[]'
> for plugin in packages/wp-plugin/*/; do
>   PLUGINS=$$(echo "$$PLUGINS" | jq --arg plugin "./$$plugin" '. += [$$plugin]')
> done
>
> THEMES='[]'
> for theme in packages/wp-theme/*/; do
>   THEMES=$$(echo "$$THEMES" | jq --arg theme "./$$theme" '. += [$$theme]')
> done
>
> jq -n \
>   --arg wordpress_image "WordPress/WordPress#$${REQUIRES_AT_LEAST_WORDPRESS_VERSION:-latest}" \
>   --arg phpVersion "$${PHP_VERSION:-8.0}" \
>   --argjson plugins "$${PLUGINS}" \
>   --argjson themes "$${THEMES}" \
>   '{core: $$wordpress_image, phpVersion: $$phpVersion, plugins : $$plugins, themes : $$themes }' \
> > $@

#
# generic target acting as entrypoint to wp-env functionality
#
# supported make variables:
#   - COMMAND the wp-env command to execute
#   - ARGS the wp-env command arguments
#
.PHONY: wp-env
wp-env: ARGS ?=
wp-env: .wp-env.json
> WP_ENV_HOME=$(WP_ENV_HOME) $(PNPM) exec wp-env $(COMMAND) $(ARGS)

# HELP<<EOF
# stops wp-env (https://developer.wordpress.org/block-editor/reference-guides/packages/packages-env/#wp-env-stop)
#
# supported make variables:
#   - ARGS (default=``) the wp-env command arguments
#
# example: `make wp-env-stop`
#
#    stop the wp-env instance
# EOF
.PHONY: wp-env-stop
wp-env-stop: ARGS ?=
wp-env-stop:
> $(MAKE) wp-env COMMAND=stop ARGS='$(ARGS)'

# HELP<<EOF
# destroy wp-env (https://developer.wordpress.org/block-editor/reference-guides/packages/packages-env/#wp-env-destroy)
#
# supported make variables:
#   - ARGS (default=``) the wp-env command arguments
#
# example: `echo 'y' | make wp-env-destroy`
#
#    destroys the wp-env instance without asking for confirmation
# EOF
.PHONY: wp-env-destroy
wp-env-destroy: ARGS ?=
wp-env-destroy:
> $(MAKE) wp-env COMMAND=destroy ARGS='$(ARGS)'
> rm -rf $(WP_ENV_HOME)

# HELP<<EOF
# runs a shell command within a wp-env container
#
# supported make variables:
#   - CONTAINER (default=`cli`) the wp-env container to run the command in,
#     possible values are `mysql`, `tests-mysql`, `wordpress`, `tests-wordpress`, `cli`, `tests-cli`
#
#   - ARGS (default=``) the wp-env containers shell command
#
# example: `make wp-env-sh CONTAINER="tests-cli" ARGS="wp post list --field=ID --post_type=page,post,attachment | xargs wp post delete --force"`
#
#    deletes all posts, pages and attachments from the wp-env tests instance
# EOF
.PHONY: wp-env-sh
wp-env-sh: ARGS ?=
wp-env-sh: CONTAINER ?= cli
wp-env-sh: wp-env-is-started
> WP_ENV_HOME=$(WP_ENV_HOME) $(PNPM) exec wp-env run $(CONTAINER) sh -c '$(ARGS)'

# runs wp-env-start target if wp-env is not yet started
# (we cannot use target wp-env-start as dependecy becauce wp-env-start will everytime explicitly called shutdown and start wp-env again)
# thats why we check if wp-env docker containers are running an if not call wp-env-start
.PHONY: wp-env-is-started
wp-env-is-started:
> [[ "$$(docker ps | grep wordpress | wc -l)" == "2" ]] || $(MAKE) -s -i wp-env-start

# HELP<<EOF
# show wp-env logs (https://developer.wordpress.org/block-editor/reference-guides/packages/packages-env/#wp-env-logs-environment)
#
# supported make variables:
#   - ARGS (default=`development`) the wp-env command arguments
#
# example: `make wp-env-logs ARGS='tests' --debug`
#
#    shows log of wp-env instance `tests` with verbose output
# EOF
.PHONY: wp-env-logs
wp-env-logs: ARGS ?= development
wp-env-logs:
> $(MAKE) wp-env COMMAND=logs ARGS='$(ARGS)' || (kambrium.log_error "wp-env is not started. consider executing 'make wp-env-start' first." && exit 1)

# HELP<<EOF
# run command inside a wp-env container (https://developer.wordpress.org/block-editor/reference-guides/packages/packages-env/#wp-env-run-container-command)
#
# supported make variables:
#   - ARGS (default=`cli bash`) the wp-env command arguments
#
# example: `make wp-env-run`
#
#    open bash shell of the wp-env wordpress (development) container
#
# example: `make wp-env-run ARGS='mysql sh'`
#
#    open a shell of the wp-env mysql (development) container
#
# example: `make wp-env-run ARGS='cli wp plugin list --debug'`
#
#    call wp-cli of the wp-env wordpress (development) container and list all installed plugins with verbose output
#
# example: `make wp-env-run ARGS='tests-cli wp shell'`
#
#    open up interactive wp-cli shell of the wp-env wordpress tests container
# EOF
.PHONY: wp-env-run
wp-env-run: ARGS ?= cli bash
wp-env-run:
> $(MAKE) wp-env COMMAND='run' ARGS='$(ARGS)'

# HELP<<EOF
# clean wp-env (https://developer.wordpress.org/block-editor/reference-guides/packages/packages-env/#wp-env-clean-environment)
#
# supported make variables:
#   - ARGS (default=`all`) the wp-env command arguments
#
# example: `make wp-env-clean ARGS='tests'`
#
#    clean the tests instance of wp-env
# EOF
.PHONY: wp-env-clean
wp-env-clean: ARGS ?= all
wp-env-clean:
> $(MAKE) wp-env COMMAND=clean ARGS='$(ARGS)' || (kambrium.log_error "wp-env is not started. consider executing 'make wp-env-start' first." && exit 1)

# HELP<<EOF
# backup database and uploads folder of a wp-env instance
#
# supported make variables:
#   - ARGS (default=`development`, the development instance). Possible values are `development`, `tests`
#   - DIR (default=`./wp-env-backup`) the directory to store the backup
#
# example: `make wp-env-backup`
#
#    backup the development instance data of wp-env into directory `wp-env-backup`
#
# example: `make wp-env-backup ARGS='tests' DIR='./my-other-backup'`
#
#    backup the tests instance data of wp-env into directory `my-other-backup`
# EOF
.PHONY: wp-env-backup
wp-env-backup: ARGS ?= development
wp-env-backup: DIR ?= ./wp-env-backup
wp-env-backup:
> rm -rf "$(DIR)"
> mkdir -p "$(DIR)"
> $(MAKE) -s wp-env-db-export DB=$(ARGS) > "$(DIR)/db.sql"
> CONTAINER=$$([[ '$(ARGS)' == 'tests' ]] && echo 'tests-wordpress' || echo 'wordpress')
> docker compose $(DOCKER_COMPOSE_FLAGS) -f "$(WP_ENV_INSTALL_PATH)/docker-compose.yml" cp $$CONTAINER:/var/www/html/wp-content/uploads "$(DIR)"

# HELP<<EOF
# restore database and uploads folder of a wp-env instance
#
# supported make variables:
#   - ARGS (default=`development`, the development instance). Possible values are `development`, `tests`
#   - DIR (default=`./wp-env-backup`) the directory to store the backup
#
# example: `make wp-env-restore`
#
#    restore the development instance data of wp-env into directory `wp-env-backup`
#
# example: `make wp-env-restore ARGS='tests' DIR='./my-other-backup'`
#
#    restore the tests instance data of wp-env into directory `my-other-backup`
# EOF
.PHONY: wp-env-restore
wp-env-restore: ARGS ?= development
wp-env-restore: DIR ?= ./wp-env-backup
wp-env-restore:
> CONTAINER=$$([[ '$(ARGS)' == 'tests' ]] && echo 'tests-wordpress' || echo 'wordpress')
> if [[ -d "$(DIR)" ]]; then
>   docker compose $(DOCKER_COMPOSE_FLAGS) -f "$(WP_ENV_INSTALL_PATH)/docker-compose.yml" exec -T $$CONTAINER rm -rf /var/www/html/wp-content/uploads
>   $(MAKE) wp-env-db-import DB=$(ARGS) < "$(DIR)/db.sql"
>   docker compose $(DOCKER_COMPOSE_FLAGS) -f "$(WP_ENV_INSTALL_PATH)/docker-compose.yml" cp "$(DIR)/uploads" $$CONTAINER:/var/www/html/wp-content
> else
>   kambrium.log_error "import directory(='$$DIR') does not exist" && exit 1
> fi


# HELP<<EOF
# spit a diffable dump from a wp-env database container to stdout
#
# supported make variables:
#   - DB (default=`development`) the database to dump (possible values are `development`, `tests`)
#   - ARGS (default=all tables will be dumped) the database tables to include in the export
#
# example: `make -s wp-env-db-dump`
#
#    writes the development database dump to stdout (note the `-s` flag to suppress verbose make output)
#
# example: `make -s wp-env-db-dump DB='tests' > ./test-db.sql`
#
#    writes the test database dump to file `./test-db.sql` (note the `-s` flag to suppress verbose make output)
#
# example: `make -s wp-env-db-dump DB=tests ARGS='wp_users wp_terms' > ./partial-diffable-wp-dump.sql`
#
#   writes a partial dump (only tables `wp_users` and `wp_terms`) of the wp-env tests database to file `./partial-diffable-wp-dump.sql
#   (note the `-s` flag to suppress verbose make output)
#
# EOF
.PHONY: wp-env-db-dump
wp-env-db-dump: DB ?= development
wp-env-db-dump: ARGS ?=
wp-env-db-dump:
> DATABASE_CONTAINER=$$([[ '$(DB)' == 'tests' ]] && echo 'tests-mysql' || echo 'mysql')
> (docker compose $(DOCKER_COMPOSE_FLAGS) -f "$(WP_ENV_INSTALL_PATH)/docker-compose.yml" exec -T $$DATABASE_CONTAINER \
>   sh -c 'mariadb-dump --compact --skip-comments --skip-extended-insert --password="$$MYSQL_ROOT_PASSWORD" $$MYSQL_DATABASE $(ARGS)' \
> ) \
> || (kambrium.log_error "wp-env is not started. consider executing 'make wp-env-start' first." && exit 1)

# HELP<<EOF
# exports a wp-env database to stdout
#
# supported make variables:
#   - DB (default=`development`) the database to export (possible values are `development`, `tests`)
#   - ARGS (default=all tables will be exported) the database tables to include in the export
#
# example: `make -s wp-env-db-export`
#
#    exports the development database to stdout (note the `-s` flag to suppress verbose make output)
#
# example: `make -s wp-env-db-export DB='tests' > ./test-db.sql`
#
#    writes the test database export to file `./test-db.sql` (note the `-s` flag to suppress verbose make output)
#
# example: `make -s wp-env-db-export DB=tests ARGS='wp_users wp_terms' > ./partial-diffable-wp-dump.sql`
#
#   writes a partial export (only tables `wp_users` and `wp_terms`) of the wp-env tests database to file `./partial-diffable-wp-dump.sql
#   (note the `-s` flag to suppress verbose make output)
#
# EOF
.PHONY: wp-env-db-export
wp-env-db-export: DB ?= development
wp-env-db-export: ARGS ?=
wp-env-db-export:
> DATABASE_CONTAINER=$$([[ '$(DB)' == 'tests' ]] && echo 'tests-mysql' || echo 'mysql')
> (docker compose $(DOCKER_COMPOSE_FLAGS) -f "$(WP_ENV_INSTALL_PATH)/docker-compose.yml" exec -T $$DATABASE_CONTAINER \
>   sh -c 'mariadb-dump --password="$$MYSQL_ROOT_PASSWORD" $$MYSQL_DATABASE $(ARGS)' \
> ) \
> || (kambrium.log_error "wp-env is not started. consider executing 'make wp-env-start' first." && exit 1)

# HELP<<EOF
# imports a wp-env database export from stdin into a wp-env database
#
# supported make variables:
#   - DB (default=`development`) the database to dump (possible values are `development`, `tests`)
#   - ARGS (default='') additional arguments for the mariadb command
#
# example: `make wp-env-db-import < ./myexport.sql`
#
#    imports the database export file `./myexport.sql` into the wp-env development database
#
# example: `make wp-env-db-import DB='tests' < ./myexport.sql`
#
#    imports the database export file `./myexport.sql` into the wp-env tests database
#
# example: `make wp-env-db-import DB=tests ARGS='-v' < ./myexport.sql`
#
#   imports the database export file `./myexport.sql` into the wp-env development database.
#   the `-v` flag in ARGS tells mariadb to be verbose while importing
#
# EOF
.PHONY: wp-env-db-import
wp-env-db-import: DB ?= development
wp-env-db-import: ARGS ?=
wp-env-db-import:
> DATABASE_CONTAINER=$$([[ '$(DB)' == 'tests' ]] && echo 'tests-mysql' || echo 'mysql')
> (docker compose $(DOCKER_COMPOSE_FLAGS) -f "$(WP_ENV_INSTALL_PATH)/docker-compose.yml" exec -T $$DATABASE_CONTAINER \
>   sh -c 'mariadb $(ARGS) --password="$$MYSQL_ROOT_PASSWORD" $$MYSQL_DATABASE' \
> ) \
> || (kambrium.log_error "wp-env is not started. consider executing 'make wp-env-start' first." && exit 1)

# HELP<<EOF
# starts wp-env (https://developer.wordpress.org/block-editor/reference-guides/packages/packages-env/#wp-env-start)
# will build (if outdated) the wordpress plugins/themes before starting up wp-env
# the wp-env folder will be located in `./wp-env-home`
#
# a `.wp-env.json` will be generated if not exist:
#   - plugins populated from directories `packages/wp-plugin/*`
#   - themes populated from directories `packages/wp-theme/*`
#   - WordPress version retrieved from `.env` file entry `REQUIRES_AT_LEAST_WORDPRESS_VERSION`
#   - php version retrieved from `.env` file entry `PHP_VERSION`
#
# a vscode launch configuration will be generated for debugging plugins/themes
#
# wp-env settings can be customized by providing file `.wp-env-override.json`
# (https://developer.wordpress.org/block-editor/reference-guides/packages/packages-env/#wp-env-override-json)
#
# environment variables can be provided using:
#   - make variables provided at commandline
#   - `.env` file from monorepo root
#   - environment
#
# supported make variables:
#   - ARGS (default=``) the wp-env command arguments
#
# example: `make wp-env-start ARGS='--debug --xdebug'`
#
#    start wp-env with option xdebug and debug enabled
# EOF
.PHONY: wp-env-start
wp-env-start: ARGS ?=
wp-env-start .vscode/launch.json: $(addsuffix /,$(wildcard packages/wp-plugin/* packages/wp-theme/*)) $(wildcard .env .secrets)
> # we always stop wp-env before start to ensure changed wp-env config files will always take effect
> $(MAKE) -s -i wp-env-stop >/dev/null 2>&1
> $(MAKE) wp-env COMMAND=start ARGS='$(ARGS)'
>
> # generates vscode launch configuration for wp-env (https://developer.wordpress.org/block-editor/reference-guides/packages/packages-env/#xdebug-ide-support)
> # CAVEAT :
> #   we cannot use WP_ENV_INSTALL_PATH here - its computed by make *before* executing the target
> #   calling `kambrium.wp-env.generate_launch.json "$(WP_ENV_INSTALL_PATH)"` will fail because WP_ENV_INSTALL_PATH computed by make is "" at this point
> #   thats why we need to call wp-env COMMAND=install-path manually
> kambrium.wp-env.generate_launch.json "$$($(MAKE) -s wp-env COMMAND=install-path 2> /dev/null)"

