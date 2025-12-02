#!/bin/bash

# =======================================================
# TERMINATOR SCRIPT: 6to4 Tunnel (Auto-Fix IPv6 Blocks)
# =======================================================

# --- AYARLAR ---
TUNNEL_NAME="tun6to4"
LOCAL_IP="10.38.1.180"
IPV6_ADDR="2002:d4fd:5f1b::1/16"
IPV6_ROUTE="2002::/16"

echo "[1/4] KÖTÜ AYARLAR TEMİZLENİYOR (/etc/sysctl.conf)..."

# --- AKILLI DÜZELTME MODÜLÜ ---
# Regex Kullanıyoruz (-E):
# "disable_ipv6" kelimesini bul, sonra ne kadar boşluk varsa geç,
# "=" işaretini bul, yine boşlukları geç ve "1" rakamını bul.
# Bulduğun her şeyi "disable_ipv6 = 0" ile değiştir.

sed -i -E 's/disable_ipv6\s*=\s*1/disable_ipv6 = 0/g' /etc/sysctl.conf
sed -i -E 's/forwarding\s*=\s*0/forwarding = 1/g' /etc/sysctl.conf

echo "   -> IPv6 yasakları kaldırıldı (0 yapıldı)."

echo "[2/4] GARANTİ DOSYASI OLUŞTURULUYOR..."
# Sistem dosyası bozuk olsa bile, bu dosya en son okunur ve düzeltir.
cat <<EOF > /etc/sysctl.d/99-6to4-master.conf
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.default.forwarding = 1
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.default.disable_ipv6 = 0
net.ipv6.conf.lo.disable_ipv6 = 0
net.ipv6.conf.$TUNNEL_NAME.disable_ipv6 = 0
EOF

# Ayarları uygula
sysctl --system > /dev/null 2>&1

echo "[3/4] NETWORK MANAGER İLE TÜNEL KURULUYOR..."
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

echo "[4/4] BAĞLANTI AÇILIYOR..."
nmcli connection up "$TUNNEL_NAME" > /dev/null

echo "=========================================="
echo "İŞLEM TAMAM. SONUÇ:"
# O yasaklı ayarların düzelip düzelmediğini kanıtlayalım:
sysctl net.ipv6.conf.all.disable_ipv6
echo "------------------------------------------"
ip addr show "$TUNNEL_NAME" | grep "inet6"
echo "=========================================="
