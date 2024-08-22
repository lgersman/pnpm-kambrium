# contains generic docker related make settings and rules

#
# disable boring scan info while building docker images
# see https://github.com/docker/scan-cli-plugin/issues/149
#
export DOCKER_SCAN_SUGGEST:=false

#
# use  buildx for more performant image builds
# see https://docs.docker.com/build/buildkit/
#
export DOCKER_BUILDKIT:=1

DEFAULT_DOCKER_REGISTRY:=registry.hub.docker.com

#
# target docker registry
#
export DOCKER_REGISTRY?=$(DEFAULT_DOCKER_REGISTRY)

# HELP<<EOF
# build and tag all outdated docker images in `packages/docker/`
#
# EOF
packages/docker/: $(KAMBRIUM_SUB_PACKAGE_FLAVOR_DEPS) ;

# HELP<<EOF
# build and tag outdated docker image sub package by name.
#
# image metadata like author/description/version will be taken from sub package file `package.json`
#
# example: `make packages/docker/foo/`
#
#   will build the docker image in sub package `packages/docker/foo`
# EOF
packages/docker/%/: $(KAMBRIUM_SUB_PACKAGE_DEPS) ;

# build and tag docker image
#
# supported variables are:
#   - `AUTHOR_NAME` (optional,default=package.json .author.name)
#   - `AUTHOR_EMAIL` (optional,default=package.json .author.name)
#
# environment variables can be provided using:
#   - make variables provided at commandline
#   - `.env` file from sub package
#   - `.env` file from monorepo root
#   - environment
#
# we utilize file "build-info" to track if the docker image was build/is up to date
packages/docker/%/build-info: $(KAMBRIUM_SUB_PACKAGE_BUILD_INFO_DEPS)
> # inject sub package environments from {.env,.secrets} files
> kambrium.load_env $(@D)
> PACKAGE_JSON=$(@D)/package.json
> PACKAGE_VERSION=$$(jq -r '.version | values' $$PACKAGE_JSON)
> PACKAGE_AUTHOR="$$(kambrium.author_name $$PACKAGE_JSON) <$$(kambrium.author_email $$PACKAGE_JSON)>"
> PACKAGE_NAME=$$(jq -r '.name | values' $$PACKAGE_JSON | sed -r 's/@//g')
# if DOCKER_USER is not set take the package scope (example: "@foo/bar" package user is "foo")
> DOCKER_USER=$${DOCKER_USER:-$${PACKAGE_NAME%/*}}
# if DOCKER_REPOSITORY is not set take the package repository (example: "@foo/bar" package repository is "bar")
> DOCKER_REPOSITORY=$${DOCKER_REPOSITORY:-$${PACKAGE_NAME#*/}}
> DOCKER_IMAGE="$$DOCKER_USER/$$DOCKER_REPOSITORY"
> rm -rf $(@D)/{dist,build,build-info}
> $(PNPM) -r --filter "$$(jq -r '.name | values' $$PACKAGE_JSON)" --if-present run pre-build
# image labels : see https://github.com/opencontainers/image-spec/blob/main/annotations.md#pre-defined-annotation-keys
> docker build \
>   $$(test -f $(@D)/.env && cat $(@D)/.env | sed 's/^/--build-arg /' ||:) \
>   --progress=plain \
>   -t $$DOCKER_IMAGE:latest \
>   -t $$DOCKER_IMAGE:$$PACKAGE_VERSION \
>   --label "maintainer=$$PACKAGE_AUTHOR" \
>   --label "org.opencontainers.image.title=$$DOCKER_IMAGE" \
>   --label "org.opencontainers.image.description=$$(jq -r '.description | values' $$PACKAGE_JSON)" \
>   --label "org.opencontainers.image.authors=$$PACKAGE_AUTHOR" \
>   --label "org.opencontainers.image.source=$$(jq -r -e '.repository.url | values' $$PACKAGE_JSON || jq -r '.repository.url | values' package.json)" \
>   --label "org.opencontainers.image.url=$$(jq -r -e '.homepage | values' $$PACKAGE_JSON || jq -r '.homepage | values' package.json)" \
>   --label "org.opencontainers.image.vendor=https://cm4all.com" \
>   --label "org.opencontainers.image.licenses=$$(jq -r -e '.license | values' $$PACKAGE_JSON || jq -r '.license | values' package.json)" \
>   -f $(@D)/Dockerfile .
# output generated image labels
> cat << EOF | tee $@
> $$(docker image inspect $$DOCKER_IMAGE:latest | jq '.[0].Config.Labels | values')
>
> $$(echo -n "---")
>
> $$(docker image ls --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.CreatedAt}}\t{{.Size}}" $$DOCKER_IMAGE:$$PACKAGE_VERSION)
> EOF

# HELP<<EOF
# push docker images to registry
#
# see supported environment variables on target `docker-push-%`
# EOF
.PHONY: docker-push
docker-push: $(foreach PACKAGE, $(shell find packages/docker/ -mindepth 1 -maxdepth 1 -type d -printf "%f " 2>/dev/null ||:), $(addprefix docker-push-, $(PACKAGE))) ;

