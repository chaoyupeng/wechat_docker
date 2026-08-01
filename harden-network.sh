#!/usr/bin/env bash
# Block the WeChat container from reaching anything on a private network:
# your Mac, your LAN, other VMs, cloud metadata endpoints. Public internet
# still works, because WeChat is useless without it.
#
# Rules live in the Colima VM's iptables and are LOST on `colima stop`.
# Re-run this after every `colima start`.
#
# Usage: ./harden-network.sh [apply|status|clear]

set -euo pipefail
cd "$(dirname "$0")"

# Same source of truth as docker-compose.yml.
[ -f .env ] && set -a && . ./.env && set +a
SUBNET="${WECHAT_SUBNET:-172.30.7.0/24}"

PRIVATE_RANGES=(
  10.0.0.0/8
  172.16.0.0/12
  192.168.0.0/16
  169.254.0.0/16    # link-local + cloud metadata (169.254.169.254)
  100.64.0.0/10     # CGNAT, used by some VPNs/Tailscale
)

require_colima() {
  if ! command -v colima >/dev/null 2>&1; then
    cat >&2 <<'EOF'
This script writes iptables rules inside a Colima VM and colima was not found.

Everything else in this repo works on Docker Desktop or OrbStack, but you will
be missing the egress firewall: by default the container CAN reach your LAN and
your host. Either switch to Colima, or apply equivalent rules to the DOCKER-USER
chain in whatever VM your runtime uses.
EOF
    exit 1
  fi
  colima status >/dev/null 2>&1 || { echo "colima is not running: colima start" >&2; exit 1; }
}

in_vm() { colima ssh -- sudo "$@"; }

clear_rules() {
  # Flush every DOCKER-USER rule that mentions our subnet, repeatedly until none left.
  while in_vm iptables -S DOCKER-USER | grep -q -- "$SUBNET"; do
    local rule
    # Strip the whole "-A DOCKER-USER " prefix; the chain is passed separately
    # to -D, so leaving it in would be read as a rule number and error out.
    rule=$(in_vm iptables -S DOCKER-USER | grep -m1 -- "$SUBNET" | sed 's/^-A DOCKER-USER //')
    # shellcheck disable=SC2086
    in_vm iptables -D DOCKER-USER $rule
  done
}

apply_rules() {
  clear_rules
  # -I inserts at position 1, so these are applied in REVERSE order of listing:
  # the DROPs go in first, then the RETURNs land above them.
  for dst in "${PRIVATE_RANGES[@]}"; do
    in_vm iptables -I DOCKER-USER -s "$SUBNET" -d "$dst" -j DROP
  done
  # Container-to-container inside our own bridge stays allowed.
  in_vm iptables -I DOCKER-USER -s "$SUBNET" -d "$SUBNET" -j RETURN
  # Replies on connections you opened (i.e. your browser hitting :3001) stay allowed.
  in_vm iptables -I DOCKER-USER -s "$SUBNET" -m conntrack \
    --ctstate ESTABLISHED,RELATED -j RETURN
}

require_colima
case "${1:-apply}" in
  apply)  apply_rules; echo "Egress rules applied for $SUBNET:"; in_vm iptables -S DOCKER-USER ;;
  status) in_vm iptables -S DOCKER-USER ;;
  clear)  clear_rules; echo "Egress rules removed for $SUBNET." ;;
  *)      echo "usage: $0 [apply|status|clear]" >&2; exit 2 ;;
esac
