# Image Apache + PHP (mod_php) pour Pterodactyl, pensée pour Symfony.
# Basée sur l'image officielle PHP : reconstruite par Docker à chaque version
# corrective de PHP et à chaque mise à jour de sécurité Debian.
ARG PHP_VERSION=8.4
FROM php:${PHP_VERSION}-apache

LABEL org.opencontainers.image.title="pterodactyl-apache-php" \
      org.opencontainers.image.description="Apache + PHP pour Pterodactyl (Symfony)" \
      org.opencontainers.image.source="https://github.com/VenstoneMC/pterodactyl-apache-php"

# Installeur d'extensions (gère les dépendances système de chaque extension)
COPY --from=mlocati/php-extension-installer:2 /usr/bin/install-php-extensions /usr/local/bin/
# Composer 2
COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer

RUN set -eux; \
    apt-get update; \
    apt-get upgrade -y; \
    apt-get install -y --no-install-recommends git unzip ffmpeg ca-certificates tini; \
    install-php-extensions gd intl opcache zip apcu; \
    php -m | grep -qi '^pdo_sqlite$'; \
    rm -rf /var/lib/apt/lists/* /tmp/*; \
    # Utilisateur Pterodactyl (uid 988 par défaut côté Wings)
    useradd -m -d /home/container -u 988 -s /bin/bash container; \
    # Config PHP de production comme base
    cp "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"; \
    # Modules Apache utiles à Symfony ; on retire ceux qui exposent des infos
    a2enmod rewrite headers expires deflate remoteip; \
    a2dismod -f status autoindex; \
    a2disconf other-vhosts-access-log serve-cgi-bin; \
    rm -f /etc/apache2/sites-enabled/* /etc/apache2/conf-enabled/security.conf; \
    : > /etc/apache2/ports.conf

COPY apache/venstone.conf /etc/apache2/conf-enabled/zz-venstone.conf
COPY php/zz-venstone.ini "$PHP_INI_DIR/conf.d/zz-venstone.ini"
COPY scripts/entrypoint.sh /entrypoint.sh
COPY scripts/start-web.sh /usr/local/bin/start-web
RUN chmod 755 /entrypoint.sh /usr/local/bin/start-web

# Apache tourne sans root : tout ce qui doit être écrit va dans /tmp (tmpfs Wings)
# ou dans /home/container. Si jamais le conteneur démarre en root, Apache
# redescend quand même sur l'utilisateur "container".
# PHP_INI_SCAN_DIR : le ":" en tête ajoute /home/container/php aux .ini par
# défaut, pour pouvoir surcharger la config PHP depuis le gestionnaire de fichiers.
ENV USER=container \
    HOME=/home/container \
    APACHE_RUN_USER=container \
    APACHE_RUN_GROUP=container \
    APACHE_RUN_DIR=/tmp/apache2/run \
    APACHE_LOCK_DIR=/tmp/apache2/lock \
    APACHE_PID_FILE=/tmp/apache2/run/apache2.pid \
    APACHE_LOG_DIR=/home/container/logs \
    PHP_INI_SCAN_DIR=":/home/container/php" \
    COMPOSER_HOME=/home/container/.composer \
    SERVER_PORT=8080 \
    DOCUMENT_ROOT=/home/container/www/public

WORKDIR /home/container
STOPSIGNAL SIGWINCH

ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/entrypoint.sh"]
CMD ["start-web"]
