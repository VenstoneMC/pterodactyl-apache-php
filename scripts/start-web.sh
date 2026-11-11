#!/bin/bash
# Démarrage du site : mise à jour optionnelle (git pull + composer + migrations),
# puis Apache au premier plan.
#
# Variables (définies par l'egg) :
#   AUTO_UPDATE=1      git pull + composer install à chaque démarrage
#   GIT_BRANCH         branche suivie (défaut : celle déjà en place)
#   GIT_USERNAME / GIT_ACCESS_TOKEN   pour un dépôt privé (jamais écrit sur le disque)
#   RUN_MIGRATIONS=1   doctrine:migrations:migrate à chaque démarrage
#   DEPLOY_COMMANDS    commandes bin/console lancées à chaque démarrage, séparées par ";"
#   SERVER_PORT, DOCUMENT_ROOT
#
# Une fois Apache lancé, chaque ligne tapée dans la console Pterodactyl est
# exécutée comme "php bin/console <ligne>" (ou "composer ...").

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

# Découpe une ligne en arguments (guillemets gérés par xargs, sans passer par un shell)
parse_args() {
    ARGS=()
    mapfile -t ARGS < <(printf '%s' "$1" | xargs printf '%s\n' 2>/dev/null) || return 1
    [ "${#ARGS[@]}" -gt 0 ]
}

# php bin/console <args>, sans interaction (aucune question ne peut bloquer)
console() {
    (cd "$APP_DIR" && php bin/console "$@" --no-interaction </dev/null)
}

if [ -f "$APP_DIR/bin/console" ]; then
    # AssetMapper : fichiers JS/CSS compilés dans public/assets (requis en prod)
    if [ -f "$APP_DIR/importmap.php" ]; then
        info "asset-map:compile..."
        console asset-map:compile >/dev/null || warn "asset-map:compile a échoué."
    fi

    # Commandes de déploiement de l'egg, séparées par des ";"
    IFS=';' read -ra DEPLOY_LIST <<< "${DEPLOY_COMMANDS:-}"
    for cmd in "${DEPLOY_LIST[@]}"; do
        cmd="${cmd#"${cmd%%[![:space:]]*}"}"; cmd="${cmd%"${cmd##*[![:space:]]}"}"
        [ -z "$cmd" ] && continue
        if parse_args "$cmd"; then
            info "bin/console ${cmd}"
            console "${ARGS[@]}" || warn "« ${cmd} » a échoué."
        fi
    done
fi

if [ -f "$APP_DIR/bin/console" ] && [ ! -f "$APP_DIR/.env.local" ] && [ ! -f "$APP_DIR/.env.local.php" ]; then
    warn "pas de www/.env.local : le site risque de tourner en APP_ENV=dev !"
fi

if [ ! -d "$DOCUMENT_ROOT" ]; then
    warn "DocumentRoot $DOCUMENT_ROOT introuvable."
fi

cd /home/container || exit 1
info "PHP $(php -r 'echo PHP_VERSION;') - Apache sur le port ${SERVER_PORT}"
apache2 -DFOREGROUND &
APACHE_PID=$!
trap 'kill -TERM "$APACHE_PID" 2>/dev/null' INT TERM

console_help() {
    info "Console : tape une commande Symfony, elle est lancée avec php bin/console."
    echo "  ex. venstone:guide:import    venstone:rules:import --force --book=rules"
    echo "      venstone:skins:import    cache:clear    list venstone"
    echo "  composer <args> fonctionne aussi. Les commandes ne peuvent pas poser de question."
}

# Console Pterodactyl : chaque ligne tapée devient une commande bin/console
handle_line() {
    local line="$1"
    line="${line#"${line%%[![:space:]]*}"}"; line="${line%"${line##*[![:space:]]}"}"
    line="${line#php }"; line="${line#bin/console }"; line="${line#./bin/console }"
    [ -z "$line" ] && return
    if [ "$line" = "help" ] || [ "$line" = "aide" ]; then console_help; return; fi
    if [ ! -f "$APP_DIR/bin/console" ] && [[ "$line" != composer* ]]; then
        warn "pas de bin/console dans www/."; return
    fi
    if ! parse_args "$line"; then warn "commande illisible (guillemet non fermé ?)."; return; fi
    echo -e "\033[1;36m>\033[0m ${line}"
    local rc
    if [ "${ARGS[0]}" = "composer" ]; then
        (cd "$APP_DIR" && composer "${ARGS[@]:1}" --no-interaction </dev/null); rc=$?
    else
        console "${ARGS[@]}"; rc=$?
    fi
    [ "$rc" -eq 0 ] && info "terminé" || warn "code de sortie ${rc}"
}

[ -f "$APP_DIR/bin/console" ] && console_help

while kill -0 "$APACHE_PID" 2>/dev/null; do
    if IFS= read -r -t 2 line; then
        handle_line "$line"
    elif [ $? -le 128 ]; then
        # Entrée fermée (pas de console attachée) : on attend juste Apache
        break
    fi
done
# wait est interrompu par les signaux : on boucle jusqu'à l'arrêt réel d'Apache
rc=0
while kill -0 "$APACHE_PID" 2>/dev/null; do wait "$APACHE_PID"; rc=$?; done
exit "$rc"
