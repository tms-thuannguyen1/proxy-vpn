# Shell shortcuts for the L2TP/IPsec SOCKS5 proxy container (macOS, zsh).
#
# Install: add this line to ~/.zshrc, then run `source ~/.zshrc`:
#   source ~/l2tp-proxy/vpn.zsh
#
# Commands:
#   vpn-on [--browser]  Start the container, wait until the proxy works, then
#                       enable the macOS SOCKS proxy (skipped with --browser)
#   vpn-off             Disable the macOS SOCKS proxy, then stop the container
#   vpn-status          Show container state, exit IP and macOS proxy state
#   vpn-logs            Follow container logs
#
# Optional overrides (set before sourcing this file):
#   VPN_PROXY_DIR       Project directory (default: directory of this file)
#   VPN_PROXY_HOST      Proxy host (default: 127.0.0.1)
#   VPN_PROXY_PORT      Proxy port (default: 1080)
#   VPN_PROXY_TIMEOUT   Seconds to wait for the proxy (default: 30)
#   VPN_NET_SERVICE     macOS network service, e.g. "Wi-Fi" (default: auto-detect)

typeset -g VPN_PROXY_DIR=${VPN_PROXY_DIR:-${${(%):-%x}:A:h}}
typeset -g VPN_PROXY_HOST=${VPN_PROXY_HOST:-127.0.0.1}
typeset -g VPN_PROXY_PORT=${VPN_PROXY_PORT:-1080}
typeset -g VPN_PROXY_TIMEOUT=${VPN_PROXY_TIMEOUT:-30}

_vpn_compose() {
  docker compose -f "$VPN_PROXY_DIR/docker-compose.yml" "$@"
}

# Prints the exit IP seen through the proxy; fails if the tunnel is not usable.
_vpn_exit_ip() {
  curl -fsS --max-time 5 --socks5-hostname "$VPN_PROXY_HOST:$VPN_PROXY_PORT" \
    https://ipinfo.io/ip 2>/dev/null
}

# Maps the interface of the current default route (e.g. en0) to its
# network service name (e.g. "Wi-Fi").
_vpn_active_service() {
  local iface
  iface=$(route -n get default 2>/dev/null | awk '/interface:/ { print $2 }')
  [[ -n $iface ]] || return 1
  networksetup -listnetworkserviceorder | awk -v dev="$iface" '
    /^\([0-9*]+\) / { sub(/^\([0-9*]+\) /, ""); name = $0; next }
    index($0, "Device: " dev ")") { print name; exit }
  '
}

_vpn_all_services() {
  networksetup -listallnetworkservices | tail -n +2 | sed 's/^\*//'
}

_vpn_socks_enabled() {
  networksetup -getsocksfirewallproxy "$1" 2>/dev/null | grep -q '^Enabled: Yes'
}

vpn-on() {
  local browser_only=0 service ip i
  [[ $1 == --browser ]] && browser_only=1

  if ! docker info >/dev/null 2>&1; then
    echo "Docker is not running. Start Docker Desktop first." >&2
    return 1
  fi

  echo "Starting VPN container..."
  _vpn_compose up -d || return 1

  printf "Waiting for SOCKS5 proxy on %s:%s " "$VPN_PROXY_HOST" "$VPN_PROXY_PORT"
  for (( i = 0; i < VPN_PROXY_TIMEOUT; i++ )); do
    ip=$(_vpn_exit_ip) && break
    printf "."
    sleep 1
  done
  echo

  # Never point macOS at a dead proxy: that would cut the whole network.
  if [[ -z $ip ]]; then
    echo "Proxy not ready after ${VPN_PROXY_TIMEOUT}s. Check: vpn-logs" >&2
    return 1
  fi

  if (( browser_only )); then
    echo "VPN is ON (browser only). Exit IP: $ip"
    return 0
  fi

  service=${VPN_NET_SERVICE:-$(_vpn_active_service)}
  if [[ -z $service ]]; then
    echo "Cannot detect the active network service. Set VPN_NET_SERVICE." >&2
    return 1
  fi

  networksetup -setsocksfirewallproxy "$service" "$VPN_PROXY_HOST" "$VPN_PROXY_PORT" &&
    networksetup -setsocksfirewallproxystate "$service" on || return 1
  echo "VPN is ON. Exit IP: $ip, macOS SOCKS proxy enabled on \"$service\"."
}

vpn-off() {
  local service

  # Disable on every service, not only the current one, in case the network
  # was switched (e.g. Wi-Fi -> Ethernet) while the VPN was on.
  _vpn_all_services | while IFS= read -r service; do
    if _vpn_socks_enabled "$service"; then
      networksetup -setsocksfirewallproxystate "$service" off &&
        echo "macOS SOCKS proxy disabled on \"$service\"."
    fi
  done

  if docker info >/dev/null 2>&1; then
    echo "Stopping VPN container..."
    _vpn_compose stop || return 1
  fi
  echo "VPN is OFF. Network is back to normal."
}

vpn-status() {
  local service ip state

  state=$(_vpn_compose ps -a --format '{{.State}}' 2>/dev/null)
  echo "Container : ${state:-not created or Docker not running}"

  if ip=$(_vpn_exit_ip); then
    echo "Exit IP   : $ip"
  else
    echo "Exit IP   : proxy not reachable"
  fi

  _vpn_all_services | while IFS= read -r service; do
    _vpn_socks_enabled "$service" && echo "macOS SOCKS: ON (\"$service\")"
  done
  return 0
}

vpn-logs() {
  _vpn_compose logs -f
}
