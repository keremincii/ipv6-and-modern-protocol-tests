# Neden bu script gerekli?

NetworkManager, IPv6 autoconf açıkken manuel IPv6 adresi eklemeye
direniyor. Otomatik RA üzerinden adres alınca manuel statik adresi
siliyor. Ayrıca default route bazen kayboluyor.

Bu nedenle:
- IPv6 autoconf kapatıldı
- Manuel IPv6 adres rc.local üzerinden zorlandı
- Default IPv6 route rc.local içine eklendi
- sysctl ile IPv6 disable ayarları kaldırıldı
