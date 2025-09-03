# n8n + Postgres (compose.yml) with Host Nginx

This repository provides a Docker Compose stack for running n8n with a PostgreSQL database, intended to sit behind a host‑level nginx reverse proxy you already manage. It’s designed to be novice‑friendly, resilient, and explicit about where data is stored so upgrades and restarts do not lose data.

## What’s Included

- n8n: Workflow automation server (published only on loopback; proxied by host nginx)
- postgres: Database for n8n
- compose.yml: The improved Compose file for this stack
- .env: Central configuration, including timezone and n8n settings
- manage.sh: Helper script to init, start, stop, upgrade, check, and inspect the stack
- nginx/: Host nginx config, includes, and TLS files you deploy to the server (not mounted by Compose)

## Services (Containers)

- `n8n` (container name: `n8n`): Listens on `5678` in-container, bound to host loopback (`127.0.0.1:${N8N_PORT:-5678}`), persisted data in `n8n-data` volume.
- `postgres` (container name: `postgres`): Internal only (no host port), healthchecked, data in `postgres-data` volume.

Check status: `./manage.sh --status` (both should be running and healthy after start).

## Prerequisites

- Docker Engine + Docker Compose plugin
- DNS A/AAAA records for your domain pointing to the host
- Host nginx installed and configured (you can use the files under `nginx/` as your source of truth)
- TLS cert and key present under `nginx/ssl/<your-domain>/` (or use your ACME workflow to populate them)

## Quick Start

1) Copy env.txt to `.env` and edit

- Copy: `cp env.txt .env`
- Set `GENERIC_TIMEZONE` (e.g., `America/Vancouver`)
- Set `DOMAIN`, `N8N_ENCRYPTION_KEY`, and strong passwords
- Ensure n8n URLs match your domain:
  - `WEBHOOK_URL=https://${DOMAIN}`
  - `N8N_HOST=${DOMAIN}`
  - `N8N_PROTOCOL=https`

2) Configure host nginx via Ansible

- Use the playbooks in `nginx/` to install and configure nginx.
- Example (inventory-less):
  - `ansible-playbook -i "your.host.name," -u youruser --become -e @nginx/vars.example.yml nginx/bootstrap.yml`
- Ensure variables reflect your domain(s):
  - `primary_domain`, optional `alt_domains`, and `n8n_upstream: 127.0.0.1:5678`

3) Initialize and start

```bash
./manage.sh --init      # creates persistent volumes
./manage.sh --doctor    # optional preflight checks
./manage.sh --start     # starts the stack
./manage.sh --logs -f   # follow logs
```

## CLI Reference: manage.sh

All commands preserve data. Persistent state lives in Docker volumes `n8n-data` and `postgres-data`.

Commands

- `--help`: Show usage and exit.
- `--init`: Create external volumes (`n8n-data`, `postgres-data`) and run basic checks.
- `--doctor`: Preflight checks for Docker/Compose, `.env`, and required nginx/acme assets.
- `--build`: Pull images referenced by `compose.yml` (no local Dockerfile build).
- `--start` (alias `up`): Start or update the stack (`up -d`). Creates network/containers if missing.
- `--stop`: Gracefully stop containers. Keeps containers and network. Volumes untouched.
- `--down`: Stop and remove containers and the compose network. Volumes untouched.
- `--restart`: Restart all services. Equivalent to stop then start.
- `--status` (alias `ps`): Show container status.
- `--logs [svc] [-f]`: Show logs (all services by default, or a single service). `-f` to follow.
- `--upgrade`: Pull latest images, recreate containers, remove orphans; data preserved.
- `--console [svc]`: Open an interactive shell in a running service (default `n8n`). No ports exposed.
- `--psql [args]`: Open `psql` inside the `postgres` service. With no args, uses the container’s `POSTGRES_USER` and `POSTGRES_DB`. Pass standard `psql` args to override.
- `--exec SVC [CMD...]`: Exec into a service (default `/bin/sh` if no command).
- `--export-bundle [--out FILE]`: Create a single-file bundle of the project and volume snapshots.
- `--import-bundle FILE [--start] [--force-extract]`: Restore volumes, optionally extract project, then optionally start.

Environment variables

- `COMPOSE_FILE`: Path to compose file (default `compose.yml`).
- `ENV_FILE`: Path to env file (default `.env`).

Stop vs Down

- `--stop`: Stops containers only. Faster resume; network and containers remain. Data volumes never touched.
- `--down`: Stops and removes containers and the compose-created network. Data volumes remain and are reattached on next start.

Data safety

