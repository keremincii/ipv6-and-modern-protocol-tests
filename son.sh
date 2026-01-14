#!/bin/bash

# ====================================================
# FINAL SINGLE-BOX GATEWAY INSTALLER (IP: ...::54)
# ====================================================

IFACE="eth0"
GATEWAY_IPV6="2001:db8:50::54"  # İstenilen Yeni IP
SUBNET_IPV6="2001:db8:50::"
KEASERVICE="kea-dhcp6"

echo ">>> [1/7] Gerekli Paketler Yükleniyor..."
dnf install epel-release -y
dnf install tayga iptables-services net-tools kea -y

echo ">>> [2/7] Ağ Ayarları (IP: $GATEWAY_IPV6) Yapılandırılıyor..."
# UUID Al
CURRENT_UUID=$(nmcli -g UUID connection show "$IFACE" 2>/dev/null)
[ -z "$CURRENT_UUID" ] && CURRENT_UUID=$(uuidgen)

# Eski konfigürasyonu yedekle
cp /etc/sysconfig/network-scripts/ifcfg-$IFACE /etc/sysconfig/network-scripts/ifcfg-$IFACE.bak_54

# NetworkManager Ayarları
cat > /etc/sysconfig/network-scripts/ifcfg-$IFACE <<EOF
TYPE=Ethernet
PROXY_METHOD=none
BROWSER_ONLY=no
BOOTPROTO=none
DEFROUTE=yes
IPV4_FAILURE_FATAL=no
NAME=$IFACE
UUID=$CURRENT_UUID
DEVICE=$IFACE
ONBOOT=yes
AUTOCONNECT_PRIORITY=-999
# IPv4 Ayarları (Mevcut yapını koruyoruz)
IPADDR=10.38.1.180
GATEWAY=10.38.1.254
DNS1=10.38.1.10
DNS2=8.8.8.8
PREFIX=24
# IPv6 Ayarları (İstediğin .54 Adresi)
IPV6INIT=yes
IPV6_DISABLED=no
IPV6ADDR=$GATEWAY_IPV6/64
IPV6_DEFROUTE=yes
IPV6_FAILURE_FATAL=no
IPV6_ADDR_GEN_MODE=default
IPV6_AUTOCONF=no
EOF

# Ağı yeniden başlat
systemctl restart NetworkManager

echo ">>> [3/7] Kernel Forwarding Ayarları..."
# IPv6 trafiğinin akması için gerekli izinler
cat > /etc/sysctl.d/99-nat64-gateway.conf <<EOF
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.default.forwarding = 1
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.eth0.forwarding = 1
EOF
sysctl --system

echo ">>> [4/7] Tayga (NAT64) Konfigürasyonu..."
# Tayga, IPv6 paketlerini IPv4'e çevirir
cat > /etc/tayga.conf <<EOF
tun-device nat64
ipv4-addr 192.168.255.1
ipv6-addr 2001:db8:50::64  
prefix 2001:db8:64:ff9b::/96
dynamic-pool 192.168.255.0/24
data-dir /var/spool/tayga
EOF

mkdir -p /var/spool/tayga
chmod 700 /var/spool/tayga

# Tayga Servis Dosyası ve Routing Kuralları
cat > /etc/systemd/system/tayga.service <<EOF
[Unit]
Description=Tayga NAT64 Service
After=network.target docker.service firewalld.service

