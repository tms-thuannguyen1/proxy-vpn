# Shell shortcuts for the L2TP/IPsec VPN container (macOS, zsh).
#
# Install: add this line to ~/.zshrc, then run `source ~/.zshrc`:
#   source ~/l2tp-proxy/vpn.zsh
#
# Commands:
#   vpn-on [--browser]  Start the container, wait until the VPN works, then
#                       route the whole Mac through it (WireGuard bridge).
#                       --browser: only start the container (SOCKS5 on :1080)
#   vpn-off             Remove the whole-Mac route, then stop the container
#   vpn-status          Show container state, tunnel state and exit IPs
#   vpn-logs            Follow container logs
#   vpn-exec <cmd...>   Run a command with proxy env vars set, for CLI tools
#                       that honor them (curl, git, wget...)
#
# Whole-Mac mode needs `brew install wireguard-tools` and asks for the sudo
# password (routes and DNS are system settings).
#
# Optional overrides (set before sourcing this file):
#   VPN_PROXY_DIR       Project directory (default: directory of this file)
#   VPN_PROXY_HOST      Proxy host (default: 127.0.0.1)
#   VPN_PROXY_PORT      Proxy port (default: 1080)
#   VPN_PROXY_TIMEOUT   Seconds to wait for the VPN (default: 30)
#   VPN_NET_SERVICE     macOS network service, e.g. "Wi-Fi" (default: auto-detect)

typeset -g VPN_PROXY_DIR=${VPN_PROXY_DIR:-${${(%):-%x}:A:h}}
typeset -g VPN_PROXY_HOST=${VPN_PROXY_HOST:-127.0.0.1}
typeset -g VPN_PROXY_PORT=${VPN_PROXY_PORT:-1080}
typeset -g VPN_PROXY_TIMEOUT=${VPN_PROXY_TIMEOUT:-30}

# Written by the container (entrypoint.sh) into the ./data bind mount
typeset -g VPN_WG_DIR="$VPN_PROXY_DIR/data/wireguard"
typeset -g VPN_WG_CONF="$VPN_WG_DIR/wg-l2tp.conf"
# What vpn-on changed, so vpn-off can undo exactly that
typeset -g VPN_TUNNEL_STATE="$VPN_PROXY_DIR/data/tunnel.state"

_vpn_compose() {
  docker compose -f "$VPN_PROXY_DIR/docker-compose.yml" "$@"
}

# Prints the exit IP seen through the proxy; fails if the VPN is not usable.
_vpn_exit_ip() {
  curl -fsS --max-time 5 --socks5-hostname "$VPN_PROXY_HOST:$VPN_PROXY_PORT" \
    https://ipinfo.io/ip 2>/dev/null
}

