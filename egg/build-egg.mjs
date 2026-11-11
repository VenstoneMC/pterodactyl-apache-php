// Génère egg-apache-php-symfony.json à partir de install.sh.
// Usage : node egg/build-egg.mjs
import { readFileSync, writeFileSync } from 'node:fs';

const dir = new URL('.', import.meta.url);
const image = 'ghcr.io/venstonemc/pterodactyl-apache-php';
const script = readFileSync(new URL('install.sh', dir), 'utf8').replace(/\r\n/g, '\n');

const variable = (name, env, description, def, rules, viewable = true) => ({
    name,
    description,
    env_variable: env,
    default_value: def,
    user_viewable: viewable,
    user_editable: viewable,
    rules,
    field_type: 'text',
});

const egg = {
    _comment: 'DO NOT EDIT: FILE GENERATED AUTOMATICALLY BY PTERODACTYL PANEL - PTERODACTYL.IO',
    meta: { version: 'PTDL_v2', update_url: null },
    exported_at: new Date().toISOString().replace(/\.\d{3}Z$/, '+00:00'),
    name: 'Apache + PHP (Symfony)',
    author: 'Limeen@users.noreply.github.com',
    description:
        "Apache 2 + PHP (mod_php) basé sur l'image officielle php:*-apache, reconstruite chaque semaine. " +
        'Composer, git, ffmpeg, extensions gd/intl/opcache/apcu/pdo_sqlite. ' +
        'Clone un dépôt git, sert www/public, mise à jour + migrations au démarrage.',
    features: null,
    docker_images: {
        'PHP 8.4': `${image}:8.4`,
        'PHP 8.5': `${image}:8.5`,
    },
    file_denylist: [],
    startup: 'start-web',
    config: {
        files: '{}',
        startup: JSON.stringify({ done: 'resuming normal operations' }),
        logs: '{}',
        stop: '^C',
    },
    scripts: {
        installation: {
            script,
            container: `${image}:8.4`,
            entrypoint: 'bash',
        },
    },
    variables: [
        variable('Dépôt git', 'GIT_ADDRESS',
            "Adresse HTTPS du dépôt à cloner dans www/. Vide = pas de clonage.",
            'https://github.com/VenstoneMC/venstone-website.git', 'nullable|string|max:255'),
        variable('Branche', 'GIT_BRANCH',
            'Branche à déployer (vide = branche par défaut du dépôt).',
            'main', 'nullable|string|max:100'),
        variable('Utilisateur git', 'GIT_USERNAME',
            'Seulement pour un dépôt privé.',
            '', 'nullable|string|max:100'),
        variable("Jeton d'accès git", 'GIT_ACCESS_TOKEN',
            "Dépôt privé uniquement : jeton GitHub fine-grained en lecture seule (Contents: Read) sur ce seul dépôt. Jamais écrit sur le disque.",
            '', 'nullable|string|max:255'),
        variable('Mise à jour au démarrage', 'AUTO_UPDATE',
            '1 = git pull + composer install à chaque démarrage. 0 = rien.',
            '1', 'required|boolean'),
        variable('Migrations au démarrage', 'RUN_MIGRATIONS',
            '1 = doctrine:migrations:migrate à chaque démarrage (projets Symfony).',
            '1', 'required|boolean'),
        variable('Racine web', 'DOCUMENT_ROOT',
            'Dossier servi par Apache. Ne jamais pointer sur www/ pour un projet Symfony (exposerait .env).',
            '/home/container/www/public', 'required|string|max:191'),
    ],
};

writeFileSync(new URL('egg-apache-php-symfony.json', dir), JSON.stringify(egg, null, 4) + '\n');
console.log('egg/egg-apache-php-symfony.json généré');
