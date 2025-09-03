#!/usr/bin/env bash
set -Eeuo pipefail

# Simple manager for the n8n + nginx + postgres compose stack
# Commands aim to be novice-friendly and safe by default.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

COMPOSE_FILE="${COMPOSE_FILE:-compose.yml}"
ENV_FILE="${ENV_FILE:-.env}"

# Detect docker and compose
DOCKER_BIN="${DOCKER_BIN:-docker}"
if "$DOCKER_BIN" compose version >/dev/null 2>&1; then
  COMPOSE_CMD=("$DOCKER_BIN" compose)
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE_CMD=(docker-compose)
else
  echo "Error: Docker Compose not found. Install Docker Desktop or docker-compose plugin." >&2
  exit 1
fi

compose() {
  "${COMPOSE_CMD[@]}" -f "$COMPOSE_FILE" --env-file "$ENV_FILE" "$@"
}

require_file() {
  local f="$1"; local why="$2"
  if [[ ! -f "$f" ]]; then
    echo "Error: Missing $f ($why)" >&2
    exit 1
  fi
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: Missing required command: $1" >&2
    exit 1
  fi
}

usage() {
  cat <<EOF
Usage: $0 [command] [args]

Commands:
  --help                Show this help and exit
  --init                Create external volumes and basic preflight checks
  --doctor              Run preflight checks (Docker, env, nginx config, certs)
  --build               Pull images referenced by compose file
  --start               Start or update stack (up -d)
  --stop                Gracefully stop services
  --down                Stop and remove containers/network (keeps volumes)
  --restart             Restart all services
  --status              Show container status (ps)
  --logs [svc] [-f]     Show logs (all or service)
  --upgrade             Pull latest images, recreate containers, remove orphans
  --console [SVC]       Open interactive shell inside a running service (default: n8n)
  --psql [ARGS...]      Open psql in the postgres service (uses container env by default)
  --exec SVC [CMD...]   Exec into a service (default /bin/sh)
  --export-bundle       Create single-file migration bundle (project + volumes)
  --import-bundle FILE  Restore from bundle (volumes; extract project if absent)

Environment variables:
  COMPOSE_FILE   Path to compose file (default: compose.yml)
  ENV_FILE       Path to env file (default: .env)

Examples:
  $0 --init
  $0 --start
  $0 --logs n8n -f
  $0 --exec n8n
  $0 --export-bundle
  $0 --import-bundle n8n-bundle-2024-09-02-120000.tgz
EOF
}

create_volume_if_missing() {
  local v="$1"
  if ! $DOCKER_BIN volume inspect "$v" >/dev/null 2>&1; then
    echo "Creating volume: $v"
    $DOCKER_BIN volume create "$v" >/dev/null
  else
    echo "Volume already exists: $v"
  fi
}

cmd_init() {
  require_file "$COMPOSE_FILE" "compose stack definition"
  require_file "$ENV_FILE" ".env with configuration"
  require_cmd "$DOCKER_BIN"

  echo "Initializing external volumes..."
  create_volume_if_missing n8n-data
  create_volume_if_missing postgres-data

  echo "Done. Run '$0 --doctor' for an extra sanity check."
}

cmd_doctor() {
  echo "== Preflight checks =="

  # Docker/Compose
  if $DOCKER_BIN info >/dev/null 2>&1; then
    echo "Docker: OK"
  else
    echo "Docker: NOT OK (daemon not reachable)"; exit 1
  fi
  if "${COMPOSE_CMD[@]}" version >/dev/null 2>&1; then
    echo "Compose: OK"
  else
    echo "Compose: NOT OK"; exit 1
  fi

  # Files
  [[ -f "$COMPOSE_FILE" ]] && echo "Compose file: $COMPOSE_FILE (OK)" || { echo "Missing $COMPOSE_FILE"; exit 1; }
  [[ -f "$ENV_FILE" ]] && echo "Env file: $ENV_FILE (OK)" || { echo "Missing $ENV_FILE"; exit 1; }

  # Nginx/Ansible files (collapsed layout: nginx/ contains playbooks; nginx/files contains assets)
  local tpl_file="nginx/templates/n8n.conf.j2"
  local include_file="nginx/files/includes/ssl.conf"
  local deploy_hook="nginx/files/acme.sh/deploy/nginx.sh"
  [[ -f "$tpl_file" ]] && echo "nginx template: OK ($tpl_file)" || echo "nginx template missing: $tpl_file"
  [[ -f "$include_file" ]] && echo "nginx include: OK ($include_file)" || echo "nginx include missing: $include_file"
  [[ -f "$deploy_hook" ]] && echo "acme deploy hook: OK ($deploy_hook)" || echo "acme deploy hook missing: $deploy_hook"

  # Warn if host nginx/apache likely running (port conflicts)
  if command -v systemctl >/dev/null 2>&1; then
    if systemctl is-active --quiet nginx; then
      echo "Warning: Host nginx service is active; it may block ports 80/443."
    fi
    if systemctl is-active --quiet apache2; then
      echo "Warning: Host apache2 service is active; it may block ports 80/443."
    fi
  fi

  # Check proxy_pass target expectation in template (uses Jinja variable)
  if rg -n "proxy_pass\s+http://\{\{\s*n8n_upstream\s*\}\}" "$tpl_file" >/dev/null 2>&1; then
    echo "nginx template proxy uses n8n_upstream variable (OK)"
  else
    echo "Warning: nginx template may not proxy via n8n_upstream variable: $tpl_file"
  fi

  # Optional: Check if SSL dir exists in project assets (not required if ACME deploys directly to host)
  if [[ -d "nginx/files/ssl" ]]; then
    echo "nginx/files/ssl directory present (optional)"
  fi

  echo "Doctor checks complete."
}