# Prints the exit IP of the Mac's normal routing (tunnel or not).
_vpn_direct_ip() {
  curl -fsS --max-time 5 https://ipinfo.io/ip 2>/dev/null
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

# The tunnel is up when an interface holds the client address from the config.
_vpn_tunnel_up() {
  local addr
  addr=$(awk -F' *= *' '$1 == "Address" { sub(/\/.*/, "", $2); print $2 }' "$VPN_WG_CONF" 2>/dev/null)
  [[ -n $addr ]] && ifconfig | grep -q "inet $addr "
}

_vpn_tunnel_start() {
  local gateway server_ip service

  if ! command -v wg-quick >/dev/null; then
    echo "wg-quick not found. Install it: brew install wireguard-tools" >&2
    return 1
  fi
  if [[ ! -r $VPN_WG_CONF || ! -r $VPN_WG_DIR/vpn-server-ip ]]; then
    echo "Missing $VPN_WG_CONF. Rebuild the container: docker compose up -d --build" >&2
    return 1
  fi
  _vpn_tunnel_up && return 0

  gateway=$(route -n get default 2>/dev/null | awk '/gateway:/ { print $2 }')
  server_ip=$(<"$VPN_WG_DIR/vpn-server-ip")
  service=${VPN_NET_SERVICE:-$(_vpn_active_service)}
  if [[ -z $gateway || -z $service ]]; then
    echo "Cannot detect the default gateway / network service. Set VPN_NET_SERVICE." >&2
    return 1
  fi

  echo "Routing the whole Mac through the VPN (sudo password may be asked)..."
  # Docker's own packets to the VPN server must keep using the real gateway,
  # otherwise they would be sent into the tunnel they are carrying.
  sudo route -q -n add -host "$server_ip" "$gateway" >/dev/null || return 1
  print -r -- "server_ip=$server_ip" > "$VPN_TUNNEL_STATE"

  # IPv6 is not carried by the VPN: turn it off so nothing leaks around it.
  if networksetup -getinfo "$service" | grep -q '^IPv6: Automatic'; then
    sudo networksetup -setv6off "$service" &&
      print -r -- "ipv6_service=$service" >> "$VPN_TUNNEL_STATE"
  fi

  if ! sudo wg-quick up "$VPN_WG_CONF"; then
    _vpn_tunnel_stop
    return 1
  fi
}

_vpn_tunnel_stop() {
  local line server_ip ipv6_service
  _vpn_tunnel_up && sudo wg-quick down "$VPN_WG_CONF"

  [[ -r $VPN_TUNNEL_STATE ]] || return 0
  while IFS= read -r line; do
    case $line in
      server_ip=*)    server_ip=${line#*=} ;;
      ipv6_service=*) ipv6_service=${line#*=} ;;
    esac
  done < "$VPN_TUNNEL_STATE"
  [[ -n $server_ip ]] && sudo route -q -n delete -host "$server_ip" >/dev/null
  [[ -n $ipv6_service ]] && sudo networksetup -setv6automatic "$ipv6_service"
  rm -f "$VPN_TUNNEL_STATE"
}

vpn-on() {
  local browser_only=0 ip direct_ip i
  [[ $1 == --browser ]] && browser_only=1

  if ! docker info >/dev/null 2>&1; then
    echo "Docker is not running. Start Docker Desktop first." >&2
    return 1
  fi

  echo "Starting VPN container..."
  _vpn_compose up -d || return 1

  printf "Waiting for the VPN "
  for (( i = 0; i < VPN_PROXY_TIMEOUT; i++ )); do
    ip=$(_vpn_exit_ip) && break
    printf "."
    sleep 1
  done
  echo

  # Never route the Mac into a dead VPN: that would cut the whole network.
  if [[ -z $ip ]]; then
    echo "VPN not ready after ${VPN_PROXY_TIMEOUT}s. Check: vpn-logs" >&2
    return 1
  fi

  if (( browser_only )); then
    echo "VPN is ON (SOCKS5 only, $VPN_PROXY_HOST:$VPN_PROXY_PORT). Exit IP: $ip"
    return 0
  fi

  _vpn_tunnel_start || return 1

  direct_ip=$(_vpn_direct_ip)
  if [[ $direct_ip == "$ip" ]]; then
    echo "VPN is ON for the whole Mac. Exit IP: $ip"
  else
    echo "Tunnel is up but the Mac exits via '${direct_ip:-unknown}' instead of $ip. Check: vpn-status" >&2
    return 1
  fi
}

vpn-off() {
  local service

  if _vpn_tunnel_up || [[ -r $VPN_TUNNEL_STATE ]]; then
    echo "Removing the whole-Mac route (sudo password may be asked)..."
    _vpn_tunnel_stop
  fi

  # Clean up the manual SOCKS setup (README option 2) on every service, in
  # case the network was switched (e.g. Wi-Fi -> Ethernet) while it was on.
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
  echo "Container  : ${state:-not created or Docker not running}"

  if ip=$(_vpn_exit_ip); then
    echo "VPN exit IP: $ip"
  else
    echo "VPN exit IP: not reachable"
  fi

  if _vpn_tunnel_up; then
    echo "Whole Mac  : ON"
  else
    echo "Whole Mac  : OFF"
  fi
  echo "Mac exit IP: $(_vpn_direct_ip || echo unknown)"

  _vpn_all_services | while IFS= read -r service; do
    _vpn_socks_enabled "$service" && echo "macOS SOCKS: ON (\"$service\")"
  done
  return 0
}

vpn-logs() {
  _vpn_compose logs -f
}

vpn-exec() {
  local proxy="socks5h://$VPN_PROXY_HOST:$VPN_PROXY_PORT"
  ALL_PROXY=$proxy all_proxy=$proxy \
    HTTPS_PROXY=$proxy https_proxy=$proxy \
    HTTP_PROXY=$proxy http_proxy=$proxy \
    "$@"
}
