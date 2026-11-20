#!/usr/bin/env bash
set -euo pipefail

controller_ip=$1
rules=/etc/puppet-ansible-agent.nft
temporary_rules=$(mktemp)
trap 'rm -f "$temporary_rules"' EXIT

cat > "$temporary_rules" <<RULES
#!/usr/sbin/nft -f
add table inet puppet_ansible_agent
flush table inet puppet_ansible_agent

table inet puppet_ansible_agent {
  chain input {
    type filter hook input priority filter; policy drop;
    iifname "lo" accept
    ct state established,related accept
    udp sport 67 udp dport 68 accept
    ip saddr $controller_ip tcp dport 22 accept
  }
}
RULES

nft --check --file "$temporary_rules"
install -m 0644 "$temporary_rules" "$rules"
cat > /etc/systemd/system/puppet-ansible-agent-firewall.service <<'UNIT'
[Unit]
Description=Firewall do agente Puppet e Ansible
DefaultDependencies=no
After=local-fs.target nftables.service
Before=network-pre.target shutdown.target
Wants=network-pre.target
Conflicts=shutdown.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/nft --file /etc/puppet-ansible-agent.nft
RemainAfterExit=yes

[Install]
WantedBy=sysinit.target
UNIT
systemctl daemon-reload
systemctl enable puppet-ansible-agent-firewall.service
systemctl restart puppet-ansible-agent-firewall.service
