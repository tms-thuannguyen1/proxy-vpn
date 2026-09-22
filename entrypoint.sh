#!/bin/bash
set -e

# Tear down the VPN session so the server releases it right away. Without this,
# `docker compose stop` kills everything abruptly, the server keeps the stale
# session, and the next start is rejected until that session times out.
teardown() {
    echo "Disconnecting VPN session..."
    [ -n "$PROXY_PID" ] && kill -TERM "$PROXY_PID" 2>/dev/null || true
    # pppd sends LCP Terminate-Request to the server when it gets SIGTERM
    pkill -TERM pppd 2>/dev/null || true
    for _ in 1 2 3; do pgrep pppd >/dev/null || break; sleep 1; done
    echo "d myvpn" > /var/run/xl2tpd/l2tp-control 2>/dev/null || true
    sleep 1
    ipsec down myvpn >/dev/null 2>&1 || true
    ipsec stop >/dev/null 2>&1 || true
}
trap 'teardown; exit 0' TERM INT

# Reports the failure, tears down and exits so the restart policy retries.
fail() {
    echo "ERROR: $1" >&2
    teardown
    exit 1
}

# The writable layer survives `restart: unless-stopped`, so pidfiles left by
# the previous run make xl2tpd/charon believe they are already running.
rm -f /var/run/xl2tpd.pid /var/run/charon.pid /var/run/starter.charon.pid \
      /var/run/ppp*.pid /var/run/xl2tpd/l2tp-control

# 1. Cấu hình IPsec
cat <<EOF > /etc/ipsec.conf
config setup
  charondebug="ike 1, knl 1, cfg 0"

conn myvpn
  keyexchange=ikev1
  authby=secret
  auto=add
  keyingtries=1
  type=transport
  left=%defaultroute
  leftprotoport=17/1701
  right=${VPN_SERVER}
  # A server behind NAT identifies itself by its private IP (e.g. 192.168.100.1),
  # not VPN_SERVER; accept any ID by default like native clients (PSK still authenticates)
  rightid=${VPN_SERVER_ID:-%any}
  rightprotoport=17/1701
  ike=aes256-sha256-modp2048,aes128-sha1-modp1024,3des-sha1-modp1024!
  esp=aes256-sha256,aes128-sha1,3des-sha1!
EOF

cat <<EOF > /etc/ipsec.secrets
: PSK "${VPN_PSK}"
EOF

# 2. Cấu hình L2TP
mkdir -p /etc/xl2tpd
cat <<EOF > /etc/xl2tpd/xl2tpd.conf
[lac myvpn]
lns = ${VPN_SERVER}
pppoptfile = /etc/ppp/options.l2tpd.client
length bit = yes
redial = yes
redial timeout = 5
EOF

mkdir -p /etc/ppp
cat <<EOF > /etc/ppp/options.l2tpd.client
ipcp-accept-local
ipcp-accept-remote
refuse-eap
require-mschap-v2
noccp
noauth
idle 0
# Send pppd messages (e.g. authentication failures) to the container log
logfd 2
name "${VPN_USER}"
password "${VPN_PASSWORD}"
EOF

# 3. Khởi động IPsec
ipsec start
sleep 2
# `ipsec up` exits 0 even when negotiation fails, so check the SA explicitly
ipsec up myvpn || true
ipsec status myvpn | grep -q INSTALLED || fail "IPsec negotiation failed, see the lines above: 'peer not responding' = wrong VPN_SERVER or UDP 500/4500 blocked; 'NO_PROPOSAL_CHOSEN' = cipher mismatch; 'INVALID_HASH_INFORMATION' or 'AUTHENTICATION_FAILED' = wrong VPN_PSK; 'IDir ... does not match' = set VPN_SERVER_ID to the ID the server sends"

# 4. Khởi động xl2tpd
mkdir -p /var/run/xl2tpd
xl2tpd -D &
sleep 2
echo "c myvpn" > /var/run/xl2tpd/l2tp-control

echo "Đang chờ interface ppp0 có IP..."
for i in {1..30}; do
    if ip addr show ppp0 2>/dev/null | grep -q "inet"; then
        echo "VPN ppp0 đã nhận IP thành công!"
        break
    fi
    sleep 1
done
if ! ip addr show ppp0 2>/dev/null | grep -q "inet"; then
    fail "ppp0 did not get an IP within 30s: no 'Connection established' above means L2TP got no reply; otherwise check VPN_USER/VPN_PASSWORD or wait for a stale session on the server to expire"
fi

