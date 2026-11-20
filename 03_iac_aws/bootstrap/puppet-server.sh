#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# Fixar o nome antes da instalação: o nome integra a identidade TLS.
printf 'preserve_hostname: true\n' > /etc/cloud/cloud.cfg.d/99-bacen-hostname.cfg
hostnamectl set-hostname puppet-server.bacen.test
printf '\n127.0.1.1 puppet-server.bacen.test puppet-server\n' >> /etc/hosts

apt-get update
apt-get install -y puppetserver
systemctl enable --now puppetserver
