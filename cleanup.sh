#!/bin/bash

# Cleanup script for GRE Zscaler Simulator
# Removes all network namespaces, tunnels, and bridges

set +e  # Don't exit on error - we want to clean up as much as possible

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

NIC="enp0s25"

echo -e "${GREEN}=== GRE Zscaler Simulator - Cleanup ===${NC}"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root${NC}" 
   exit 1
fi

# Remove GRE tunnels from gre1 namespace
echo -e "${YELLOW}Removing GRE tunnels from gre1 namespace...${NC}"
for tunnel in gre1 gre11 gre21 gre31; do
    if ip netns exec gre1 ip tunnel show "$tunnel" &>/dev/null; then
        ip netns exec gre1 ip tunnel del "$tunnel" && echo "  ✓ Removed $tunnel" || echo "  ✗ Failed to remove $tunnel"
    fi
done

# Remove GRE tunnels from gre2 namespace
echo -e "${YELLOW}Removing GRE tunnels from gre2 namespace...${NC}"
for tunnel in gre2 gre12 gre22 gre32; do
    if ip netns exec gre2 ip tunnel show "$tunnel" &>/dev/null; then
        ip netns exec gre2 ip tunnel del "$tunnel" && echo "  ✓ Removed $tunnel" || echo "  ✗ Failed to remove $tunnel"
    fi
done

# Delete network namespaces
echo -e "${YELLOW}Deleting network namespaces...${NC}"
for ns in gre1 gre2; do
    if ip netns list | grep -q "^$ns"; then
        ip netns del "$ns" && echo "  ✓ Deleted $ns" || echo "  ✗ Failed to delete $ns"
    fi
done

# Remove bridge
echo -e "${YELLOW}Removing bridge br1...${NC}"
if ip link show br1 &>/dev/null; then
    ip link set br1 down 2>/dev/null
    ip link del br1 && echo "  ✓ Removed br1" || echo "  ✗ Failed to remove br1"
fi

# Remove veth pairs (should be auto-removed when namespaces are deleted, but just in case)
echo -e "${YELLOW}Removing veth pairs...${NC}"
for veth in veth-a1 veth-a2 veth-b1 veth-b2; do
    if ip link show "$veth" &>/dev/null; then
        ip link del "$veth" && echo "  ✓ Removed $veth" || echo "  ✗ Failed to remove $veth"
    fi
done

# Check for and remove any TUN/TAP devices attached to br1
echo -e "${YELLOW}Checking for TUN/TAP devices attached to br1...${NC}"
TUNTAP_ON_BR1=$(ip tuntap list 2>/dev/null | awk '{print $1}' | cut -d: -f1 | while read dev; do
    MASTER=$(ip -json link show "$dev" 2>/dev/null | jq -r '.[].master // empty')
    if [ "$MASTER" = "br1" ]; then
        echo "$dev"
    fi
done)

if [ -n "$TUNTAP_ON_BR1" ]; then
    for dev in $TUNTAP_ON_BR1; do
        ip link del "$dev" && echo "  ✓ Removed TUN/TAP device $dev" || echo "  ✗ Failed to remove $dev"
    done
else
    echo "  (none found)"
fi

# Restore physical interface
echo -e "${YELLOW}Restoring physical interface $NIC...${NC}"
ip link set "$NIC" up
dhclient "$NIC"

NEW_IP=$(ip -4 addr show "$NIC" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || echo "none")
echo -e "${GREEN}  $NIC IP: $NEW_IP${NC}"

# Restart NetworkManager
echo -e "${YELLOW}Restarting NetworkManager...${NC}"
systemctl start NetworkManager && echo "  ✓ NetworkManager started" || echo "  ✗ Failed to start NetworkManager"

echo ""
echo -e "${GREEN}=== Cleanup Complete ===${NC}"
echo ""
echo "Remaining network namespaces (should be empty):"
ip netns list || echo "  (none)"

