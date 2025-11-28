# 01 - ifcfg-eth0 yapılandırması

Aşağıdaki içeriği `/etc/sysconfig/network-scripts/ifcfg-eth0`
dosyasına yazın (IP adresleri makineye göre değiştirilmeli).

TYPE=Ethernet
PROXY_METHOD=none
BROWSER_ONLY=no
BOOTPROTO=none
DEVICE=eth0
NAME=eth0
UUID=<MAKİNE-UUID>
ONBOOT=yes
AUTOCONNECT_PRIORITY=-999

IPv6
IPV6ADDR=2001:db8:50::1/64
IPV6INIT=yes
IPV6_AUTOCONF=no
IPV6_DEFROUTE=yes
IPV6_FAILURE_FATAL=no
IPV6_ADDR_GEN_MODE=default
IPV6_DISABLED=no

IPv4
IPADDR=10.38.1.193
GATEWAY=10.38.1.254
DNS1=10.38.1.10
DNS2=8.8.8.8
PREFIX=24
IPV4_FAILURE_FATAL=no
DEFROUTE=yes

css
Kodu kopyala

Değişiklikten sonra:

systemctl restart NetworkManager
