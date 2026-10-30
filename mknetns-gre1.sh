#!/bin/bash

# Setup a bridge and veth pairs to network namespaces to run dedicated GRE endpoints.
# With this architecture, multiple Zscaler endpoints and probes can be served:
# - Isolated from the host OS routing table
# - Supporting multiple identical setups with separate L7 health check listeners
#
# References:
# - https://routemyip.com/posts/linux/networking/gre-tunnels/
# - https://docs.kernel.org/networking/tuntap.html

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

NIC="enp0s25"

echo -e "${GREEN}=== GRE Zscaler Simulator - Network Setup ===${NC}"
echo ""

# Function to cleanup on error
cleanup_on_error() {
    echo -e "${RED}Error occurred! Attempting to restore network connectivity...${NC}"
    ip link set dev "$NIC" up 2>/dev/null || true
    dhclient "$NIC" 2>/dev/null || true
    systemctl start NetworkManager 2>/dev/null || true
    exit 1
}

trap cleanup_on_error ERR

# Pre-flight checks
echo -e "${YELLOW}Running pre-flight checks...${NC}"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root${NC}" 
   exit 1
fi

# Check if physical interface exists
if ! ip link show "$NIC" &>/dev/null; then
    echo -e "${RED}Error: Network interface $NIC does not exist${NC}"
    echo "Available interfaces:"
    ip -o link show | awk -F': ' '{print "  - " $2}'
    exit 1
fi

# Check if interface is already part of a bridge
CURRENT_MASTER=$(ip -json link show "$NIC" | jq -r '.[].master // empty')
if [ -n "$CURRENT_MASTER" ]; then
    echo -e "${RED}Error: $NIC is already enslaved to bridge/master: $CURRENT_MASTER${NC}"
    echo "You need to remove it first:"
    echo "  sudo ip link set $NIC nomaster"
    exit 1
fi

# Check for macvlan interfaces using this physical interface as parent
echo -e "${YELLOW}Checking for macvlan interfaces on $NIC...${NC}"

# Get the interface index of our NIC
NIC_INDEX=$(ip -json link show "$NIC" | jq -r '.[].ifindex')

# Check in default namespace
MACVLAN_CHILDREN=$(ip -json link show | jq -r ".[] | select(.link == \"$NIC\" and .linkinfo.info_kind == \"macvlan\") | .ifname" 2>/dev/null)

# Check in all namespaces
MACVLAN_IN_NS=""
for ns in $(ip netns list | awk '{print $1}'); do
    # Look for macvlan@if<NIC_INDEX> pattern in each namespace
    MACVLAN_FOUND=$(ip netns exec "$ns" ip -d link show 2>/dev/null | grep -o "macvlan[^@]*@if${NIC_INDEX}" | cut -d@ -f1)
    if [ -n "$MACVLAN_FOUND" ]; then
        MACVLAN_IN_NS="${MACVLAN_IN_NS}${ns}:${MACVLAN_FOUND} "
    fi
done

if [ -n "$MACVLAN_CHILDREN" ] || [ -n "$MACVLAN_IN_NS" ]; then
    echo -e "${RED}Error: macvlan interfaces are attached to $NIC (if${NIC_INDEX}):${NC}"
    
    if [ -n "$MACVLAN_CHILDREN" ]; then
        echo "  In default namespace:"
        echo "$MACVLAN_CHILDREN" | sed 's/^/    - /'
    fi
    
    if [ -n "$MACVLAN_IN_NS" ]; then
        echo "  In network namespaces:"
        for entry in $MACVLAN_IN_NS; do
            ns=$(echo "$entry" | cut -d: -f1)
            macvlan=$(echo "$entry" | cut -d: -f2)
            echo "    - $macvlan (in namespace: $ns)"
        done
    fi
    
    echo ""
    echo -e "${YELLOW}This blocks adding $NIC to a bridge.${NC}"
    echo "This is likely from a companion VeloCloud LAN/client lab script:"
    echo "  velocloud-lan-client-netns-macvlan-setup.sh"
    echo ""
    echo -e "${YELLOW}You have 3 options:${NC}"
    echo ""
    echo "1. Remove macvlan interfaces (labs cannot run together):"
    
    if [ -n "$MACVLAN_IN_NS" ]; then
        for entry in $MACVLAN_IN_NS; do
            ns=$(echo "$entry" | cut -d: -f1)
            macvlan=$(echo "$entry" | cut -d: -f2)
            echo "     sudo ip netns exec $ns ip link del $macvlan"
        done
    fi
    
    if [ -n "$MACVLAN_CHILDREN" ]; then
        for macvlan in $MACVLAN_CHILDREN; do
            echo "     sudo ip link del $macvlan"
        done
    fi
    
    echo ""
    echo "2. Migrate macvlan to use bridge br1 (allows both labs to coexist):"
    echo "     This script can do it automatically if you continue"
    echo ""
    echo "3. Abort and keep current setup"
    echo ""
    
    read -p "Choose option (1=remove, 2=migrate, 3=abort) [3]: " MACVLAN_OPTION
    MACVLAN_OPTION=${MACVLAN_OPTION:-3}
    
    case $MACVLAN_OPTION in
        1)
            echo ""
            echo -e "${YELLOW}Removing macvlan interfaces...${NC}"
            if [ -n "$MACVLAN_IN_NS" ]; then
                for entry in $MACVLAN_IN_NS; do
                    ns=$(echo "$entry" | cut -d: -f1)
                    macvlan=$(echo "$entry" | cut -d: -f2)
                    ip netns exec "$ns" ip link del "$macvlan" && echo "  ✓ Removed $macvlan from $ns" || echo "  ✗ Failed to remove $macvlan"
                done
            fi
            if [ -n "$MACVLAN_CHILDREN" ]; then
                for macvlan in $MACVLAN_CHILDREN; do
                    ip link del "$macvlan" && echo "  ✓ Removed $macvlan" || echo "  ✗ Failed to remove $macvlan"
                done
            fi
            echo -e "${GREEN}Macvlan interfaces removed. Continuing setup...${NC}"
            echo ""
            ;;
        2)
            echo ""
            echo -e "${YELLOW}Migration will happen after bridge br1 is created${NC}"
            echo "The macvlan interfaces will be automatically migrated to use br1 as parent"
            echo ""
            MIGRATE_MACVLAN=true
            ;;
        3|*)
            echo "Aborted."
            exit 1
            ;;
    esac
