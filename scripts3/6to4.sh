#!/bin/bash

# --- 6to4 Tunnel Setup Script (NAT Friendly) ---

# 1. Temizlik: Varsa eski tüneli sil (Hata verirse yoksay)
ip tunnel del tun6to4 2>/dev/null

# 2. Kernel Ayarları: IPv6 Forwarding'i aç
sysctl -w net.ipv6.conf.all.forwarding=1

# 3. Tünel Oluşturma (NAT AYARI)
# remote: any (her yerden gelebilir)
# local: 10.38.1.180 (Senin sunucunun fiziksel iç IP'si - KRİTİK NOKTA)
ip tunnel add tun6to4 mode sit remote any local 10.38.1.180 ttl 64

# 4. Tünel üzerinde IPv6'yı zorla aktif et (Permission denied hatasını önler)
sysctl -w net.ipv6.conf.tun6to4.disable_ipv6=0

# 5. Arayüzü ayağa kaldır
ip link set dev tun6to4 up

# 6. IPv6 Adresini Ata
# Buradaki adres senin PUBLIC IP'nin (212.253.95.27) hex karşılığıdır. Değişmez.
ip -6 addr add 2002:d4fd:5f1b::1/16 dev tun6to4

# 7. Routing Ekle
ip -6 route add 2002::/16 dev tun6to4

echo "6to4 Tüneli (NAT Arkası) Başarıyla Kuruldu."
