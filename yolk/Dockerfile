# The runtime VentaCart runs in on Pterodactyl.
#
# It carries no application code. The egg's install script clones VentaCart into
# /home/container, which is the only directory Wings keeps between restarts,
# and this image supplies everything around it: PHP, php-fpm, nginx,
# composer, git, and Node to build the storefront's CSS and JS, which the
# repository does not commit.
#
# The image's own user is root, on purpose. Wings runs the egg's install
# script in this image as the image's default user, and that script must
# write the server's directory. Servers themselves are never started as
# root: Wings always starts them as its own unprivileged user, so nothing
# VentaCart runs may assume it can write outside /home/container and /tmp.

FROM debian:trixie-slim

LABEL org.opencontainers.image.source="https://github.com/pao2pao16/ventacart-pterodactyl"
LABEL org.opencontainers.image.description="Runtime for VentaCart on Pterodactyl"

ARG PHP_VERSION=8.4
ENV PHP_VERSION=${PHP_VERSION} \
    DEBIAN_FRONTEND=noninteractive

# Node comes from Debian: trixie's 20.19 is the oldest release Vite 7 accepts.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl git unzip tini tzdata nginx nodejs npm \
      php${PHP_VERSION}-cli php${PHP_VERSION}-fpm php${PHP_VERSION}-mysql \
      php${PHP_VERSION}-gd php${PHP_VERSION}-intl php${PHP_VERSION}-zip \
      php${PHP_VERSION}-bcmath php${PHP_VERSION}-mbstring php${PHP_VERSION}-xml \
      php${PHP_VERSION}-curl php${PHP_VERSION}-opcache php${PHP_VERSION}-readline \
 && rm -rf /var/lib/apt/lists/* /etc/nginx/sites-enabled/default \
 && ln -s /usr/sbin/php-fpm${PHP_VERSION} /usr/local/sbin/php-fpm \
 && git config --system --add safe.directory '*' \
 && useradd -m -d /home/container -s /bin/bash container

COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer
COPY rootfs/ /

RUN chmod 755 /entrypoint.sh /usr/local/bin/ventacart-boot /usr/local/bin/ventacart-run \
 && ln -sf /etc/ventacart/php.ini /etc/php/${PHP_VERSION}/cli/conf.d/99-ventacart.ini \
 && ln -sf /etc/ventacart/php.ini /etc/php/${PHP_VERSION}/fpm/conf.d/99-ventacart.ini

ENV USER=container \
    HOME=/home/container
WORKDIR /home/container

ENTRYPOINT ["/usr/bin/tini", "-g", "--"]
CMD ["/entrypoint.sh"]
