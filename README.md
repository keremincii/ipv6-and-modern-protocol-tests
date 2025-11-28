# IPv6 Pure Network Test Master Scripts

Bu repo, saf IPv6 ortamında Oracle Linux / RHEL / CentOS sistemlerinde
NetworkManager ile manuel IPv6 adreslemeyi aynı anda kullanırken çıkan
çakışmaları çözmek için oluşturulmuş test scriptlerini içerir.

## İçerik
- `scripts/` → 3 aşamalı IPv6 yapılandırma scriptleri
- `examples/` → örnek ifcfg ve rc.local dosyaları
- `notes/` → bilinen çakışmaların açıklamaları

## Kullanım
Sırasıyla aşağıdaki dosyaları çalıştır:

1. `scripts/01-ifcfg-setup.md`  
2. `scripts/02-sysctl-setup.sh`  
3. `scripts/03-rc-local-setup.sh`

İşlem sonrası sistem tamamen saf IPv6 çalışabilir hale gelir.