else
    echo -e "${GREEN}  No macvlan interfaces found on $NIC${NC}"
fi

# Check if interface is in any bridge using brctl
if command -v brctl &>/dev/null; then
    if brctl show 2>/dev/null | grep -q "$NIC"; then
        BRIDGE_NAME=$(brctl show 2>/dev/null | grep "$NIC" | awk '{print $1}')
        echo -e "${RED}Error: $NIC is in bridge: $BRIDGE_NAME${NC}"
        echo "Remove it first:"
        echo "  sudo ip link set $NIC nomaster"
        echo "  # or"
        echo "  sudo brctl delif $BRIDGE_NAME $NIC"
        exit 1
    fi
fi

# Check if br1 already exists
if ip link show br1 &>/dev/null; then
    echo -e "${YELLOW}Warning: Bridge br1 already exists${NC}"
    # Check if it has the expected configuration
    BR1_SLAVES=$(bridge link show | grep "master br1" | awk '{print $2}' | cut -d: -f1 | tr '\n' ' ')
    echo "  Current slaves: $BR1_SLAVES"
    
    # If it doesn't have enp0s25, it's from a previous incomplete setup
    if ! echo "$BR1_SLAVES" | grep -q "$NIC"; then
        echo -e "${RED}  Bridge exists but $NIC is not attached (incomplete setup)${NC}"
        echo "  Clean it up first:"
        echo "    sudo ./cleanup.sh"
        echo "  Or manually:"
        echo "    sudo ip link del br1"
        exit 1
    fi
fi

# Check if namespaces already exist
if ip netns list | grep -q "^gre1"; then
    echo -e "${RED}Error: Network namespace gre1 already exists${NC}"
    echo "Clean it up first with: sudo ip netns del gre1"
    exit 1
fi

if ip netns list | grep -q "^gre2"; then
    echo -e "${RED}Error: Network namespace gre2 already exists${NC}"
    echo "Clean it up first with: sudo ip netns del gre2"
    exit 1
fi

# Check if veth pairs already exist
if ip link show veth-a1 &>/dev/null; then
    echo -e "${RED}Error: veth-a1 already exists${NC}"
    echo "Clean it up first with: sudo ip link del veth-a1"
    exit 1
fi

if ip link show veth-a2 &>/dev/null; then
    echo -e "${RED}Error: veth-a2 already exists${NC}"
    echo "Clean it up first with: sudo ip link del veth-a2"
    exit 1
fi

# Check for required tools
for cmd in jq dhclient; do
    if ! command -v $cmd &>/dev/null; then
        echo -e "${RED}Error: Required command '$cmd' not found${NC}"
        echo "Install it with: sudo apt install $cmd"
        exit 1
    fi
done

