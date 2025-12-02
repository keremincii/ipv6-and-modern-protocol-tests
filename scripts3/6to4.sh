#!/bin/bash

# 1. Varsa eski tüneli temizle
ip tunnel del tun6to4 2>/dev/null

# 2. IPv6 Forwarding'i genel olarak aç (Gateway olduğu için şart)
sysctl -w net.ipv6.conf.all.forwarding=1

# 3. Tünel arayüzünü oluştur (Public IP: 212.253.95.27)
ip tunnel add tun6to4 mode sit remote any local 212.253.95.27 ttl 64

# 4. KRİTİK ADIM: Tünel arayüzünde IPv6'yı zorla aktif et
# (Az önce aldığın "Permission denied" hatasını bu engeller)
sysctl -w net.ipv6.conf.tun6to4.disable_ipv6=0

# 5. Arayüzü ayağa kaldır
ip link set dev tun6to4 up

# 6. 6to4 IPv6 adresini ata
ip -6 addr add 2002:d4fd:5f1b::1/16 dev tun6to4

# 7. Routing'i ayarla (2002:: trafiğini tünele it)
ip -6 route add 2002::/16 dev tun6to4

# Bitti! Kontrol edelim:
echo "Kurulum tamamlandı. Arayüz durumu:"
ip addr show tun6to4
