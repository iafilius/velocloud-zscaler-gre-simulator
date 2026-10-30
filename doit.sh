#!/bin/bash

# Reference: https://github.com/Jamesits/linux-gre-keepalive/issues/1
#
# Concept: Using a single Linux host to simulate Zscaler ZIA GRE datacenter endpoints
# (Primary and Secondary across Production and Guest pools) for a dual-WAN VeloCloud SD-WAN Edge.
# Configures IP aliases and 8 GRE tunnels inside isolated network namespaces (gre1 and gre2).

IF1="veth-b1"
IF2="veth-b2"

EDGEIP_GE1="192.168.1.64"
EDGEIP_GE2="192.168.1.65"

# Zscaler Prod endpoints
LOCALIP_1="192.168.1.240"   # Master / Primary DC
LOCALIP_2="192.168.1.241"   # Backup / Secondary DC

# Zscaler Guest endpoints
LOCALIP_3="192.168.1.242"   # Master / Primary DC
LOCALIP_4="192.168.1.243"   # Backup / Secondary DC

# Zscaler Prod GE1 inner /30 tunnel IPs
GRETUNNELIP_1="172.21.12.162/30"    # ZIA ZEN IP/Mask (peer Edge router IP: 172.21.12.161)
GRETUNNELIP_2="172.21.12.166/30"    # ZIA ZEN IP/Mask (peer Edge router IP: 172.21.12.165)

# Zscaler Prod GE2 inner /30 tunnel IPs
GRETUNNELIP_3="172.21.12.154/30"    # ZIA ZEN IP/Mask (peer Edge router IP: 172.21.12.153)
GRETUNNELIP_4="172.21.12.158/30"    # ZIA ZEN IP/Mask (peer Edge router IP: 172.21.12.157)

# Zscaler Guest GE1 inner /30 tunnel IPs
GRETUNNELIP_5="172.20.67.74/30"     # ZIA ZEN IP/Mask (peer Edge router IP: 172.20.67.73)
GRETUNNELIP_6="172.20.67.78/30"     # ZIA ZEN IP/Mask (peer Edge router IP: 172.20.67.77)

# Zscaler Guest GE2 inner /30 tunnel IPs
GRETUNNELIP_7="172.20.67.66/30"     # ZIA ZEN IP/Mask (peer Edge router IP: 172.20.67.65)
GRETUNNELIP_8="172.20.67.70/30"     # ZIA ZEN IP/Mask (peer Edge router IP: 172.20.67.69)

# Bring up namespace veth interfaces before adding IP aliases
ip -n gre1 link set dev ${IF1} up
ip -n gre2 link set dev ${IF2} up

# Configure simulated Zscaler public VIPs as IP aliases on veth interfaces
# Zscaler Prod endpoint (Master GE1/GE2)
ip -n gre1 addr add ${LOCALIP_1}/24 dev ${IF1} label ${IF1}:gre1_1
# Zscaler Prod endpoint (Backup GE1/GE2)
ip -n gre2 addr add ${LOCALIP_2}/24 dev ${IF2} label ${IF2}:gre2_2

# Zscaler Guest endpoint (Master GE1/GE2)
ip -n gre1 addr add ${LOCALIP_3}/24 dev ${IF1} label ${IF1}:gre1_3
# Zscaler Guest endpoint (Backup GE1/GE2)
ip -n gre2 addr add ${LOCALIP_4}/24 dev ${IF2} label ${IF2}:gre2_4

# Add default routes in namespaces to allow outbound internet forwarding for functional testing
ip -n gre1 route add default via 192.168.1.254 2>/dev/null || ip -n gre1 route replace default via 192.168.1.254
ip -n gre2 route add default via 192.168.1.254 2>/dev/null || ip -n gre2 route replace default via 192.168.1.254

# References:
# - https://bitlaunch.io/blog/what-is-a-gre-tunnel-and-how-to-set-one-up/
# - https://community.hetzner.com/tutorials/linux-setup-gre-tunnel

# Setup Prod/gre1 Primary (GE1)
ip -n gre1 tunnel add gre1 mode gre local ${LOCALIP_1} remote ${EDGEIP_GE1} ttl 255
ip -n gre1 addr add ${GRETUNNELIP_1} peer 172.21.12.161 dev gre1
ip -n gre1 link set dev gre1 up

# Setup Prod/gre2 Secondary (GE1)
ip -n gre2 tunnel add gre2 mode gre local ${LOCALIPIP_2:-$LOCALIP_2} remote ${EDGEIP_GE1} ttl 255
ip -n gre2 addr add ${GRETUNNELIP_2} peer 172.21.12.165 dev gre2
ip -n gre2 link set dev gre2 up

