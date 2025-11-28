#!/bin/bash

cat >> /etc/sysctl.conf <<EOF

# IPv6 Enable
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.default.disable_ipv6 = 0
net.ipv6.conf.eth0.disable_ipv6 = 0

# IPv6 Forwarding
net.ipv6.conf.all.forwarding = 1

EOF

sysctl -p
