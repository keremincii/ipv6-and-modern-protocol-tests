#!/bin/bash

# ====================================================
# NAT64 GATEWAY FINAL MASTER SCRIPT (FIREWALL & DOCKER FIXED)
# SUNUCU: 10.38.1.180 (Gateway)
# DURUM: TEST EDİLDİ VE ONAYLANDI
# ====================================================

IFACE="eth0"

echo ">>> [1/8] UUID Alınıyor..."
CURRENT_UUID=$(nmcli -g UUID connection show "$IFACE" 2>/dev/null)
if [ -z "$CURRENT_UUID" ]; then
    CURRENT_UUID=$(uuidgen)
fi

echo ">>> [2/8] Paketler Yükleniyor..."
dnf install epel-release -y
dnf install tayga iptables-services net-tools -y

echo ">>> [3/8] Ağ Ayarları (ifcfg-$IFACE)..."
cp /etc/sysconfig/network-scripts/ifcfg-$IFACE /etc/sysconfig/network-scripts/ifcfg-$IFACE.bak_final

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
IPADDR=10.38.1.180
GATEWAY=10.38.1.254
DNS1=10.38.1.10
DNS2=8.8.8.8
PREFIX=24
IPV6INIT=yes
IPV6_DISABLED=no
IPV6ADDR=2001:db8:50::180/64
IPV6_DEFROUTE=yes
IPV6_FAILURE_FATAL=no
IPV6_ADDR_GEN_MODE=default
IPV6_AUTOCONF=no
EOF

systemctl restart NetworkManager

echo ">>> [4/8] Kernel Forwarding..."
cat > /etc/sysctl.d/99-nat64.conf <<EOF
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.default.disable_ipv6 = 0
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.eth0.forwarding = 1
EOF
sysctl --system

echo ">>> [5/8] Tayga Config..."
cat > /etc/tayga.conf <<EOF
tun-device nat64
ipv4-addr 192.168.255.1
ipv6-addr 2001:db8:50::180
prefix 64:ff9b::/96
dynamic-pool 192.168.255.0/24
data-dir /var/spool/tayga
EOF

mkdir -p /var/spool/tayga
chmod 700 /var/spool/tayga

echo ">>> [6/8] Tayga Servisi (IPTables Entegre)..."
cat > /etc/systemd/system/tayga.service <<EOF
[Unit]
Description=Tayga NAT64 Service
# Docker ve Firewall acildiktan sonra basla
After=network.target docker.service firewalld.service

[Service]
Type=simple
ExecStart=/usr/sbin/tayga --nodetach

# Kartin olusmasini bekle
ExecStartPost=/usr/bin/sleep 5

# Kilitleri Kir
ExecStartPost=/usr/sbin/sysctl -w net.ipv6.conf.nat64.disable_ipv6=0
ExecStartPost=/usr/sbin/sysctl -w net.ipv6.conf.all.forwarding=1
ExecStartPost=/usr/sbin/sysctl -w net.ipv6.conf.eth0.forwarding=1

# Rotalar
ExecStartPost=-/usr/sbin/ip link set nat64 up
ExecStartPost=-/usr/sbin/ip addr replace 192.168.255.1 dev nat64
ExecStartPost=-/usr/sbin/ip route replace 192.168.255.0/24 dev nat64
ExecStartPost=-/usr/sbin/ip -6 route replace 64:ff9b::/96 dev nat64

# NAT Kuralları (Mevcutlari temizle ve yeniden ekle)
ExecStartPost=-/usr/sbin/iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
ExecStartPost=-/usr/sbin/iptables -D FORWARD -i eth0 -o nat64 -m state --state RELATED,ESTABLISHED -j ACCEPT
ExecStartPost=-/usr/sbin/iptables -D FORWARD -i nat64 -o eth0 -j ACCEPT

ExecStartPost=/usr/sbin/iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
ExecStartPost=/usr/sbin/iptables -A FORWARD -i eth0 -o nat64 -m state --state RELATED,ESTABLISHED -j ACCEPT
ExecStartPost=/usr/sbin/iptables -A FORWARD -i nat64 -o eth0 -j ACCEPT

# IPv6 Firewall Temizligi (Sadece Forward zinciri)
ExecStartPost=/usr/sbin/ip6tables -P FORWARD ACCEPT
ExecStartPost=/usr/sbin/ip6tables -F FORWARD

Restart=always

[Install]
WantedBy=multi-user.target
EOF

echo ">>> [7/8] Firewalld Yapılandırması (Kritik Düzeltmeler)..."
systemctl enable --now firewalld

# 1. Önce olası çakışmaları temizle (Public zone'dan sil)
# Hata verirse onemseme (|| true)
firewall-cmd --permanent --zone=public --remove-source=2001:db8:50::/64 || true
firewall-cmd --permanent --zone=public --remove-source=2001:db8:50::0/64 || true

# 2. nat64 arayüzünü "Trusted" (Güvenli) bölgesine al
firewall-cmd --permanent --zone=trusted --add-interface=nat64

# 3. Client Ağını (Source Based) Trusted bölgesine al (EN KRİTİK ADIM)
firewall-cmd --permanent --zone=trusted --add-source=2001:db8:50::/64

# 4. Masquerade aç
firewall-cmd --permanent --zone=public --add-masquerade

# 5. Uygula
firewall-cmd --reload

echo ">>> [8/8] Servisler Başlatılıyor..."
# iptables servisini kapat (Tayga yönetecek)
systemctl stop iptables
systemctl disable iptables

# Docker'ı yeniden başlat
echo ">>> Docker..."
systemctl restart docker

# Tayga'yı yeniden başlat
echo ">>> Tayga..."
systemctl daemon-reload
systemctl enable tayga
systemctl restart tayga

echo "============================================="
echo "✅ KURULUM TAMAMLANDI!"
echo " Firewalld: AÇIK"
echo " Docker: AÇIK"
echo " NAT64: AÇIK"
echo "============================================="
