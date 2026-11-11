#!/bin/bash
# Démarrage du site : mise à jour optionnelle (git pull + composer + migrations),
# puis Apache au premier plan.
#
# Variables (définies par l'egg) :
#   AUTO_UPDATE=1      git pull + composer install à chaque démarrage
#   GIT_BRANCH         branche suivie (défaut : celle déjà en place)
#   GIT_USERNAME / GIT_ACCESS_TOKEN   pour un dépôt privé (jamais écrit sur le disque)
#   RUN_MIGRATIONS=1   doctrine:migrations:migrate à chaque démarrage
#   SERVER_PORT, DOCUMENT_ROOT

APP_DIR=/home/container/www
# Jamais de demande interactive (identifiants) : échouer tout de suite
export GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/bin/false
info() { echo -e "\033[1;36m[web]\033[0m $*"; }
warn() { echo -e "\033[1;33m[web] ATTENTION :\033[0m $*"; }

mkdir -p "$APACHE_RUN_DIR" "$APACHE_LOCK_DIR" /home/container/logs \
         /home/container/tmp/sessions /home/container/php
rm -f "$APACHE_PID_FILE"

git_auth() {
    # En-tête d'authentification passé à la volée : le jeton ne finit pas dans .git/config
    if [ -n "${GIT_ACCESS_TOKEN:-}" ]; then
        local basic
        basic=$(printf '%s:%s' "${GIT_USERNAME:-x-access-token}" "$GIT_ACCESS_TOKEN" | base64 -w0)
        git -c "http.extraHeader=Authorization: Basic ${basic}" "$@"
    else
        git "$@"
    fi
}

if [ "${AUTO_UPDATE:-0}" = "1" ] && [ -d "$APP_DIR/.git" ]; then
    cd "$APP_DIR" || exit 1
    info "Mise à jour du code (git pull)..."
    if [ -n "${GIT_BRANCH:-}" ] && [ "$(git rev-parse --abbrev-ref HEAD)" != "$GIT_BRANCH" ]; then
        git_auth fetch origin "$GIT_BRANCH" && git checkout "$GIT_BRANCH"
    fi
    if git_auth pull --ff-only; then
        info "Code à jour : $(git log -1 --format='%h %s')"
    else
        warn "git pull a échoué (modifications locales ?). On démarre avec la version actuelle."
    fi
fi

if [ "${AUTO_UPDATE:-0}" = "1" ] && [ -f "$APP_DIR/composer.json" ]; then
    cd "$APP_DIR" || exit 1
    info "composer install..."
    composer install --no-dev --optimize-autoloader --classmap-authoritative \
        --no-interaction --no-progress \
        || warn "composer install a échoué, voir ci-dessus."
fi

if [ "${RUN_MIGRATIONS:-0}" = "1" ] && [ -f "$APP_DIR/bin/console" ]; then
    cd "$APP_DIR" || exit 1
    info "Migrations Doctrine..."
    php bin/console doctrine:migrations:migrate --no-interaction --allow-no-migration \
        || warn "Les migrations ont échoué, voir ci-dessus."
fi

if [ -f "$APP_DIR/bin/console" ] && [ ! -f "$APP_DIR/.env.local" ] && [ ! -f "$APP_DIR/.env.local.php" ]; then
    warn "pas de www/.env.local : le site risque de tourner en APP_ENV=dev !"
fi

if [ ! -d "$DOCUMENT_ROOT" ]; then
    warn "DocumentRoot $DOCUMENT_ROOT introuvable."
fi

cd /home/container || exit 1
info "PHP $(php -r 'echo PHP_VERSION;') - Apache sur le port ${SERVER_PORT}"
exec apache2 -DFOREGROUND
