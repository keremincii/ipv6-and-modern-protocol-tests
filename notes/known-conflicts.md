# Bilinen Çakışmalar

1) NetworkManager, `IPV6_AUTOCONF=no` olsa bile RA görünce tekrar
ikinci bir IPv6 adres ekleyebilir.

2) Kernel bazen iki tane `/64` route ekler (metric farkı ile).

3) IPv6 default route zaman zaman kaybolabilir, rc.local bunu garantiye alır.

4) fe80::1 link-local adresi NetworkManager tarafından eklenmediği için
manuel olarak rc.local ile verildi.
