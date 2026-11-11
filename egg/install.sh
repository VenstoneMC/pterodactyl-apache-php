#!/bin/bash
# Script d'installation de l'egg "Apache + PHP (Symfony)".
# Tourne dans l'image du site (même PHP, composer, git), en root, sur /mnt/server.
# Relançable (Reinstall) : ne supprime jamais www/ ni le .env.local existants.
set -uo pipefail

export HOME=/tmp COMPOSER_HOME=/tmp/composer COMPOSER_ALLOW_SUPERUSER=1
git config --global --add safe.directory '*'

GIT_ADDRESS="${GIT_ADDRESS:-}"
GIT_BRANCH="${GIT_BRANCH:-}"

git_auth() {
    if [ -n "${GIT_ACCESS_TOKEN:-}" ]; then
        local basic
        basic=$(printf '%s:%s' "${GIT_USERNAME:-x-access-token}" "$GIT_ACCESS_TOKEN" | base64 -w0)
        git -c "http.extraHeader=Authorization: Basic ${basic}" "$@"
    else
        git "$@"
    fi
}

cd /mnt/server || exit 1
mkdir -p www logs tmp/sessions php

echo "[SETUP] PHP $(php -r 'echo PHP_VERSION;') / $(composer --version 2>/dev/null | head -n1)"

if [ -d www/.git ]; then
    echo "[SETUP] Dépôt déjà présent : git pull"
    git_auth -C www pull --ff-only || echo "[WARN] git pull a échoué, on garde la version actuelle."
elif [ -n "$GIT_ADDRESS" ]; then
    if [ -n "$(ls -A www)" ]; then
        echo "[SKIP] www/ n'est pas vide et n'est pas un dépôt git : clonage ignoré."
    else
        echo "[SETUP] Clonage de ${GIT_ADDRESS} ${GIT_BRANCH:+(branche ${GIT_BRANCH})}"
        if ! git_auth clone ${GIT_BRANCH:+--branch "$GIT_BRANCH"} "$GIT_ADDRESS" www; then
            echo "[ERREUR] Clonage impossible (adresse, branche ou jeton d'accès ?)."
            exit 1
        fi
    fi
elif [ -z "$(ls -A www)" ]; then
    echo "[SETUP] Pas de dépôt git : page d'attente"
    mkdir -p www/public
    echo '<!doctype html><meta charset="utf-8"><title>Bientôt</title><p>Site en cours de déploiement.</p>' > www/public/index.php
fi

if [ -f www/composer.json ]; then
    cd www || exit 1
    if [ ! -f .env.local ] && [ ! -f .env.local.php ]; then
        echo "[SETUP] Création de www/.env.local (APP_ENV=prod, APP_SECRET aléatoire)"
        cat > .env.local <<EOF
# Généré à l'installation. À compléter (voir README du site, section Déploiement).
APP_ENV=prod
APP_DEBUG=0
APP_SECRET=$(php -r 'echo bin2hex(random_bytes(32));')
# Même valeur que web.secret dans la config du plugin AuthyVenstone
PLUGIN_API_SECRET=
# IP du reverse proxy devant le site, ou REMOTE_ADDR
TRUSTED_PROXIES=
DEFAULT_URI=https://venstone.xyz
EOF
        chmod 600 .env.local
    fi

    echo "[SETUP] composer install (prod)"
    composer install --no-dev --optimize-autoloader --classmap-authoritative --no-interaction --no-progress \
        || echo "[WARN] composer install a échoué : il sera relancé au démarrage si AUTO_UPDATE=1."
    mkdir -p var storage
    cd /mnt/server || exit 1
fi

# Wings remet de toute façon les bons droits au démarrage (check_permissions_on_boot)
chown -R 988:988 /mnt/server 2>/dev/null || true

echo "[DONE] Installation terminée."
