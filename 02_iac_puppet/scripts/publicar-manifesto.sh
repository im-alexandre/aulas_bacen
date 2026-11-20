#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Uso: bash $0 IP_DO_SERVIDOR" >&2
  exit 1
fi

manifest="$(dirname "$0")/../puppet/manifests/nginx.pp"
target="ubuntu@$1"
ssh_options=()
if [[ -n "${SSH_PRIVATE_KEY:-}" ]]; then
  ssh_options=(-i "$SSH_PRIVATE_KEY")
fi

ssh "${ssh_options[@]}" "$target" 'sudo cloud-init status --wait'
ssh "${ssh_options[@]}" "$target" \
  'tmp=$(mktemp); trap "rm -f $tmp" EXIT; cat > "$tmp"; sudo puppet parser validate "$tmp" && sudo install -m 0644 "$tmp" /etc/puppet/code/environments/production/manifests/site.pp' < "$manifest"
