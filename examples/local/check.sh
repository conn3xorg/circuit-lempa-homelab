#!/usr/bin/env bash
# Uses the default stack the way a browser and a resolver on your network
# would, from the host itself: every app through Traefik by its name, and the
# names from BIND. CI runs it inside the host container:
#   podman exec -i -e LAB_PASSWORD circuit-lempa-homelab bash -s < check.sh
# LAB_PASSWORD is the admin_password the stack was applied with.
set -euo pipefail
domain=${DOMAIN:-home.arpa}
# The address the names point at: the stack's address input.
address=${ADDRESS:-127.0.0.1}
: "${LAB_PASSWORD:?Set LAB_PASSWORD to the admin_password of the stack.}"

# Services take a while to come back after a restart, so each check gets a
# minute and a half before it counts as failed.
retry() {
  for _ in $(seq 45); do
    "$@" >/dev/null 2>&1 && return 0
    sleep 2
  done
  echo "Failed: $*" >&2
  "$@"
}

# Through Traefik on 443 by name. -k because Traefik serves its own
# self-signed certificate until it has a real one.
via() { curl -sSf --max-time 10 -k --resolve "$1.$domain:443:127.0.0.1" "https://$1.$domain$2"; }

# Grafana's API on loopback, signed in as admin from a netrc on a pipe, so
# the password never shows on a command line.
grafana() { curl -sSf --max-time 10 --netrc-file <(printf 'machine 127.0.0.1 login admin password %s\n' "$LAB_PASSWORD") "http://127.0.0.1:3002$1"; }

command -v dig >/dev/null || if command -v apt-get >/dev/null; then
  apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq bind9-dnsutils >/dev/null
else
  dnf -y -q install bind-utils
fi

echo "BIND answers for each app's name, with authority, and nothing else."
resolves() { [ "$(dig +short @127.0.0.1 "$1.$domain" A)" = "$address" ]; }
for name in home uptimekuma grafana ns; do
  retry resolves "$name"
done
dig @127.0.0.1 "grafana.$domain" A | grep -q 'flags:.* aa[ ;]'
dig @127.0.0.1 "nothing.$domain" A | grep -q 'status: NXDOMAIN'
dig @127.0.0.1 example.org A | grep -q 'status: REFUSED'

echo "Traefik sends plain HTTP to HTTPS, and unknown names nowhere."
case $(curl -s -o /dev/null -w '%{http_code}' --resolve "home.$domain:80:127.0.0.1" "http://home.$domain/") in 301 | 308) ;; *) exit 1 ;; esac
[ "$(curl -sk -o /dev/null -w '%{http_code}' --resolve "nothing.$domain:443:127.0.0.1" "https://nothing.$domain/")" = 404 ]

echo "Homepage loads, with a tile for each app."
homepage_up() { via home / | grep -q '<title[^>]*>Homelab</title>'; }
retry homepage_up
services=$(via home /api/services)
for tile in '"Uptime Kuma"' '"Grafana"' '"Monitoring"' "\"https://grafana.$domain\""; do
  grep -qF "$tile" <<<"$services" || { echo "Homepage's services lack $tile: $services" >&2; exit 1; }
done

# Homepage's status dot: it checks Grafana's loopback port from the host.
grafana_dot() { via home '/api/siteMonitor?groupName=Monitoring&serviceName=Grafana' | grep -q '"status":200'; }
retry grafana_dot

echo "Uptime Kuma answers, socket.io included, which its whole UI runs on."
kuma_up() { via uptimekuma /dashboard | grep -q '<title>Uptime Kuma'; }
retry kuma_up
via uptimekuma '/socket.io/?EIO=4&transport=polling' | grep -q '"sid"'

echo "Grafana answers, has Prometheus as its datasource, and can query it."
grafana_up() { via grafana /api/health | grep -q '"database": *"ok"'; }
retry grafana_up
grafana /api/datasources | grep -q '"name":"Prometheus"'
prometheus_queried() { grafana /api/datasources/uid/prometheus/health | grep -q '"status":"OK"'; }
retry prometheus_queried
grafana '/api/datasources/proxy/uid/prometheus/api/v1/query?query=up%7Bjob%3D%22prometheus%22%7D' | grep -q '"value":\[[0-9.]*,"1"\]'

echo "All good."
