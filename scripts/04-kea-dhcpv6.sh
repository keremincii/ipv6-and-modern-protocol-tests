#!/bin/bash

CONFIG_FILE="/etc/kea/kea-dhcp6.conf"
SERVICE_NAME="kea-dhcp6"

echo "--- Kea DHCPv6 Konfigürasyon Scripti Başlatılıyor ---"

# 1. Mevcut dosyanın yedeğini al (varsa)
if [ -f "$CONFIG_FILE" ]; then
    echo ">> Mevcut konfigürasyon yedekleniyor: ${CONFIG_FILE}.bak"
    cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
fi

# 2. Yeni konfigürasyonu yaz
echo ">> Yeni konfigürasyon dosyaya yazılıyor..."
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
            "subnet": "2001:db8:50::/64",
            "pools": [ { "pool": "2001:db8:50::100 - 2001:db8:50::200" } ],
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

# 3. İzinleri ayarla (Kea genelde root veya kea kullanıcısı ile okur, garanti olsun)
chmod 644 "$CONFIG_FILE"

# 4. Servisi yeniden başlat
echo ">> $SERVICE_NAME servisi yeniden başlatılıyor..."
systemctl restart "$SERVICE_NAME"

# 5. Durum kontrolü
if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo "✅ BAŞARILI: Kea DHCPv6 servisi çalışıyor."
    echo "   Logları kontrol etmek için: journalctl -u $SERVICE_NAME -f"
else
    echo "❌ HATA: Servis başlatılamadı. Lütfen konfigürasyonu kontrol edin."
    systemctl status "$SERVICE_NAME" --no-pager
fi
