#!/bin/bash

# =======================================================
# COMPLETE MASTER SCRIPT: Tunnel + Kernel + Firewall Fix
# =======================================================

# --- AYARLAR ---
TUNNEL_NAME="tun6to4"
LOCAL_IP="10.38.1.180"           # Sunucu İç IP (NAT)
IPV6_ADDR="2002:d4fd:5f1b::1/16" # 6to4 Adres
IPV6_ROUTE="2002::/16"

echo "[1/5] FIREWALL AYARLARI (PING İZNİ) AÇILIYOR..."
# Eğer firewalld çalışıyorsa ICMP izni ver (Kalıcı Çözüm)
if command -v firewall-cmd >/dev/null 2>&1; then
    if firewall-cmd --state >/dev/null 2>&1; then
        firewall-cmd --permanent --add-protocol=icmp >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
        echo "   -> Firewalld: ICMP (Ping) protokolüne izin verildi."
    else
        echo "   -> Firewalld yüklü ama çalışmıyor, atlanıyor."
    fi
else
    echo "   -> Firewalld bulunamadı, iptables kuralı denenecek..."
    iptables -I INPUT -p icmp --icmp-type echo-request -j ACCEPT >/dev/null 2>&1
fi

echo "[2/5] KÖTÜ KERNEL AYARLARI TEMİZLENİYOR..."
# /etc/sysctl.conf içindeki yasaklı ayarları (disable_ipv6=1) zorla 0 yap
sed -i -E 's/disable_ipv6\s*=\s*1/disable_ipv6 = 0/g' /etc/sysctl.conf
sed -i -E 's/forwarding\s*=\s*0/forwarding = 1/g' /etc/sysctl.conf

echo "[3/5] GARANTİ KERNEL AYARLARI YÜKLENİYOR..."
# Sistem dosyasını oluştur
cat <<EOF > /etc/sysctl.d/99-6to4-master.conf
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.default.forwarding = 1
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.default.disable_ipv6 = 0
net.ipv6.conf.lo.disable_ipv6 = 0
net.ipv6.conf.$TUNNEL_NAME.disable_ipv6 = 0
EOF
# Uygula
sysctl --system > /dev/null 2>&1

echo "[4/5] NETWORK MANAGER TÜNELİ KURULUYOR..."
# Temizlik
nmcli connection delete "$TUNNEL_NAME" > /dev/null 2>&1
ip tunnel del "$TUNNEL_NAME" > /dev/null 2>&1

# Kurulum
nmcli con add type ip-tunnel \
    con-name "$TUNNEL_NAME" \
    ifname "$TUNNEL_NAME" \
    mode sit \
    remote 0.0.0.0 \
    local "$LOCAL_IP" \
    ipv6.method manual \
    ipv6.addresses "$IPV6_ADDR" \
    ipv6.routes "$IPV6_ROUTE" > /dev/null

if [ $? -eq 0 ]; then
    echo "   -> Tünel başarıyla oluşturuldu."
else
    echo "   -> HATA: Tünel kurulamadı!"
    exit 1
fi

echo "[5/5] BAĞLANTI AÇILIYOR..."
nmcli connection up "$TUNNEL_NAME" > /dev/null

echo "=========================================="
echo "TAM KURULUM BAŞARILI. SONUÇ:"
ip addr show "$TUNNEL_NAME" | grep "inet6"
echo "=========================================="
