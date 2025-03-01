# syntax=docker/dockerfile:1.4

# php version of the docker image
ARG PHP_VERSION

FROM php:${PHP_VERSION}-cli as base

FROM php:${PHP_VERSION}-cli-alpine as build
COPY --from=composer /usr/bin/composer /usr/bin/composer

ARG ECS_VERSION

ENV COMPOSER_HOME=/tmp
ENV COMPOSER_ALLOW_SUPERUSER=1

RUN composer global config --no-plugins allow-plugins.dealerdirect/phpcodesniffer-composer-installer false \
  && composer global require symplify/easy-coding-standard:${ECS_VERSION} \
  && composer

FROM php:${PHP_VERSION}-cli-alpine

RUN apk add --no-cache icu-dev shadow && docker-php-ext-install intl

COPY --from=build /tmp/vendor/ /composer/
COPY --chmod=755 ./packages/docker/easy-coding-standard-php/entrypoint.sh /usr/bin

ENV PATH="${PATH}:/composer/bin/"

RUN groupadd --gid 1000 php && useradd --uid 1000 --gid php --shell /bin/sh --create-home php
USER php


VOLUME ["/project"]
WORKDIR /project

ENTRYPOINT ["/usr/bin/entrypoint.sh"]
