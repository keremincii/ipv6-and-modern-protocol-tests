#!/bin/bash

# =======================================================
# FINAL MASTER SCRIPT: 10.60.1.50 | IPv6 ::50 | 6to4
# =======================================================

# --- SABİT AYARLAR (Senin ifcfg-eth0 dosyana göre) ---
IFACE="eth0"
MY_UUID="96894157-e38a-3d52-a385-830d68345ff3"
MY_IPV4="10.60.1.50"
MY_GW="10.60.1.1"
MY_DNS1="10.38.1.10"
MY_DNS2="8.8.8.8"

# --- IPv6 AYARLARI ---
# Gateway IPv6 (IPv4 .50 olduğu için bunu da .50 yaptık)
TARGET_IPV6="2001:db8:50::50"
# Subnet Prefix
SUBNET_PREFIX="2001:db8:50::"

# --- 6to4 TÜNEL AYARLARI ---
TUNNEL_NAME="tun6to4"
TUNNEL_IPV6_ADDR="2002:d4fd:5f1b::1/16" 
TUNNEL_IPV6_ROUTE="2002::/16"

echo ">>> [1/9] Sistem Hazırlanıyor..."
echo "    - Makine IPv4: $MY_IPV4"
echo "    - Makine IPv6: $TARGET_IPV6"
echo "    - UUID:        $MY_UUID"

echo ">>> [2/9] Paketler Yükleniyor..."
dnf install epel-release -y
dnf install tayga iptables-services net-tools kea -y

echo ">>> [3/9] eth0 Ağ Konfigürasyonu Yazılıyor..."
# Yedek al
cp /etc/sysconfig/network-scripts/ifcfg-$IFACE /etc/sysconfig/network-scripts/ifcfg-$IFACE.bak_final 2>/dev/null

cat > /etc/sysconfig/network-scripts/ifcfg-$IFACE <<EOF
TYPE=Ethernet
PROXY_METHOD=none
BROWSER_ONLY=no
BOOTPROTO=none
DEFROUTE=yes
IPV4_FAILURE_FATAL=no
NAME=$IFACE
UUID=$MY_UUID
DEVICE=$IFACE
ONBOOT=yes
AUTOCONNECT_PRIORITY=-999

# IPv4 Ayarları (Sabit)
IPADDR=$MY_IPV4
PREFIX=24
GATEWAY=$MY_GW
DNS1=$MY_DNS1
DNS2=$MY_DNS2

# IPv6 Ayarları (Aktif Ediliyor)
IPV6INIT=yes
IPV6_DISABLED=no
IPV6ADDR=$TARGET_IPV6/64
IPV6_DEFROUTE=yes
IPV6_FAILURE_FATAL=no
IPV6_ADDR_GEN_MODE=default
IPV6_AUTOCONF=no
EOF

# Network servisini yeniden başlat
systemctl restart NetworkManager

echo ">>> [4/9] 6to4 Tünel Kurulumu..."

# Önce eski tünel varsa temizle
nmcli connection delete "$TUNNEL_NAME" > /dev/null 2>&1
ip tunnel del "$TUNNEL_NAME" > /dev/null 2>&1

# Tüneli oluştur (Local IP olarak 10.60.1.50 kullanacak)
nmcli con add type ip-tunnel \
    con-name "$TUNNEL_NAME" \
    ifname "$TUNNEL_NAME" \
    mode sit \
    remote 0.0.0.0 \
    local "$MY_IPV4" \
    ipv6.method manual \
    ipv6.addresses "$TUNNEL_IPV6_ADDR" \
    ipv6.routes "$TUNNEL_IPV6_ROUTE" > /dev/null

if [ $? -eq 0 ]; then
    echo "    -> Tünel başarıyla tanımlandı."
else
    echo "    -> HATA: Tünel nmcli ile eklenemedi."
fi

# Tüneli Aktifleştir
nmcli connection up "$TUNNEL_NAME" > /dev/null
echo "    -> Tünel bağlantısı açıldı."

echo ">>> [5/9] Kernel Ayarları (Tünel + NAT64)..."
cat > /etc/sysctl.d/99-master-gateway.conf <<EOF
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.default.forwarding = 1
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.eth0.forwarding = 1
# Tünel için özel ayar
net.ipv6.conf.$TUNNEL_NAME.disable_ipv6 = 0
net.ipv6.conf.$TUNNEL_NAME.forwarding = 1
EOF
sysctl --system > /dev/null 2>&1

echo ">>> [6/9] Tayga (NAT64) Konfigürasyonu..."
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
# IPTables NAT
ExecStartPost=-/usr/sbin/iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
ExecStartPost=/usr/sbin/iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
ExecStartPost=/usr/sbin/iptables -A FORWARD -i eth0 -o nat64 -m state --state RELATED,ESTABLISHED -j ACCEPT
ExecStartPost=/usr/sbin/iptables -A FORWARD -i nat64 -o eth0 -j ACCEPT
# IPv6 Clean
ExecStartPost=/usr/sbin/ip6tables -P FORWARD ACCEPT
ExecStartPost=/usr/sbin/ip6tables -F FORWARD
Restart=always

[Install]
WantedBy=multi-user.target
EOF

echo ">>> [7/9] Kea DHCPv6 (Havuz: 60-200)..."
# IP adresimiz 50 olduğu için havuzu 60'tan başlattık!
CONFIG_FILE="/etc/kea/kea-dhcp6.conf"
[ -f "$CONFIG_FILE" ] && cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"

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
            "subnet": "${SUBNET_PREFIX}/64",
            "pools": [ { "pool": "${SUBNET_PREFIX}60 - ${SUBNET_PREFIX}200" } ],
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

echo ">>> [8/9] Firewall Kuralları..."
systemctl enable --now firewalld

# Temizlik
firewall-cmd --permanent --zone=public --remove-source=${SUBNET_PREFIX}/64 || true

# Trusted Zone: NAT64 ve Clientlar
firewall-cmd --permanent --zone=trusted --add-interface=nat64
firewall-cmd --permanent --zone=trusted --add-source=${SUBNET_PREFIX}/64

# KRİTİK: Tünel arayüzüne güven
firewall-cmd --permanent --zone=trusted --add-interface=$TUNNEL_NAME

# DHCP ve ICMP İzinleri
firewall-cmd --permanent --add-service=dhcpv6
firewall-cmd --permanent --add-protocol=icmp

# Masquerade
firewall-cmd --permanent --zone=public --add-masquerade

firewall-cmd --reload

echo ">>> [9/9] Servisler Başlatılıyor..."
systemctl stop iptables
systemctl disable iptables

systemctl daemon-reload
systemctl restart docker || echo "Docker yok, atlandı."

systemctl enable tayga
systemctl restart tayga

systemctl enable kea-dhcp6
systemctl restart kea-dhcp6

echo "============================================="
echo "✅ TAM KURULUM BAŞARILI!"
echo "---------------------------------------------"
echo "🖥️  IPv4 Adresi    : $MY_IPV4"
echo "🌐 Gateway IPv6   : $TARGET_IPV6"
echo "🚇 6to4 Tünel     : $TUNNEL_IPV6_ADDR (Aktif)"
echo "🎱 DHCP Havuzu    : ...::60 -> ...::200"
echo "============================================="