# HELP<<EOF
# push docker image to registry.
#
# target will also update
#
#   - the image short description using the `description` property of sub package file `package.json`
#   - image long description using sub package file `README.md`
#
# at the docker registry using
#
# supported variables are:
#   - `DOCKER_TOKEN` (required) can be the docker password (a docker token is preferred for security reasons)
#   - `DOCKER_USER` (optional,default=sub package scope without `@`) use the docker identity/username, your docker account email will not work
#   - `DOCKER_REPOSITORY` (optional,default=sub package name part after minus)
#   - `DOCKER_REGISTRY` (optional,default=$(DEFAULT_DOCKER_REGISTRY))
#
# environment variables can be provided using:
#   - make variables provided at commandline
#   - `.env` file from sub package
#   - `.env` file from monorepo root
#   - environment
#
# example: `make docker-push-foo DOCKER_USER=foo DOCKER_TOKEN=foobar`
#
#    will build/tag (if outdated) the docker image and push it to wordpress.org
# EOF
.PHONY: docker-push-%
docker-push-%: packages/docker/$$*/
> # inject sub package environments from {.env,.secrets} files
> kambrium.load_env packages/docker/$*
> PACKAGE_JSON=packages/docker/$*/package.json
> PACKAGE_NAME=$$(jq -r '.name | values' $$PACKAGE_JSON | sed -r 's/@//g')
# if DOCKER_USER is not set take the package scope (example: "@foo/bar" package user is "foo")
> DOCKER_USER=$${DOCKER_USER:-$${PACKAGE_NAME%/*}}
# if DOCKER_REPOSITORY is not set take the package repository (example: "@foo/bar" package repository is "bar")
> DOCKER_REPOSITORY=$${DOCKER_REPOSITORY:-$${PACKAGE_NAME#*/}}
> DOCKER_IMAGE="$$DOCKER_USER/$$DOCKER_REPOSITORY"
# abort if DOCKER_TOKEN is not defined
> : $${DOCKER_TOKEN:?"DOCKER_TOKEN environment is required but not given"}
> echo "push docker image $$DOCKER_IMAGE using docker user $$DOCKER_USER"
> if [[ "$$(jq -r '.private | values' $$PACKAGE_JSON)" != "true" ]]; then
>   PACKAGE_VERSION=$$(jq -r '.version | values' $$PACKAGE_JSON)
>   # docker login --username [username] and docker access-token or real password must be initially before push
>   echo "$$DOCKER_TOKEN" | docker login --username "$$DOCKER_USER" --password-stdin $$([[ "$$DOCKER_REGISTRY" != "$(DEFAULT_DOCKER_REGISTRY)" ]] && echo "$$DOCKER_REGISTRY") >/dev/null 2>&1
>   docker push $(DOCKER_FLAGS) $$DOCKER_IMAGE:latest
>   docker push $(DOCKER_FLAGS) $$DOCKER_IMAGE:$$PACKAGE_VERSION
>   kambrium.log_done
>
>   # if DOCKER_REGISTRY == $(DEFAULT_DOCKER_REGISTRY) : update description and README.md
>   if [[ "$$DOCKER_REGISTRY" == "$(DEFAULT_DOCKER_REGISTRY)" ]]; then
>     echo "updating description/README.md for docker image $$DOCKER_IMAGE"
#>     cat ~/my_password.txt | docker login --username foo --password-stdin
#>     docker login --username='$(DOCKER_USER)' --password='$(DOCKER_PASS)' $${DOCKER_HOST:-}
>     LOGIN_PAYLOAD=$$(printf '{ "username": "%s", "password": "%s" }' "$$DOCKER_USER" "$$DOCKER_TOKEN")
>     JWT_TOKEN=$$($(CURL) -H "Content-Type: application/json" -X POST -d "$$LOGIN_PAYLOAD" https://hub.docker.com/v2/users/login/ | jq --exit-status -r .token)
>     # GET : > $(CURL) -v -H "Authorization: JWT $${JWT_TOKEN}" "https://hub.docker.com/v2/repositories/$$DOCKER_IMAGE/"
>     DESCRIPTION=$$(docker image inspect --format='' $$DOCKER_IMAGE:latest | jq -r '.[0].Config.Labels["org.opencontainers.image.description"] | values')
>     # see https://frontbackend.com/linux/how-to-post-a-json-data-using-curl
>     # see https://stackoverflow.com/a/48470227/1554103
>     DATA=`jq -n \
>       --arg description "$$(jq -r '.description | values' $$PACKAGE_JSON)" \
>       --arg full_description "$$(cat packages/docker/$*/README.md 2>/dev/null ||:)" '{description: $$description, full_description: $$full_description}' \
>     `
>     $(CURL) \
>       -H "Content-Type: application/json" \
>       -H "Authorization: JWT $${JWT_TOKEN}" \
>       -X PATCH \
>       --data "$$DATA" \
>       "https://hub.docker.com/v2/repositories/$$DOCKER_IMAGE/" \
>     | jq '{ description, full_description }'
>     kambrium.log_done
>   fi
> else
>   kambrium.log_skipped "package.json is marked as private"
> fi

# HELP<<EOF
# this target will cleanup local docker artefacts by removing
#  - all stopped containers
#  - all networks not used by at least one container
#  - all dangling images
#  - all dangling build cache
#
# example: `make docker-prune`
# EOF
.PHONY: docker-prune
docker-prune:
> docker system prune