- Volumes are declared as `external: true` and are never removed by any `manage.sh` command.
- Destructive actions require explicit Docker commands (e.g., `docker volume rm n8n-data postgres-data`, `docker compose down -v`, or `docker system prune --volumes`) and are not used by this script.

Examples

```bash
# Pull images explicitly (optional; --start will also fetch if needed)
./manage.sh --build

# Restart stack after changing .env
./manage.sh --restart

# Exec into n8n container
./manage.sh --exec n8n /bin/sh

# Open a console (defaults to n8n)
./manage.sh --console

# Open a console in postgres container
./manage.sh --console postgres

# Open psql in postgres (uses container env)
./manage.sh --psql

# Or specify args (db/user/etc.)
./manage.sh --psql -U n8n n8n

# Create and restore a migration bundle
./manage.sh --export-bundle
./manage.sh --import-bundle n8n-bundle-YYYY-MM-DD-HHMMSS.tgz --start
```

## Timezone

- Set `GENERIC_TIMEZONE` in `.env` (e.g., `America/Vancouver`).
- The Compose stack passes this to containers as `TZ` for OS-level time, and n8n also reads `GENERIC_TIMEZONE` from `.env`.

## Networking

- n8n publishes: `127.0.0.1:${N8N_PORT:-5678} -> 5678` (loopback only)
- postgres is internal only (no host port exposure)
- Host nginx listens on 80/443 and proxies to `http://127.0.0.1:5678`

## Persistence and Where Data Lives

This stack uses one bind mount for convenience plus named Docker volumes for persistence.

- Bind mount:
  - `./local-files    → /files` (optional workspace for imports/exports)

- Named volumes (Docker-managed, persistent across restarts/upgrades):
  - Volume `n8n-data` → `/home/node/.n8n` (n8n data)
    - Host path: `/var/lib/docker/volumes/n8n-data/_data`
  - Volume `postgres-data` → `/var/lib/postgresql/data` (database files)
    - Host path: `/var/lib/docker/volumes/postgres-data/_data`

Notes:

- Compared to an older `docker-compose.yml` you may have used that created a default volume like `n8n_data`, this stack uses explicitly named volumes (`n8n-data`, `postgres-data`). They are still stored under `/var/lib/docker/volumes/<name>/_data` and persist until explicitly removed.
- The volumes are declared as `external: true` in `compose.yml`, and `./manage.sh --init` creates them for you.
- The `nginx/` folder here is for managing host nginx configuration and certs; Compose does not mount it.

## Backups

Fast snapshot (filesystem-level):

```bash
# n8n data
docker run --rm -v n8n-data:/data -v "$PWD":/backup busybox \
  tar czf /backup/n8n-data-$(date +%F).tgz -C /data .

# postgres data (offline snapshot; stop n8n first for consistency or use pg_dump)
docker run --rm -v postgres-data:/data -v "$PWD":/backup busybox \
  tar czf /backup/postgres-data-$(date +%F).tgz -C /data .
```

Logical DB backup (recommended for consistency):

```bash
# Replace user/db as needed; runs inside the postgres container
docker exec -i postgres pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" > pgdump-$(date +%F).sql
```

## Upgrades and Maintenance

- Upgrade images and recreate containers (data preserved):

```bash
./manage.sh --upgrade
```

- Restart / stop / status:

```bash
./manage.sh --restart
./manage.sh --stop
./manage.sh --status
```

## Robustness

- `restart: unless-stopped` is set for all services so they restart automatically after crashes or host reboots. Leave this enabled for production.
- Healthchecks for n8n and postgres ensure the app is ready before serving traffic.
- n8n is bound to loopback and not directly exposed to the internet; host nginx is the single entry point.

## Troubleshooting

- Port conflicts: If a host-level nginx or apache is running, it may block ports 80/443. Stop those services or change the published ports in `compose.yml`.
- Logs: `./manage.sh --logs -f` (or `--logs n8n`, `--logs postgres`)
- Proxy target: The vhost template proxies to `{{ n8n_upstream }}` (defaults to `127.0.0.1:5678`).
- TLS: When using acme.sh via the playbook, certs are deployed into `/etc/nginx/ssl/<domain>/` on the host.

## Git Hygiene

- `.env` is intentionally git-ignored; keep real secrets out of your repo.
- Use `env.txt` as a safe, shareable sample to onboard others.
- Bundles and export temp directories are also ignored by default.

## Move The Project Folder

You can relocate the project directory (e.g., from `~/n8n` to `/vendor/clients/n8n`) without losing data because persistent data lives in Docker volumes.

Steps on the same host:

```bash
cd /current/path
./manage.sh --stop
mv /current/path /new/path
cd /new/path
./manage.sh --start
```

Notes:
- Named volumes (`n8n-data`, `postgres-data`) remain attached to the host and are independent of the folder path.
- Ensure `./local-files` moved with the project if you use it.
- Host nginx config does not need to change for this move (it proxies to 127.0.0.1:5678).

## Migrate To A New Machine

There are two supported approaches: a one-file bundle via manage.sh (easiest), or manual steps.

Important: Keep the same `.env` (specifically `N8N_ENCRYPTION_KEY`) so n8n can decrypt existing credentials after migration.

### Option A: One-file bundle (recommended)

On the source host, from your project folder:

```bash
# Stop (for consistent DB snapshot)
./manage.sh --stop

# Create a single bundle (contains project + volumes)
./manage.sh --export-bundle
# Output: n8n-bundle-YYYY-MM-DD-HHMMSS.tgz
```

Copy the bundle to the new host and place it in the target project folder, then:

```bash
./manage.sh --import-bundle n8n-bundle-YYYY-MM-DD-HHMMSS.tgz
./manage.sh --start
```

Notes:
- `--import-bundle` auto-creates `n8n-data` and `postgres-data` and restores them.
- If `compose.yml` is already present, project extraction is skipped (use `--force-extract` to overwrite).

### Option B: Manual export/import

1) Stop on the old host

```bash
cd /path/to/your/project
./manage.sh --stop
```

2) Create export folder and project bundle

```bash
EXPORT_DIR=export-$(date +%F)
mkdir -p "$EXPORT_DIR"

# Bundle the project files (compose.yml, env, scripts, nginx configs, optional local files)
tar czf "$EXPORT_DIR/project.tgz" compose.yml .env manage.sh nginx local-files README.md
```

3) Snapshot the volumes (offline, consistent — stack is stopped)

```bash
# n8n data
docker run --rm -v n8n-data:/data -v "$PWD/$EXPORT_DIR":/backup busybox \
  tar czf /backup/n8n-data.tgz -C /data .

# postgres data
docker run --rm -v postgres-data:/data -v "$PWD/$EXPORT_DIR":/backup busybox \
  tar czf /backup/postgres-data.tgz -C /data .
```

4) Transfer to the new host

```bash
scp -r "$EXPORT_DIR" user@new-host:~/
```

5) Restore on the new host

```bash
ssh user@new-host
mkdir -p ~/n8n && cd ~/n8n

# Extract the project bundle
tar xzf ~/export-*/project.tgz

# Create volumes
./manage.sh --init

# Restore volume data into the newly created volumes
docker run --rm -v n8n-data:/data -v "$PWD":/backup busybox \
  sh -c "cd /data && tar xzf /backup/n8n-data.tgz"

docker run --rm -v postgres-data:/data -v "$PWD":/backup busybox \
  sh -c "cd /data && tar xzf /backup/postgres-data.tgz"
```

6) Verify configs and domain

- Host nginx vhost was rendered with your `primary_domain`/`alt_domains` and proxies to `127.0.0.1:5678`.
- `.env` has correct `DOMAIN`, `WEBHOOK_URL`, `N8N_HOST`, `N8N_PROTOCOL`, and `GENERIC_TIMEZONE`.
- Update DNS so `n8n.example.com` points to the new host IP.

7) Start the stack and verify

```bash
./manage.sh --start
./manage.sh --logs -f
```

Browse to `https://your-domain` and confirm n8n loads and your workflows/credentials are present.

## About N8N_ENCRYPTION_KEY

- What it is: A symmetric key that n8n uses to encrypt/decrypt credentials stored in the database.
- Why it matters: If this key changes, n8n cannot decrypt existing credentials — they will appear corrupted/unusable.
- Migration rule: Keep the same `N8N_ENCRYPTION_KEY` value in `.env` across upgrades and migrations.
- Generation: Use a strong 32‑byte value, e.g. `openssl rand -base64 32`.
- Storage: Treat it like a secret. Do not commit `.env` publicly. Store in your password manager or secrets vault.

## Optional: Ansible Automation

If you manage multiple hosts or want repeatability, use the Ansible playbooks under `nginx/`:

- `nginx/bootstrap.yml`: Installs nginx and (optionally) issues/deploys certs with acme.sh.
- `nginx/nginx.yml`: Only nginx install + vhost config from template.
- `nginx/acme.yml`: Only acme.sh install and optional issuance/deploy.
- `nginx/migrate.yml`: Export/import the Docker stack across hosts.

Examples are in `nginx/README.md`.