# Check for TUN/TAP devices that might interfere
echo -e "${YELLOW}Checking for TUN/TAP devices...${NC}"
TUNTAP_DEVICES=$(ip tuntap list 2>/dev/null)
if [ -n "$TUNTAP_DEVICES" ]; then
    echo -e "${YELLOW}  Found TUN/TAP devices:${NC}"
    echo "$TUNTAP_DEVICES" | sed 's/^/    /'
    
    # Check if any are attached to our NIC or bridge
    for device in $(echo "$TUNTAP_DEVICES" | awk '{print $1}' | cut -d: -f1); do
        DEVICE_MASTER=$(ip -json link show "$device" 2>/dev/null | jq -r '.[].master // empty')
        if [ "$DEVICE_MASTER" = "br1" ] || [ "$DEVICE_MASTER" = "$NIC" ]; then
            echo -e "${RED}  Error: TUN/TAP device $device is attached to $DEVICE_MASTER${NC}"
            echo "  This may cause conflicts. Remove it first:"
            echo "    sudo ip link del $device"
            exit 1
        fi
    done
    echo -e "${GREEN}  No conflicts detected${NC}"
else
    echo -e "${GREEN}  No TUN/TAP devices found${NC}"
fi

echo -e "${GREEN}✓ All pre-flight checks passed${NC}"
echo ""

# Save current IP for reference
CURRENT_IP=$(ip -4 addr show "$NIC" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || echo "none")
echo -e "${YELLOW}Current IP on $NIC: $CURRENT_IP${NC}"
echo ""

read -p "WARNING: This will temporarily disconnect your network. Continue? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo -e "${GREEN}Starting network reconfiguration...${NC}"

# Enable GRE module on the host
modprobe ip_gre

# Reference: https://superuser.com/questions/1204229/bridge-virtual-interface-into-physical-network
echo -e "${YELLOW}[1/7] Stopping NetworkManager...${NC}"
systemctl stop NetworkManager

echo -e "${YELLOW}[2/7] Preparing interface $NIC...${NC}"
ip link set dev "$NIC" down 
ip addr flush dev "$NIC"

# Extra check: ensure no lingering routes
ip route flush dev "$NIC" 2>/dev/null || true

# Verify interface is really down and clean
if ip addr show "$NIC" | grep -q "inet "; then
    echo -e "${RED}  Warning: Interface still has IP addresses after flush${NC}"
    ip addr show "$NIC"
fi

echo -e "${YELLOW}[3/7] Creating veth pairs...${NC}"
ip link add veth-a1 type veth peer name veth-b1
ip link set veth-a1 up

ip link add veth-a2 type veth peer name veth-b2
ip link set veth-a2 up

echo -e "${YELLOW}[4/7] Creating bridge br1...${NC}"
# Preserve physical NIC MAC address so DHCP assigns the same lease
ORIG_MAC=$(ip -json link show dev "$NIC" | jq -r .[].address)
echo "  Preserving MAC address: $ORIG_MAC"
ip link add name br1 address "$ORIG_MAC" up type bridge

echo -e "${YELLOW}[5/7] Adding interfaces to bridge...${NC}"
ip link set veth-a1 master br1 && echo "  ✓ Added veth-a1 to br1" || { echo "  ✗ Failed to add veth-a1"; exit 1; }
ip link set veth-a2 master br1 && echo "  ✓ Added veth-a2 to br1" || { echo "  ✗ Failed to add veth-a2"; exit 1; }

echo "  Attempting to add $NIC to br1..."

# Check current state
echo "  Checking $NIC state before adding to bridge:"
ip -brief addr show "$NIC" | sed 's/^/    /'

if ip addr show "$NIC" | grep -q "inet "; then
    echo -e "${YELLOW}  Warning: $NIC still has IP addresses, flushing again...${NC}"
    ip addr flush dev "$NIC"
fi

# Check if dhclient or NetworkManager processes are still running
if pgrep -x dhclient > /dev/null; then
    echo -e "${YELLOW}  Warning: dhclient is still running, killing...${NC}"
    pkill -9 dhclient || true
    sleep 1
fi

echo "  Final state check:"
ip link show "$NIC" | sed 's/^/    /'

if ip link set "$NIC" master br1; then
    echo -e "${GREEN}  ✓ Added $NIC to br1${NC}"
else
    echo -e "${RED}  ✗ Failed to add $NIC to br1${NC}"
    echo ""
    echo "  Diagnostic information:"
    echo "  Running processes related to $NIC:"
    ps aux | grep -E "(dhclient|NetworkManager|wpa_supplicant)" | grep -v grep | sed 's/^/    /'
    echo "  Interface detailed info:"
    ip -d link show "$NIC" | sed 's/^/    /'
    exit 1
fi
 
echo -e "${YELLOW}[6/7] Bringing up bridge and interface...${NC}"
ip link set "$NIC" up
ip link set br1 up

