#!/bin/bash
# Pterodactyl runs this once when the server is installed or reinstalled, as
# root, in a throwaway container with the server's files at /mnt/server.
#
# It fetches VentaCart, its PHP dependencies, and builds the storefront's CSS and
# JS. Everything that needs the database (the key, migrations, the first
# admin) happens on start instead, when the database settings are filled in.

set -euo pipefail

say() { echo "[ventacart-install] $*"; }

: "${GIT_REPO:?GIT_REPO is not set}"
: "${GIT_BRANCH:?GIT_BRANCH is not set}"

cd /mnt/server

# The token is handed to git through its environment, so it is never on a
# command line and never written into .git/config.
if [ -n "${GIT_TOKEN:-}" ]; then
    export GIT_CONFIG_COUNT=1
    export GIT_CONFIG_KEY_0=http.extraHeader
    export GIT_CONFIG_VALUE_0="Authorization: Basic $(printf 'x-access-token:%s' "$GIT_TOKEN" | base64 -w0)"
fi

if [ -d .git ]; then
    say "Existing install found. Moving it to the latest ${GIT_BRANCH}."
    git fetch --depth 1 origin "$GIT_BRANCH"
    git reset --hard FETCH_HEAD
else
    say "Fetching ${GIT_REPO} (${GIT_BRANCH}) ..."
    work=$(mktemp -d)
    git clone --depth 1 --branch "$GIT_BRANCH" "https://github.com/${GIT_REPO}.git" "$work/app"
    cp -a "$work/app/." /mnt/server/
    rm -rf "$work"
fi

unset GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0

say "Installing PHP dependencies ..."
# No scripts: they boot the application, and the database may not be
# reachable yet. Package discovery runs on start instead.
export COMPOSER_ALLOW_SUPERUSER=1 COMPOSER_HOME=/tmp/composer
composer install --no-dev --no-scripts --no-interaction --prefer-dist \
    --optimize-autoloader --no-progress

# Drops the Google API services this store does not use: the package ships
# 640 of them (184 MB) and VentaCart speaks to one. A Composer script, which
# --no-scripts above keeps from running on its own, so it is called here and
# the autoloader is written again over what is left.
# Tolerated, not required: a branch whose composer.json has no such script
# installs fine, it is only bigger.
if composer run-script pre-autoload-dump --no-interaction; then
    say "Trimmed unused dependencies."
    composer dump-autoload --no-dev --optimize --no-scripts --no-interaction
else
    say "No dependency trim in this branch; carrying on."
fi

mkdir -p .runtime/tmp .runtime/nginx \
         storage/framework/cache/data storage/framework/sessions storage/framework/views \
         storage/logs bootstrap/cache

say "Building the storefront's CSS and JS ..."
export npm_config_cache=/tmp/npm npm_config_update_notifier=false
npm ci --no-audit --no-fund --loglevel=error
npm run build
# The build is all that is needed at run time. node_modules is a few hundred
# MB; the cache lives in /tmp here and never reaches the server's disk.
rm -rf node_modules
# Tells the first start this build matches the code, so it is not built twice.
git rev-parse HEAD > .runtime/build-commit

[ -f .env ] || cp .env.example .env

# Kept out of Pterodactyl backups: all of it can be rebuilt. The database is
# not in a Pterodactyl backup at all and needs its own.
cat > .pteroignore <<'IGNORE'
vendor/
node_modules/
public/build/
.runtime/
.cache/
storage/framework/cache/
storage/framework/views/
IGNORE

# Everything written here belongs to root. The server runs as the user that
# owns its directory, so the files are handed to that same owner.
chown -R "$(stat -c '%u:%g' /mnt/server)" /mnt/server

# Printed so the console itself says which install ran and what it left
# behind: a store trimmed of the unused Google services is about 80 MB,
# an untrimmed one about 270 MB.
say "Installed: $(du -sh /mnt/server 2>/dev/null | cut -f1) on disk, vendor $(du -sh /mnt/server/vendor 2>/dev/null | cut -f1), google $(du -sh /mnt/server/vendor/google 2>/dev/null | cut -f1)."
say "Start the server to finish setting it up."
