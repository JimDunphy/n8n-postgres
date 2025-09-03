#!/usr/bin/env bash
set -Eeuo pipefail

# Simple wrapper to run the Ansible bootstrap playbook
# Supports: --help and --dry-run (ansible --check --diff)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLAYBOOK_PATH="$SCRIPT_DIR/bootstrap.yml"
ANSIBLE_BIN="${ANSIBLE_BIN:-ansible-playbook}"

usage() {
  cat <<EOF
Usage: $0 [--help] [--dry-run] [ansible-args...]

Runs the Ansible bootstrap playbook that installs/configures host nginx
and (optionally) sets up acme.sh.

Examples:
  $0 -i "your.host.name," -u youruser --become \
     -e @vars.example.yml

  $0 --dry-run -i "your.host.name," -u youruser --become \
     -e @vars.example.yml

Notes:
  - --dry-run adds '--check' and '--diff' to preview changes.
  - Any additional arguments are passed through to ansible-playbook.
  - This script does not modify inventory/vars; provide them via args.
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" || "${1:-}" == "help" ]]; then
  usage
  exit 0
fi

dry_run=false
if [[ "${1:-}" == "--dry-run" ]]; then
  dry_run=true
  shift || true
fi

if ! command -v "$ANSIBLE_BIN" >/dev/null 2>&1; then
  echo "Error: ansible-playbook not found. Install Ansible (pip or system package)." >&2
  exit 1
fi

args=()
if [[ "$dry_run" == true ]]; then
  args+=(--check --diff)
fi

"$ANSIBLE_BIN" "${args[@]}" "$@" "$PLAYBOOK_PATH"

