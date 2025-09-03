# Ansible: Host Nginx + acme.sh for n8n

These playbooks install the latest nginx (from the official upstream repos), deploy a templated server block for n8n, install acme.sh for the connecting user (non-root, via the online installer which also configures user crontab for renewals), place your custom `nginx` deploy hook, and optionally issue/deploy certificates using DNS validation.

Supports Ubuntu 22.04 (Jammy) and RHEL 9.

## Files

- `nginx.yml` — nginx install + config
- `acme.yml` — acme.sh install + optional issuance/deploy
- `bootstrap.yml` — imports `nginx.yml` then `acme.yml`
- `migrate.yml` — export from `source` and import to `target` hosts
- `templates/n8n.conf.j2` — nginx vhost template (Jinja)
- `vars.example.yml` — example variables

Relies on repo paths for:

- `files/includes/ssl.conf` — included from the vhost
- `files/acme.sh/deploy/nginx.sh` — custom acme.sh deploy hook (installed to `~/.acme.sh/deploy/nginx.sh`)

## Variables (common)

- `primary_domain`: main domain, e.g., `n8n.example.com`
- `alt_domains`: list of additional domains, e.g., `["www.example.com"]`
- `n8n_upstream`: where nginx proxies, e.g., `127.0.0.1:5678`
- `acme_install_dir`: acme.sh home, default `~/.acme.sh` for the remote user
- `acme_dns_provider`: acme.sh DNS provider (e.g., `dns_cf`)
- `acme_challenge_alias`: optional CNAME target for `_acme-challenge`
- `acme_account_email`: optional email for acme.sh account
- `acme_env_vars`: dict of env vars required by your DNS provider (e.g., Cloudflare token)
- `acme_issue_deploy`: boolean; default `false`. When `true`, the playbook issues and deploys a cert. When `false`, it skips issuance/deploy so you can bring existing certs or just test nginx install.

See `vars.example.yml` for a starter.

## Run

Helper script (wrapper)

From repo root:

```bash
./nginx/manage.sh --help

# Dry-run (preview changes):
./nginx/manage.sh --dry-run -i "your.host.name," -u youruser --become -e @nginx/vars.example.yml

# Apply changes:
./nginx/manage.sh -i "your.host.name," -u youruser --become -e @nginx/vars.example.yml
```

Inline inventory note: the trailing comma in `-i "your.host.name,"` tells Ansible this is an inline host list, not a path to an inventory file. Without the comma, Ansible would try to read an inventory file named `your.host.name`.

Direct via ansible-playbook (inventory-less single host):

```bash
ansible-playbook -i "your.host.name," -u youruser --become \
  -e @nginx/vars.example.yml \
  nginx/bootstrap.yml
```

Or specify vars inline:

```bash
ansible-playbook -i "your.host.name," -u youruser --become nginx/bootstrap.yml \
  -e primary_domain=n8n.example.com \
  -e alt_domains='["www.example.com"]' \
  -e acme_dns_provider=dns_cf \
  -e acme_env_vars='{"CF_Token":"...","CF_Account_ID":"..."}'

# To enable issuance/deploy in a run, set:
#   -e acme_issue_deploy=true

```

## Migration (export/import)

The `migrate.yml` playbook contains two plays: one for the `source` host to create a bundle, and one for the `target` host to restore it. You can optionally have the export play scp the bundle to the target.

Inventory example:

```ini
[source]
src-host.example.com

[target]
tgt-host.example.com
```

Run export (stops stack, bundles, optional transfer):

```bash
ansible-playbook -i inventory -u youruser --become nginx/migrate.yml \
  -l source \
  -e project_dir_source=~/n8n \
  -e stop_before_export=true \
  -e start_after_export=false \
  -e perform_transfer=true \
  -e target_host=tgt-host.example.com \
  -e target_ssh_user=youruser \
  -e target_receive_dir=~ \
  -e bundle_name=export-$(date +%Y%m%d%H%M%S)
```

Then run import on the target (uses the same bundle_name):

```bash
ansible-playbook -i inventory -u youruser --become nginx/migrate.yml \
  -l target \
  -e project_dir_target=~/n8n \
  -e target_receive_dir=~ \
  -e bundle_name=export-20240902T120000  # <-- use the actual value used in export
```


Notes:

- For a clone (keep source running), set `-e stop_before_export=false`. Consistency may vary; for a fully consistent DB state, stop before export or substitute a `pg_dump` process.
- The export includes: `compose.yml`, `.env`, `manage.sh`, `README.md`, and optionally `nginx/` and `local-files/` if present.
- Volumes are captured via tarballs of `n8n-data` and `postgres-data` using a temporary busybox container.
- Alternatively, you can use the project’s `manage.sh` bundle flow on a single host (create the bundle with `--export-bundle`, transfer it yourself, and restore with `--import-bundle`). This is OS-agnostic and simple for manual migrations.


## What it does

1. Adds the official nginx repo and installs latest nginx
2. Creates `/etc/nginx/includes` and `/etc/nginx/ssl/<domain>/`
3. Copies `ssl.conf` and renders `conf.d/<domain>.conf`
4. Installs acme.sh to the remote user’s home (`~/.acme.sh`) and sets up user-level cron renewals (acme.yml)
5. Installs your `deploy/nginx.sh` hook to `~/.acme.sh/deploy/` (acme.yml)
6. Optionally issues a cert for all configured domains using DNS validation (acme.yml)
7. Optionally deploys the cert to `/etc/nginx/ssl/<domain>/` and reloads nginx (acme.yml)

Notes:

- The DNS provider credentials and challenge alias are provided via vars. This playbook doesn’t manage your DNS records beyond what acme.sh does for the selected provider.
- The deploy hook copies certs into `/etc/nginx/ssl/<domain>/` and reloads nginx. The playbook creates this domain directory owned by the remote user so acme.sh can write from user cron. Parent directories remain root-owned.

## Run individual plays

- Only nginx setup:

```bash
ansible-playbook -i "your.host.name," -u youruser --become nginx/nginx.yml \
  -e primary_domain=n8n.example.com -e alt_domains='[]'
```

- Only acme.sh (no issuance/deploy):

```bash
ansible-playbook -i "your.host.name," -u youruser --become nginx/acme.yml \
  -e primary_domain=n8n.example.com -e alt_domains='[]'
```

- Only acme.sh with issuance/deploy enabled:

```bash
ansible-playbook -i "your.host.name," -u youruser --become nginx/acme.yml \
  -e primary_domain=n8n.example.com -e alt_domains='[]' \
  -e acme_dns_provider=dns_cf \
  -e acme_env_vars='{"CF_Token":"...","CF_Account_ID":"..."}' \
  -e acme_issue_deploy=true
```
