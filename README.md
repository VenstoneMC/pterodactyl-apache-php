# pterodactyl-apache-php

Image Docker **Apache + PHP (mod_php)** et egg Pterodactyl pour héberger le site Symfony de Venstone.

- Basée sur l'image officielle `php:<version>-apache` (Debian), **reconstruite chaque lundi** par
  GitHub Actions : les correctifs de sécurité PHP et Debian arrivent sans rien faire.
- Tags : `ghcr.io/venstonemc/pterodactyl-apache-php:8.4` et `:8.5`.
- Inclus : Composer 2, git, ffmpeg, extensions `gd intl opcache apcu zip pdo_sqlite mbstring fileinfo`.
- Tourne en utilisateur non-root (uid 988), sert `www/public`, refuse les fichiers cachés (`.env`, `.git`),
  `expose_php=Off`, `ServerTokens Prod`, aucune erreur PHP affichée aux visiteurs.

## Arborescence du serveur Pterodactyl

```
/home/container
├── www/            le dépôt git du site (DocumentRoot = www/public)
│   ├── .env.local  généré à l'installation (APP_ENV=prod, APP_SECRET aléatoire) — à compléter
│   └── storage/    données hors git (launcher, skins, radio...) — à copier en SFTP
├── logs/access.log journal d'accès (rotation 5 x 10 Mo) ; les erreurs vont dans la console
├── php/            *.ini pour surcharger la config PHP sans reconstruire l'image
└── tmp/sessions/   sessions PHP (survivent aux redémarrages)
```

## Démarrage (`start-web`)

1. `AUTO_UPDATE=1` : `git pull --ff-only` puis `composer install --no-dev` (cache vidé par les scripts Composer).
2. `RUN_MIGRATIONS=1` : `doctrine:migrations:migrate`.
3. Apache au premier plan. Pterodactyl considère le serveur démarré sur « resuming normal operations ».

Un échec de `git pull` / `composer` / migration est signalé dans la console mais n'empêche pas le démarrage.

## Modifier l'egg

Ne pas éditer le JSON à la main : modifier `egg/install.sh` ou `egg/build-egg.mjs`, puis

```bash
node egg/build-egg.mjs
```

## Tester en local

```bash
docker build --build-arg PHP_VERSION=8.4 -t apache-php:test .
```
