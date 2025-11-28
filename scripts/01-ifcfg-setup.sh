# 1. Mevcut UUID'yi al (yoksa yeni üretir)
CURRENT_UUID=$(grep UUID /etc/sysconfig/network-scripts/ifcfg-eth0 2>/dev/null | cut -d= -f2 | tr -d '"')
[ -z "$CURRENT_UUID" ] && CURRENT_UUID=$(uuidgen)

# 2. Dosyayı EOF ve tee ile yaz
cat <<EOF | sudo tee /etc/sysconfig/network-scripts/ifcfg-eth0
TYPE=Ethernet
PROXY_METHOD=none
BROWSER_ONLY=no
BOOTPROTO=none
DEVICE=eth0
NAME=eth0
UUID=${CURRENT_UUID}
ONBOOT=yes
AUTOCONNECT_PRIORITY=-999

# IPv6 Konfigürasyonu
IPV6ADDR=2001:db8:50::1/64
IPV6INIT=yes
IPV6_AUTOCONF=no
IPV6_DEFROUTE=yes
IPV6_FAILURE_FATAL=no
IPV6_ADDR_GEN_MODE=default
IPV6_DISABLED=no

# IPv4 Konfigürasyonu
IPADDR=10.38.1.193
GATEWAY=10.38.1.254
DNS1=10.38.1.10
DNS2=8.8.8.8
PREFIX=24
IPV4_FAILURE_FATAL=no
DEFROUTE=yes
EOF

# 3. Servisi yeniden başlat
sudo systemctl restart NetworkManager
