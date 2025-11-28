#!/bin/bash

# Install eksikse ekle
grep -q "[Install]" /usr/lib/systemd/system/rc-local.service || cat >> /usr/lib/systemd/system/rc-local.service <<EOF
[Install]
WantedBy=multi-user.target
EOF

# rc.local oluştur
cat > /etc/rc.d/rc.local <<EOF
#!/bin/bash

touch /var/lock/subsys/local

# Özel IPv6 ve Kea başlangıç ayarları

# 1. Link-local (DHCPv6 için gerekli)
ip addr add fe80::1/64 dev eth0 scope link

# 2. Global IPv6 adresi zorla
ip addr add 2001:db8:50::1/64 dev eth0

# 3. Default IPv6 route - [GATEWAY 180 olarak ayarlandığı için]
ip -6 route add default via 2001:db8:50::180 dev eth0

# 4. Kea DHCPv6 restart
systemctl restart kea-dhcp6
EOF

chmod +x /etc/rc.d/rc.local
systemctl daemon-reload
systemctl enable rc-local
systemctl restart rc-local