cmd_build() { # pull images
  require_file "$COMPOSE_FILE" "compose stack definition"
  require_file "$ENV_FILE" ".env with configuration"
  compose pull
}

cmd_start() {
  require_file "$COMPOSE_FILE" "compose stack definition"
  require_file "$ENV_FILE" ".env with configuration"
  compose up -d --remove-orphans
  compose ps
}

cmd_stop() {
  require_file "$COMPOSE_FILE" "compose stack definition"
  require_file "$ENV_FILE" ".env with configuration"
  compose stop
}

cmd_down() {
  require_file "$COMPOSE_FILE" "compose stack definition"
  require_file "$ENV_FILE" ".env with configuration"
  compose down
}

cmd_restart() {
  require_file "$COMPOSE_FILE" "compose stack definition"
  require_file "$ENV_FILE" ".env with configuration"
  compose restart
  compose ps
}

cmd_status() {
  require_file "$COMPOSE_FILE" "compose stack definition"
  require_file "$ENV_FILE" ".env with configuration"
  compose ps
}

cmd_logs() {
  require_file "$COMPOSE_FILE" "compose stack definition"
  require_file "$ENV_FILE" ".env with configuration"
  if [[ $# -gt 0 ]]; then
    compose logs "$@"
  else
    compose logs -f --tail=100
  fi
}

cmd_upgrade() {
  require_file "$COMPOSE_FILE" "compose stack definition"
  require_file "$ENV_FILE" ".env with configuration"
  echo "Pulling images..."
  compose pull
  echo "Recreating containers..."
  compose up -d --remove-orphans
  echo "Pruning unused images..."
  $DOCKER_BIN image prune -f >/dev/null || true
  compose ps
}

cmd_exec() {
  require_file "$COMPOSE_FILE" "compose stack definition"
  require_file "$ENV_FILE" ".env with configuration"
  local service="${1:-}"
  shift || true
  if [[ -z "$service" ]]; then
    echo "Usage: $0 --exec SERVICE [COMMAND...]" >&2
    exit 1
  fi
  if [[ $# -gt 0 ]]; then
    compose exec -it "$service" "$@"
  else
    compose exec -it "$service" /bin/sh
  fi
}

cmd_console() {
  require_file "$COMPOSE_FILE" "compose stack definition"
  require_file "$ENV_FILE" ".env with configuration"
  local service="${1:-n8n}"

  # Ensure the service container is running
  local cid
  cid=$(compose ps -q "$service" || true)
  if [[ -z "$cid" ]]; then
    echo "Service '$service' is not running. Start the stack with './manage.sh --start' then retry." >&2
    exit 1
  fi

  # Prefer bash if available; fall back to sh
  if compose exec -it "$service" /bin/bash -c 'exit 0' >/dev/null 2>&1; then
    compose exec -it "$service" /bin/bash
  else
    compose exec -it "$service" /bin/sh
  fi
}

cmd_psql() {
  require_file "$COMPOSE_FILE" "compose stack definition"
  require_file "$ENV_FILE" ".env with configuration"

  # Ensure postgres is running
  local cid
  cid=$(compose ps -q postgres || true)
  if [[ -z "$cid" ]] || ! $DOCKER_BIN inspect -f '{{.State.Running}}' "$cid" 2>/dev/null | grep -q true; then
    echo "Service 'postgres' is not running. Start the stack with './manage.sh --start' then retry." >&2
    exit 1
  fi

  if [[ $# -gt 0 ]]; then
    # Pass through explicit psql args provided by the user
    compose exec -it postgres psql "$@"
  else
    # Use container env vars for defaults
    if compose exec -it postgres bash -lc 'psql -U "$POSTGRES_USER" "$POSTGRES_DB"' >/dev/null 2>&1; then
      compose exec -it postgres bash -lc 'psql -U "$POSTGRES_USER" "$POSTGRES_DB"'
    else
      compose exec -it postgres sh -lc 'psql -U "$POSTGRES_USER" "$POSTGRES_DB"'
    fi
  fi
}

cmd_export_bundle() {
  require_file "$COMPOSE_FILE" "compose stack definition"
  require_file "$ENV_FILE" ".env with configuration"

  # Output file
  local out=""
  if [[ "${1:-}" == "--out" ]]; then
    shift || true
    out="${1:-}"
    shift || true
  fi
  local ts
  ts=$(date +%F-%H%M%S)
  local tmpdir="export-${ts}"
  local bundle="${out:-n8n-bundle-${ts}.tgz}"

  echo "Creating export workspace: $tmpdir"
  mkdir -p "$tmpdir"

  echo "Bundling project files..."
  local files=(compose.yml "$ENV_FILE" manage.sh README.md)
  [[ -d nginx ]] && files+=(nginx)
  [[ -d local-files ]] && files+=(local-files)
  tar czf "$tmpdir/project.tgz" "${files[@]}" 2>/dev/null || true

  echo "Snapshotting volumes (n8n-data, postgres-data)..."
  docker run --rm -v n8n-data:/data -v "$PWD/$tmpdir":/backup busybox \
    tar czf /backup/n8n-data.tgz -C /data .
  docker run --rm -v postgres-data:/data -v "$PWD/$tmpdir":/backup busybox \
    tar czf /backup/postgres-data.tgz -C /data .

  echo "Creating single bundle: $bundle"
  tar czf "$bundle" "$tmpdir"

  echo "Cleaning up workspace"
  rm -rf "$tmpdir"

  echo "Bundle created: $bundle"
  echo "Transfer this file to the target and run: $0 --import-bundle $bundle"
}

cmd_import_bundle() {
  local bundle_path="${1:-}"
  if [[ -z "$bundle_path" ]]; then
    echo "Usage: $0 --import-bundle PATH_TO_BUNDLE.tgz [--start] [--force-extract]" >&2
    exit 1
  fi
  shift || true
  local start_after=false
  local force_extract=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --start) start_after=true ;;
      --force-extract) force_extract=true ;;
    esac
    shift || true
  done

  if [[ ! -f "$bundle_path" ]]; then
    echo "Error: bundle not found: $bundle_path" >&2
    exit 1
  fi

  local tmpdir
  tmpdir=$(mktemp -d -t n8n-import-XXXXXX)
  echo "Extracting bundle to: $tmpdir"
  tar xzf "$bundle_path" -C "$tmpdir"

  # Find inner export directory (export-YYYY-...)
  local inner
  inner=$(find "$tmpdir" -maxdepth 1 -mindepth 1 -type d | head -n1)
  if [[ -z "$inner" ]]; then
    echo "Error: bundle is missing inner export directory" >&2
    exit 1
  fi

  # Restore volumes
  echo "Creating docker volumes if missing..."
  docker volume inspect n8n-data >/dev/null 2>&1 || docker volume create n8n-data >/dev/null
  docker volume inspect postgres-data >/dev/null 2>&1 || docker volume create postgres-data >/dev/null

  echo "Restoring n8n-data volume..."
  docker run --rm -v n8n-data:/data -v "$inner":/backup busybox \
    sh -c "cd /data && tar xzf /backup/n8n-data.tgz"

  echo "Restoring postgres-data volume..."
  docker run --rm -v postgres-data:/data -v "$inner":/backup busybox \
    sh -c "cd /data && tar xzf /backup/postgres-data.tgz"

  # Extract project files if compose.yml not present or forced
  if [[ ! -f "$COMPOSE_FILE" || "$force_extract" == true ]]; then
    echo "Extracting project files into $(pwd)"
    tar xzf "$inner/project.tgz" -C .
  else
    echo "compose.yml exists; skipping project extraction. Use --force-extract to override."
  fi

  rm -rf "$tmpdir"

  if [[ "$start_after" == true ]]; then
    cmd_start
  else
    echo "Import complete. Review project files, then start with: $0 --start"
  fi
}

main() {
  local cmd="${1:---help}"
  shift || true
  case "$cmd" in
    --help|-h|help) usage ;;
    --init) cmd_init ;;
    --doctor) cmd_doctor ;;
    --build) cmd_build ;;
    --start|up) cmd_start ;;
    --stop) cmd_stop ;;
    --down) cmd_down ;;
    --restart) cmd_restart ;;
    --status|ps) cmd_status ;;
    --logs) cmd_logs "$@" ;;
    --upgrade) cmd_upgrade ;;
    --console) cmd_console "$@" ;;
    --psql) cmd_psql "$@" ;;
    --exec) cmd_exec "$@" ;;
    --export-bundle) cmd_export_bundle "$@" ;;
    --import-bundle) cmd_import_bundle "$@" ;;
    *) echo "Unknown command: $cmd" >&2; echo; usage; exit 1 ;;
  esac
}

main "$@"