# 5. Routing qua ppp0
ORIG_GW=$(ip route show default | awk '{print $3}')
if [ -n "$ORIG_GW" ]; then
    ip route add ${VPN_SERVER} via $ORIG_GW dev eth0 2>/dev/null || true
fi
ip route del default dev eth0 2>/dev/null || true
ip route add default dev ppp0

echo "nameserver 1.1.1.1" > /etc/resolv.conf
echo "nameserver 8.8.8.8" >> /etc/resolv.conf

# 6. Port forwards for apps without SOCKS support (DB clients, ssh, ...):
# PORT_FORWARDS="41000:db.example.com:3306,41001:10.0.0.5:22" makes
# 127.0.0.1:41000 on the host reach db.example.com:3306 through the VPN.
if [ -n "${PORT_FORWARDS}" ]; then
    IFS=',' read -ra forwards <<< "${PORT_FORWARDS// /}"
    for fwd in "${forwards[@]}"; do
        IFS=':' read -r lport rhost rport extra <<< "$fwd"
        if [ -z "$lport" ] || [ -z "$rhost" ] || [ -z "$rport" ] || [ -n "$extra" ]; then
            fail "invalid PORT_FORWARDS entry '$fwd' (expected local_port:host:remote_port)"
        fi
        echo "Forwarding 127.0.0.1:${lport} -> ${rhost}:${rport}"
        socat "TCP-LISTEN:${lport},fork,reuseaddr" "TCP:${rhost}:${rport}" &
    done
fi

# 7. WireGuard bridge: vpn-on connects the Mac to wg0, and everything it sends
# is NATed out through ppp0. Keys persist in /data; the client config is
# regenerated on every start so it always matches the current ppp0 MTU.
WG_DIR=/data/wireguard
WG_PORT=51820
WG_SERVER_ADDR=10.99.0.1/24
WG_CLIENT_ADDR=10.99.0.2/32
mkdir -p "$WG_DIR"
for key in server client; do
    [ -s "$WG_DIR/$key.key" ] || (umask 077; wg genkey > "$WG_DIR/$key.key")
done
ip link del wg0 2>/dev/null || true
ip link add wg0 type wireguard
wg set wg0 listen-port "$WG_PORT" private-key "$WG_DIR/server.key" \
    peer "$(wg pubkey < "$WG_DIR/client.key")" allowed-ips "$WG_CLIENT_ADDR"
ip addr add "$WG_SERVER_ADDR" dev wg0
ip link set wg0 up
sysctl -qw net.ipv4.ip_forward=1
iptables -t nat -C POSTROUTING -o ppp0 -j MASQUERADE 2>/dev/null ||
    iptables -t nat -A POSTROUTING -o ppp0 -j MASQUERADE
iptables -t mangle -C FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null ||
    iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu

# vpn-on routes this IP outside the tunnel, otherwise the Mac would send the
# VPN's own IPsec packets (Docker -> server) into the tunnel they carry
SERVER_IP=$(getent ahostsv4 "$VPN_SERVER" | awk 'NR == 1 { print $1 }')
[ -n "$SERVER_IP" ] || fail "cannot resolve VPN_SERVER '$VPN_SERVER'"
echo "$SERVER_IP" > "$WG_DIR/vpn-server-ip"

(umask 077; cat <<EOF > "$WG_DIR/wg-l2tp.conf"
# Generated by entrypoint.sh on every start. Used by vpn-on (wg-quick).
[Interface]
PrivateKey = $(cat "$WG_DIR/client.key")
Address = $WG_CLIENT_ADDR
DNS = 1.1.1.1, 8.8.8.8
MTU = $(cat /sys/class/net/ppp0/mtu)
# With automatic routes wg-quick would add (and later delete) a host route for
# the 127.0.0.1 endpoint via the LAN gateway; add the default routes ourselves.
# They disappear with the interface on wg-quick down.
Table = off
PostUp = route -q -n add -inet 0.0.0.0/1 -interface %i && route -q -n add -inet 128.0.0.0/1 -interface %i

[Peer]
PublicKey = $(wg pubkey < "$WG_DIR/server.key")
Endpoint = 127.0.0.1:$WG_PORT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
)
echo "WireGuard bridge ready on udp/${WG_PORT}"

# 8. Khởi chạy Microsocks Proxy
echo "Khởi chạy Microsocks Proxy tại cổng 1080..."
# Run in the background (not exec) so this shell stays PID 1 and can trap SIGTERM
microsocks -i 0.0.0.0 -p 1080 &
PROXY_PID=$!
wait "$PROXY_PID" || true
teardown