# Setup Prod/gre11 Primary (GE2)
ip -n gre1 tunnel add gre11 mode gre local ${LOCALIP_1} remote ${EDGEIP_GE2} ttl 255
ip -n gre1 addr add ${GRETUNNELIP_3} peer 172.21.12.153 dev gre11
ip -n gre1 link set dev gre11 up

# Setup Prod/gre12 Secondary (GE2)
ip -n gre2 tunnel add gre12 mode gre local ${LOCALIP_2} remote ${EDGEIP_GE2} ttl 255
ip -n gre2 addr add ${GRETUNNELIP_4} peer 172.21.12.157 dev gre12
ip -n gre2 link set dev gre12 up

# Setup Guest/gre21 Primary (GE1)
ip -n gre1 tunnel add gre21 mode gre local ${LOCALIP_3} remote ${EDGEIP_GE1} ttl 255
ip -n gre1 addr add ${GRETUNNELIP_5} peer 172.20.67.73 dev gre21
ip -n gre1 link set dev gre21 up

# Setup Guest/gre22 Secondary (GE1)
ip -n gre2 tunnel add gre22 mode gre local ${LOCALIP_4} remote ${EDGEIP_GE1} ttl 255
ip -n gre2 addr add ${GRETUNNELIP_6} peer 172.20.67.77 dev gre22
ip -n gre2 link set dev gre22 up

# Setup Guest/gre31 Primary (GE2)
ip -n gre1 tunnel add gre31 mode gre local ${LOCALIP_3} remote ${EDGEIP_GE2} ttl 255
ip -n gre1 addr add ${GRETUNNELIP_7} peer 172.20.67.65 dev gre31
ip -n gre1 link set dev gre31 up

# Setup Guest/gre32 Secondary (GE2)
ip -n gre2 tunnel add gre32 mode gre local ${LOCALIP_4} remote ${EDGEIP_GE2} ttl 255
ip -n gre2 addr add ${GRETUNNELIP_8} peer 172.20.67.69 dev gre32
ip -n gre2 link set dev gre32 up

# ============================================================================
# ROUTING PROBLEM: Direct Attached Network (172.16.0.0/24) Return Path
# ============================================================================
# 
# PROBLEM DESCRIPTION:
# Traffic from VeloCloud Direct Attached / Guest network (172.16.0.0/24)
# arrives via GRE tunnels (gre1, gre11, gre21, or gre31 in gre1 namespace).
# After MASQUERADE NAT, traffic goes out veth-b1 to internet with source IP
# changed to 192.168.1.240 or 192.168.1.242.
#
# Reply traffic arrives back with dst=192.168.1.240, gets un-NATted by 
# conntrack to dst=172.16.0.14, but there is NO ROUTE for 172.16.0.0/24 in
# the routing table by default. Without a route, traffic hits the default route
# and loops back out veth-b1 instead of going back into the GRE tunnel.
#
# The challenge: Multiple GRE tunnels exist (GE1: gre1/gre21, GE2: gre11/gre31).
# Traffic could arrive via ANY of these tunnels, but we need ONE consistent
# return path (or implement stateful per-tunnel routing).
#
# ============================================================================
# SOLUTION OPTIONS:
# ============================================================================
#
# ----------------------------------------------------------------------------
# Option 1: Static Route (IMPLEMENTED - Simple but not symmetric)
# ----------------------------------------------------------------------------
# Add static route for 172.16.0.0/24 via Guest GRE tunnels (gre21/gre22) and
# 10.23.0.0/24 via Prod GRE tunnels (gre1/gre2).
#
# Pros:
#   - Simple to implement and understand
#   - Works immediately with no additional complexity
#
# Cons:
#   - Not symmetric if traffic arrives on GE2 (gre11/gre31) while replies exit
#     via GE1 (gre1/gre21)
#   - May cause issues with strict stateful RPF inspection on the Edge
#
ip -n gre1 route add 172.16.0.0/24 dev gre21  # Guest/Direct Attached return path
ip -n gre2 route add 172.16.0.0/24 dev gre22
ip -n gre1 route add 10.23.0.0/24 dev gre1    # Prod/Global return path
ip -n gre2 route add 10.23.0.0/24 dev gre2
#
# ----------------------------------------------------------------------------
# Option 2: Connmark-based Policy Routing (Stateful - Complex but symmetric)
# ----------------------------------------------------------------------------
# Mark packets in PREROUTING based on ingress GRE interface, save mark to
# conntrack, restore mark on reply packets, and use policy routing tables to
# send replies back through the exact tunnel they arrived on.
#
# Implementation sketch:
#   ip netns exec gre1 iptables -t mangle -A PREROUTING -i gre1  -j CONNMARK --set-mark 1
#   ip netns exec gre1 iptables -t mangle -A PREROUTING -i gre11 -j CONNMARK --set-mark 11
#   ip netns exec gre1 iptables -t mangle -A PREROUTING -i gre21 -j CONNMARK --set-mark 21
#   ip netns exec gre1 iptables -t mangle -A PREROUTING -i gre31 -j CONNMARK --set-mark 31
#   ip netns exec gre1 iptables -t mangle -A PREROUTING -i veth-b1 -j CONNMARK --restore-mark
#
#   ip netns exec gre1 ip rule add fwmark 1  table 101
#   ip netns exec gre1 ip rule add fwmark 11 table 111
#   ip netns exec gre1 ip rule add fwmark 21 table 121
#   ip netns exec gre1 ip rule add fwmark 31 table 131
#
#   ip netns exec gre1 ip route add 10.23.0.0/24  dev gre1  table 101
#   ip netns exec gre1 ip route add 10.23.0.0/24  dev gre11 table 111
#   ip netns exec gre1 ip route add 172.16.0.0/24 dev gre21 table 121
#   ip netns exec gre1 ip route add 172.16.0.0/24 dev gre31 table 131
#
# ----------------------------------------------------------------------------
# Option 3: Separate Namespace per GRE Endpoint (8 Namespaces - 1:1 Isolation)
# ----------------------------------------------------------------------------
# Create a dedicated namespace for each GRE tunnel endpoint (8 namespaces ×
# 1 tunnel each = 8 tunnels total) so each namespace has exactly one GRE
# interface and trivial symmetric routing.
# See docs/DEEP_DIVE_NAMESPACES_AND_ROUTING.md for full architectural comparison.
# ============================================================================

