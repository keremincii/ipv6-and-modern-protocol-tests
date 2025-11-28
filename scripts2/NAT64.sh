#!/bin/bash

# ====================================================
# NAT64 GATEWAY MASTER SCRIPT (AUTO-UUID)
# SUNUCU: 10.38.1.180 (Gateway)
# AÇIKLAMA: Docker uyumlu, otomatik UUID algılayan, kalıcı Tayga kurulumu.
# ====================================================

# Hedef Arayüz (Sunucuda internete çıkan kartın adı)
IFACE="eth0"

echo ">>> [1/7] UUID ve Sistem Bilgileri Alınıyor..."
# UUID'yi sistemden otomatik çek, bulamazsa yeni üret
CURRENT_UUID=$(nmcli -g UUID connection show "$IFACE" 2>/dev/null)

if [ -z "$CURRENT_UUID" ]; then
    echo "UYARI: Mevcut bir UUID bulunamadı, yeni oluşturuluyor..."
    CURRENT_UUID=$(uuidgen)
else
    echo "Mevcut UUID Algılandı: $CURRENT_UUID"
fi

echo ">>> [2/7] Gerekli Paketler Yükleniyor..."
dnf install epel-release -y
dnf install tayga iptables-services net-tools -y

echo ">>> [3/7] Ağ Ayarları Yapılandırılıyor (ifcfg-$IFACE)..."
# Mevcut dosyayı yedekle
cp /etc/sysconfig/network-scripts/ifcfg-$IFACE /etc/sysconfig/network-scripts/ifcfg-$IFACE.bak_$(date +%F_%T)

# Dosyayı Dinamik UUID ile oluştur
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

# --- IPv4 AYARLARI ---
IPADDR=10.38.1.180
GATEWAY=10.38.1.254
DNS1=10.38.1.10
DNS2=8.8.8.8
PREFIX=24

# --- IPv6 AYARLARI ---
IPV6INIT=yes
IPV6_DISABLED=no
IPV6ADDR=2001:db8:50::180/64
IPV6_DEFROUTE=yes
IPV6_FAILURE_FATAL=no
IPV6_ADDR_GEN_MODE=default
IPV6_AUTOCONF=no
EOF

# Ağı Yeniden Başlat
echo ">>> Ağ servisi yeniden başlatılıyor..."
systemctl restart NetworkManager

echo ">>> [4/7] Kernel Forwarding Ayarları Yapılıyor..."
# sysctl.conf dosyasına kalıcı ayarlar
cat > /etc/sysctl.d/99-nat64.conf <<EOF
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.default.disable_ipv6 = 0
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.eth0.forwarding = 1
EOF
# Ayarları uygula
sysctl --system

echo ">>> [5/7] Tayga Konfigürasyonu Yazılıyor..."
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

echo ">>> [6/7] Akıllı Tayga Servisi (Docker Uyumlu) Oluşturuluyor..."
# Bu servis dosyası Docker'dan sonra başlar ve kuralları dinamik ekler
cat > /etc/systemd/system/tayga.service <<EOF
[Unit]
Description=Tayga NAT64 Service
# KRITIK: Docker ve Network tamamen hazir olunca basla
After=network.target docker.service

[Service]
Type=simple
ExecStart=/usr/sbin/tayga --nodetach

# Kartın oluşması için bekleme süresi
ExecStartPost=/usr/bin/sleep 5

# --- Kilitleri ve Yonlendirmeyi ZORLA Ac ---
ExecStartPost=/usr/sbin/sysctl -w net.ipv6.conf.nat64.disable_ipv6=0
ExecStartPost=/usr/sbin/sysctl -w net.ipv6.conf.all.forwarding=1
ExecStartPost=/usr/sbin/sysctl -w net.ipv6.conf.eth0.forwarding=1

# --- Sanal Arayuz ve Rotalar ---
ExecStartPost=-/usr/sbin/ip link set nat64 up
ExecStartPost=-/usr/sbin/ip addr replace 192.168.255.1 dev nat64
ExecStartPost=-/usr/sbin/ip route replace 192.168.255.0/24 dev nat64
ExecStartPost=-/usr/sbin/ip -6 route replace 64:ff9b::/96 dev nat64

# --- NAT KURALLARI (Docker Uyumlu) ---
# Once temizle (Mukerrer kayit olmasin)
ExecStartPost=-/usr/sbin/iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
ExecStartPost=-/usr/sbin/iptables -D FORWARD -i eth0 -o nat64 -m state --state RELATED,ESTABLISHED -j ACCEPT
ExecStartPost=-/usr/sbin/iptables -D FORWARD -i nat64 -o eth0 -j ACCEPT

# Sonra ekle (Listenin en altina eklenir, boylece Docker'i bozmaz)
ExecStartPost=/usr/sbin/iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
ExecStartPost=/usr/sbin/iptables -A FORWARD -i eth0 -o nat64 -m state --state RELATED,ESTABLISHED -j ACCEPT
ExecStartPost=/usr/sbin/iptables -A FORWARD -i nat64 -o eth0 -j ACCEPT

Restart=always

[Install]
WantedBy=multi-user.target
EOF

echo ">>> [7/7] Servisler Başlatılıyor ve Temizlik Yapılıyor..."
# Firewalld kapat (iptables ile çakışır)
systemctl stop firewalld
systemctl disable firewalld
systemctl mask firewalld

# Eski iptables servisini kapat
systemctl stop iptables
systemctl disable iptables

# Çakışan kuralları temizle (NFTables Flush) - Temiz sayfa aç
nft flush ruleset

# Önce Docker'ı başlat
echo ">>> Docker yeniden başlatılıyor..."
systemctl restart docker

# Sonra Tayga'yı başlat
echo ">>> Tayga başlatılıyor..."
systemctl daemon-reload
systemctl enable tayga
systemctl restart tayga

echo "============================================="
echo "✅ KURULUM BAŞARIYLA TAMAMLANDI!"
echo " UUID: $CURRENT_UUID kullanıldı."
echo " Test için Client sunucusundan (193) ping atın:"
echo " ping6 64:ff9b::8.8.8.8"
echo "============================================="