# Migrate macvlan interfaces if option 2 was chosen
if [ "${MIGRATE_MACVLAN:-false}" = "true" ]; then
    echo ""
    echo -e "${YELLOW}[MIGRATION] Migrating macvlan interfaces to bridge br1...${NC}"
    
    # Re-check for macvlan interfaces
    if [ -n "$MACVLAN_IN_NS" ]; then
        for entry in $MACVLAN_IN_NS; do
            ns=$(echo "$entry" | cut -d: -f1)
            macvlan=$(echo "$entry" | cut -d: -f2)
            
            echo "  Migrating $macvlan in namespace $ns..."
            
            # Get current configuration
            OLD_IP=$(ip netns exec "$ns" ip -4 addr show "$macvlan" | grep -oP '(?<=inet\s)\S+' || echo "")
            OLD_STATE=$(ip netns exec "$ns" ip link show "$macvlan" | grep -oP '(?<=state\s)\w+' || echo "UP")
            
            # Delete old macvlan
            ip netns exec "$ns" ip link del "$macvlan"
            
            # Create new macvlan using br1 as parent
            ip link add "$macvlan" link br1 type macvlan mode bridge
            
            # Move to namespace
            ip link set "$macvlan" netns "$ns"
            
            # Restore IP if it had one
            if [ -n "$OLD_IP" ]; then
                ip netns exec "$ns" ip addr add "$OLD_IP" dev "$macvlan"
                echo "    ✓ Restored IP: $OLD_IP"
            fi
            
            # Bring up if it was up
            if [ "$OLD_STATE" = "UP" ] || [ "$OLD_STATE" = "UNKNOWN" ]; then
                ip netns exec "$ns" ip link set "$macvlan" up
                echo "    ✓ Brought interface up"
            fi
            
            # Restore routes if needed (for nshost)
            if [ "$ns" = "nshost" ] && [ -n "$OLD_IP" ]; then
                # Extract just the network from IP (e.g., 192.168.1.252/24 -> 192.168.1)
                NETWORK=$(echo "$OLD_IP" | cut -d. -f1-3)
                ip netns exec "$ns" ip route add 0.0.0.0/0 via "${NETWORK}.254" 2>/dev/null || true
                echo "    ✓ Restored default route"
            fi
            
            echo -e "${GREEN}    ✓ Successfully migrated $macvlan to br1${NC}"
        done
    fi
    
    if [ -n "$MACVLAN_CHILDREN" ]; then
        for macvlan in $MACVLAN_CHILDREN; do
            echo "  Migrating $macvlan in default namespace..."
            
            OLD_IP=$(ip -4 addr show "$macvlan" | grep -oP '(?<=inet\s)\S+' || echo "")
            OLD_STATE=$(ip link show "$macvlan" | grep -oP '(?<=state\s)\w+' || echo "UP")
            
            ip link del "$macvlan"
            ip link add "$macvlan" link br1 type macvlan mode bridge
            
            if [ -n "$OLD_IP" ]; then
                ip addr add "$OLD_IP" dev "$macvlan"
                echo "    ✓ Restored IP: $OLD_IP"
            fi
            
            if [ "$OLD_STATE" = "UP" ] || [ "$OLD_STATE" = "UNKNOWN" ]; then
                ip link set "$macvlan" up
                echo "    ✓ Brought interface up"
            fi
            
            echo -e "${GREEN}    ✓ Successfully migrated $macvlan to br1${NC}"
        done
    fi
    
    echo ""
    echo -e "${GREEN}✓ Macvlan migration complete!${NC}"
    echo -e "${YELLOW}  Note: Both labs can now coexist on the same physical interface${NC}"
    echo ""
fi

echo -e "${YELLOW}[7/7] Obtaining DHCP lease for br1...${NC}"
dhclient br1

NEW_IP=$(ip -4 addr show br1 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || echo "failed")
if [ "$NEW_IP" = "failed" ]; then
    echo -e "${RED}Failed to obtain DHCP lease!${NC}"
    cleanup_on_error
fi
echo -e "${GREEN}  Bridge IP: $NEW_IP${NC}"
echo ""

echo -e "${YELLOW}Creating network namespaces...${NC}"
ip netns add gre1
ip netns add gre2
echo -e "${GREEN}  Created: gre1, gre2${NC}"

echo -e "${YELLOW}Moving veth endpoints to namespaces...${NC}"
ip link set veth-b1 netns gre1
ip link set veth-b2 netns gre2
echo -e "${GREEN}  veth-b1 → gre1${NC}"
echo -e "${GREEN}  veth-b2 → gre2${NC}"

echo ""
echo -e "${GREEN}=== Setup Complete ===${NC}"
echo ""
echo "Network namespaces created:"
ip netns list
echo ""
echo "Bridge status:"
bridge link show
echo ""
echo -e "${YELLOW}Next step: Run sudo ./doit.sh to configure GRE tunnels${NC}"

