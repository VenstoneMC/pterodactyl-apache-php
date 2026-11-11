#!/bin/bash
# Point d'entrée compatible Pterodactyl : exécute la commande de démarrage du panel
# (variable STARTUP, avec les {{VARIABLES}} remplacées), sinon la commande Docker.

# Conteneur d'installation Wings ("bash /mnt/install/install.sh") ou commande
# explicite : on l'exécute telle quelle, sans lancer le site.
if [ "$#" -gt 0 ] && [ "$1" != "start-web" ]; then
    exec "$@"
fi

cd /home/container || exit 1

if [ -n "${STARTUP:-}" ]; then
    MODIFIED_STARTUP=$(echo -e "${STARTUP}" | sed -e 's/{{/${/g' -e 's/}}/}/g')
    echo -e "\033[1m\033[33mcontainer@pterodactyl~ \033[0m${MODIFIED_STARTUP}"
    # shellcheck disable=SC2086
    eval exec ${MODIFIED_STARTUP}
fi

exec "$@"