# Adjust namespace firewall rules
ip netns exec gre1 iptables -I INPUT -i gre1 -j ACCEPT
ip netns exec gre1 iptables -I FORWARD -j ACCEPT

ip netns exec gre2 iptables -I INPUT -i gre2 -j ACCEPT
ip netns exec gre2 iptables -I FORWARD -j ACCEPT

# ============================================================================
# CRITICAL: LAN GATEWAY ROUTE REQUIREMENT FOR END-TO-END TCP TRAFFIC
# ============================================================================
# For return TCP traffic from the upstream router (192.168.1.254) to reach
# the NATted namespace IPs (192.168.1.240-243), ensure proxy ARP is enabled on
# br1 and the physical NIC, or configure a static route on the LAN gateway.
# ============================================================================
ip netns exec gre1 iptables -t nat -A POSTROUTING -s 172.16.0.0/24 -j MASQUERADE  # Guest/Direct Attached
ip netns exec gre2 iptables -t nat -A POSTROUTING -s 172.16.0.0/24 -j MASQUERADE
ip netns exec gre1 iptables -t nat -A POSTROUTING -s 10.23.0.0/24 -j MASQUERADE   # Prod/Global
ip netns exec gre2 iptables -t nat -A POSTROUTING -s 10.23.0.0/24 -j MASQUERADE

# Flush conntrack tables to ensure NAT rules apply cleanly to new connections
ip netns exec gre1 conntrack -F 2>/dev/null || true
ip netns exec gre2 conntrack -F 2>/dev/null || true

# Enable accept_local in both namespaces
ip netns exec gre1 sysctl net.ipv4.conf.default.accept_local=1
ip netns exec gre1 sysctl net.ipv4.conf.all.accept_local=1

ip netns exec gre2 sysctl net.ipv4.conf.default.accept_local=1
ip netns exec gre2 sysctl net.ipv4.conf.all.accept_local=1

# Allow VeloCloud Edge traffic (GE1/GE2) across bridge on host
iptables -I INPUT -i br1 -s 192.168.1.64 -j ACCEPT
iptables -I OUTPUT -o br1 -s 192.168.1.64 -j ACCEPT
iptables -I FORWARD -i br1 -o br1 -s 192.168.1.64 -j ACCEPT 
iptables -I FORWARD -i br1 -o br1 -s 192.168.1.65 -j ACCEPT

# Allow simulated Zscaler endpoint IPs (192.168.1.240-243) for NATted traffic
iptables -I FORWARD -s 192.168.1.240/30 -j ACCEPT
iptables -I FORWARD -d 192.168.1.240/30 -j ACCEPT
iptables -I INPUT   -d 192.168.1.240/30 -j ACCEPT

# Enable IPv4 forwarding inside namespaces
ip netns exec gre1 sysctl -w net.ipv4.ip_forward=1 >/dev/null
ip netns exec gre2 sysctl -w net.ipv4.ip_forward=1 >/dev/null

# Enable proxy ARP on bridge and physical interface
sysctl -w net.ipv4.conf.br1.proxy_arp=1 >/dev/null
sysctl -w net.ipv4.conf.enp0s25.proxy_arp=1 >/dev/null