[Service]
Type=simple
ExecStart=/usr/sbin/tayga --nodetach
ExecStartPost=/usr/bin/sleep 5
ExecStartPost=/usr/sbin/sysctl -w net.ipv6.conf.nat64.disable_ipv6=0
ExecStartPost=/usr/sbin/sysctl -w net.ipv6.conf.all.forwarding=1
ExecStartPost=-/usr/sbin/ip link set nat64 up
ExecStartPost=-/usr/sbin/ip addr replace 192.168.255.1 dev nat64
ExecStartPost=-/usr/sbin/ip route replace 192.168.255.0/24 dev nat64
ExecStartPost=-/usr/sbin/ip -6 route replace 2001:db8:64:ff9b::/96 dev nat64
# IPTables (NAT Masquerade)
ExecStartPost=-/usr/sbin/iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
ExecStartPost=-/usr/sbin/iptables -D FORWARD -i eth0 -o nat64 -m state --state RELATED,ESTABLISHED -j ACCEPT
ExecStartPost=-/usr/sbin/iptables -D FORWARD -i nat64 -o eth0 -j ACCEPT
ExecStartPost=/usr/sbin/iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
ExecStartPost=/usr/sbin/iptables -A FORWARD -i eth0 -o nat64 -m state --state RELATED,ESTABLISHED -j ACCEPT
ExecStartPost=/usr/sbin/iptables -A FORWARD -i nat64 -o eth0 -j ACCEPT
# IPv6 Table Temizliği
ExecStartPost=/usr/sbin/ip6tables -P FORWARD ACCEPT
ExecStartPost=/usr/sbin/ip6tables -F FORWARD
Restart=always

[Install]
WantedBy=multi-user.target
EOF

echo ">>> [5/7] Kea DHCPv6 Sunucusu (IP Dağıtıcı)..."
CONFIG_FILE="/etc/kea/kea-dhcp6.conf"
[ -f "$CONFIG_FILE" ] && cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"

# Kea Config: Clientlara IP dağıtır ama Gateway'i (.54) kullanmaz (Havuz 100-200 arası)
cat <<EOF > "$CONFIG_FILE"
{
"Dhcp6": {
    "valid-lifetime": 4000,
    "renew-timer": 1000,
    "rebind-timer": 2000,
    "preferred-lifetime": 3000,
    "interfaces-config": {
        "interfaces": [ "eth0" ]
    },
    "lease-database": {
        "type": "memfile",
        "persist": true,
        "name": "/var/lib/kea/kea-leases6.csv"
    },
    "subnet6": [
        {
            "subnet": "${SUBNET_IPV6}/64",
            "pools": [ { "pool": "${SUBNET_IPV6}100 - ${SUBNET_IPV6}200" } ],
            "interface": "eth0",
            "option-data": [
                {
                    "name": "dns-servers",
                    "data": "2001:4860:4860::8888"
                }
            ]
        }
    ]
}
}
EOF
chmod 644 "$CONFIG_FILE"

echo ">>> [6/7] Firewall Güvenlik ve İzin Ayarları..."
systemctl enable --now firewalld

# Olası eski ayarları temizle
firewall-cmd --permanent --zone=public --remove-source=${SUBNET_IPV6}/64 || true

# 1. NAT64 sanal kartına güven
firewall-cmd --permanent --zone=trusted --add-interface=nat64

# 2. Clientlardan gelen trafiğe güven (Source Based)
firewall-cmd --permanent --zone=trusted --add-source=${SUBNET_IPV6}/64

# 3. DHCPv6 servisine izin ver
firewall-cmd --permanent --add-service=dhcpv6

# 4. İnternete çıkış için Masquerade aç
firewall-cmd --permanent --zone=public --add-masquerade

# Ayarları uygula
firewall-cmd --reload

echo ">>> [7/7] Servisler Yeniden Başlatılıyor..."
# Çakışmayı önlemek için iptables servisini kapat (Tayga yönetecek)
systemctl stop iptables
systemctl disable iptables

systemctl daemon-reload
# Docker varsa restart et
systemctl restart docker || echo "Docker yok, devam ediliyor."

# Tayga ve Kea'yı başlat
systemctl enable tayga
systemctl restart tayga
systemctl enable kea-dhcp6
systemctl restart kea-dhcp6

echo "============================================="
echo "✅ KURULUM BAŞARILI!"
echo "   - Bu Makine (Gateway) IP: $GATEWAY_IPV6"
echo "   - Client IP Havuzu:       ...::100 ile ...::200 arası"
echo "============================================="
echo "⚠️ ÖNEMLİ NOT: Client (Müşteri) makinelerin Gateway ayarını"
echo "              $GATEWAY_IPV6 olarak ayarlamayı unutmayın!"
echo "============================================="
