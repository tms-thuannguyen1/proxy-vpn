#!/bin/bash
set -e

# 1. Cấu hình IPsec
cat <<EOF > /etc/ipsec.conf
config setup
  charondebug="ike 1, knl 1, cfg 0"

conn myvpn
  keyexchange=ikev1
  authby=secret
  auto=start
  type=transport
  left=%defaultroute
  leftprotoport=17/1701
  right=${VPN_SERVER}
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
name "${VPN_USER}"
password "${VPN_PASSWORD}"
EOF

# 3. Khởi động IPsec
ipsec start
sleep 2
ipsec up myvpn

# 4. Khởi động xl2tpd
mkdir -p /var/run/xl2tpd
rm -f /var/run/xl2tpd/l2tp-control
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

# 5. Routing qua ppp0
ORIG_GW=$(ip route show default | awk '{print $3}')
if [ -n "$ORIG_GW" ]; then
    ip route add ${VPN_SERVER} via $ORIG_GW dev eth0 2>/dev/null || true
fi
ip route del default dev eth0 2>/dev/null || true
ip route add default dev ppp0

echo "nameserver 1.1.1.1" > /etc/resolv.conf
echo "nameserver 8.8.8.8" >> /etc/resolv.conf

# 6. Khởi chạy Microsocks Proxy
echo "Khởi chạy Microsocks Proxy tại cổng 1080..."
exec microsocks -i 0.0.0.0 -p 1080
