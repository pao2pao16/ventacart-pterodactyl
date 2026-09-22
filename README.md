# VentaCart on Pterodactyl

Runs a VentaCart store as a Pterodactyl server, the same way the VentaSync ERP
runs (`pao2pao16/ventasync-pterodactyl`). One server is one store.

Two pieces:

| | what | where |
|---|---|---|
| **Runtime image** | PHP 8.4, php-fpm, nginx, composer, git, Node 20. No VentaCart code. | `ghcr.io/pao2pao16/ventacart-yolk:php8.4`, built by Actions for amd64 and arm64 |
| **Egg** | Installs VentaCart into the server and starts it | `egg/egg-ventacart.json` |

## How it runs

Wings gives a server one process, one console and one directory that
survives restarts, `/home/container`. VentaCart needs four processes, so the
one process Wings watches starts all four and keeps them running:

- **nginx** on the server's allocation port
- **php-fpm**
- **the queue worker**, `queue:work` (order emails, notifications)
- **the scheduler**, `schedule:work` (currency rates, stock alerts, courier
  tracking, the sitemap), so no cron is needed

All four write to the console. The server shows as online once the
storefront actually answers, through nginx, PHP, Laravel and the database.

**The console runs artisan.** Type `migrate:status` and it runs
`php artisan migrate:status`. Only artisan: nothing typed there reaches a
shell. Pterodactyl Schedules can send artisan commands the same way. Type
`stop` to shut down.

**Settings are the egg's variables.** They reach Laravel as environment
variables, which it reads ahead of `.env`. The only thing kept in `.env` is
the `APP_KEY` made on the first start.

**The storefront's CSS and JS are built on the server.** The repository does
not commit `public/build`, so the install builds it, and a start rebuilds it
only when the code has changed since. Node's packages are removed after each
build; only the result is kept.

## Every start, and the first one

**Every start:** optionally pull the latest code, rebuild the CSS and JS if
the code changed, discover packages, build Laravel's caches.

**A new database:** run every migration, seed (order statuses, geography,
the default theme, email templates, the essential extensions), then give the
seeded admin the email and password the server was created with. There is
never an `admin` / `password` login.

**A store that has been running:** new migrations are **reported, not run.**
Some of VentaCart's migrations cannot be undone, and a store may owe one-off
commands before them. The console says how many are waiting; read the
release notes, then type `migrate --force`. Set *Migrate on start* to `1`
only on a store where that review is not needed.

## Before the first server

### 1. A token for the repository, while it is private

GitHub, Settings, Developer settings, Fine-grained tokens, Generate:

- **Repository access:** only `pao2pao16/venta`
- **Permissions:** Contents, **Read-only**. Nothing else.

It goes into the egg's *GitHub token* variable, which server users never
see. It is handed to git through the environment, so it is never written
into the server's files. Once the repository is public, leave it empty.

### 2. The image is public

The first run of the `yolk` workflow publishes the image. Then, on GitHub:
your profile, Packages, `ventacart-yolk`, Package settings, **Change visibility
to Public**. Wings then pulls it with no registry credentials.

### 3. A database host the containers can reach

The same one the ERP uses works. Its address must be reachable **from inside
a container**: `127.0.0.1` is the container itself, not the node.

## Install

1. **Admin, Nests, Create New**, name it *VentaCart*.
2. In that nest, **Import Egg**, choose `egg/egg-ventacart.json`.
3. **Admin, Servers, Create New:**
   - **Nest / Egg:** VentaCart / VentaCart
   - **Docker image:** PHP 8.4
   - **Memory:** 1536 MB to begin with (the CSS build needs about 1 GB for a
     minute). **Disk:** 5 GB, more for a large catalogue of photos.
   - **Database limit:** 1
   - **Allocation:** any free port
   - **Variables:** *Admin email*, *Admin password* (12 characters or more),
     the *GitHub token*. Set *Site address* to `http://<node address>:<port>`.
     Leave the database fields empty for now.
   - Untick **Start server when installed**.
4. Wait for the install to finish. The console shows
   `[ventacart-install] Installed.`
5. **The server's Databases tab, New Database.** Then copy its Endpoint,
   name, username and password into **Admin, Servers, the server,
   Startup**. The database settings are admin-only there, so no server user
   sees the password.
6. **Start.** The first start runs every migration and seeds, so give it a
   minute or two. It is ready when the console says `VentaCart is ready`.
7. Open the site address and go to `/admin`. Sign in as **admin** with the
   password set on the server. The email set on the server is the admin's
   address for password resets and notices; the sign-in itself is by username.

## A domain with HTTPS

Wings hands out an address and a port, and nothing more. The Caddy on the
node that fronts the ERP fronts stores too: see `proxy/` in
`ventasync-pterodactyl`. Then set *Site address* to `https://your-domain`
and restart. VentaCart trusts the proxy's forwarded headers, so its links come
out as `https`.

## Updates

- **Update on start = 1:** every start fetches the latest of the branch,
  installs its dependencies and rebuilds the CSS and JS. Migrations still
  follow *Migrate on start*.
- **Reinstall** from the panel does the same on demand, and keeps `.env`,
  uploads and the database.

## Backups

A Pterodactyl backup holds the server's files and **not its database**. The
files it skips on purpose are in `.pteroignore`: dependencies, the built CSS
and JS, and caches, all of which can be rebuilt. Product photos and uploads
live in `storage/app` and are included. The database needs its own backup.

## Changing the image or the egg

- **Image:** edit `yolk/`, push to `main`, and the workflow publishes it.
  Restart servers to pick it up.
- **Egg:** edit `egg/install.sh` or `egg/build-egg.py`, run
  `python3 egg/build-egg.py`, commit the JSON, and import it again over the
  existing egg in the panel.
