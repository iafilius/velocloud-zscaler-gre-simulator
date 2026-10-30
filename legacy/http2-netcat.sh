#!/bin/bash

# Legacy Netcat-based L7 Health Check Responder for Zscaler GRE Simulator
# (Superseded by zscaler_orchestrator_pyroute2.py, kept as a lightweight bash/netcat reference)

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "ERROR: This script must be run as root (use sudo)"
    echo "Usage: sudo $0"
    exit 1
fi

DD=$(date +%d-%m-%Y--%H-%M-%S)

# Expected VeloCloud Edge L7 Probe Request & Response:
#
# GET /vpntest HTTP/1.1
# Host: gateway.zscalertwo.net
# Accept: */*
# User-Agent: VMware SD-WAN
#
# HTTP/1.1 200 OK
# Content-type: text/html
# Content-length: 2
#
# OK

# Note: L7 checks execute outside the GRE tunnel over direct WAN IP connectivity.
# However, if GRE tunnel keepalives/routing are not operational, VCO may still display
# the Cloud Security Service (CSS) status as Failed even when /var/log/l7_health_check.log
# shows zero L7 errors.

# Active L7 health check port assignments can be inspected on the VeloCloud Edge via:
#   /opt/vc/bin/debug.py --l7_health_checks
#
# Example output (synthetic lab UUIDs):
# [
#   {
#     "cloud": "zscaler.net",
#     "destId": 1,
#     "dstPort": 7007,
#     "enterpriseLogicalId": "00000000-0000-0000-0000-000000000000",
#     "linkLogicalId": "00000002-1111-2222-3333-444444444444",
#     "nvsIp": "192.168.1.241",
#     "nvsLogicalId": "aaaa0001-bbbb-cccc-dddd-eeeeeeee0001",
#     "segmentId": 0,
#     "srcIp": "169.254.3.1"
#   },
#   {
#     "cloud": "zscalerbeta.net",
#     "destId": 0,
#     "dstPort": 7000,
#     "enterpriseLogicalId": "00000000-0000-0000-0000-000000000000",
#     "linkLogicalId": "00000001-1111-2222-3333-444444444444",
#     "nvsIp": "192.168.1.242",
#     "nvsLogicalId": "aaaa0002-bbbb-cccc-dddd-eeeeeeee0002",
#     "segmentId": 2,
#     "srcIp": "169.254.3.3"
#   }
# ]
#
# Quick CSV summary command on Edge:
#   /opt/vc/bin/debug.py --l7_health_checks | jq -r '.[] | [ .cloud, .nvsIp, .dstPort ] | @csv' | sort
#   "zscaler.net","192.168.1.240",7002
#   "zscaler.net","192.168.1.240",7006
#   "zscaler.net","192.168.1.241",7003
#   "zscaler.net","192.168.1.241",7007
#   "zscalerbeta.net","192.168.1.242",7000
#   "zscalerbeta.net","192.168.1.242",7004
#   "zscalerbeta.net","192.168.1.243",7001
#   "zscalerbeta.net","192.168.1.243",7005

(

# Listen on Primary Prod CSS (gre1 namespace: ports 7002 for GE1, 7006 for GE2)
while true; do
    SERVER_PORT=7002  
    SECONDS=0
    OUTPUT=$(echo -e "HTTP/1.1 200 OK\r\nContent-type: text/html\r\nContent-length: 2\r\n\r\nOK" | ip netns exec gre1 nc -v -l 192.168.1.240 ${SERVER_PORT} 2>&1 >/dev/null)
    if echo "$OUTPUT" | grep -q "Connection received"; then
        IP=$(echo "$OUTPUT" | grep "Connection received" | awk '{print $4}')
        PORT=$(echo "$OUTPUT" | grep "Connection received" | awk '{print $5}')
        duration=$SECONDS
        echo "Zscaler Prod Master $(date +%d-%m-%Y--%H-%M-%S) Client: $IP $PORT $((duration / 60)) minutes and $((duration % 60)) seconds elapsed on 192.168.1.240 port ${SERVER_PORT} (gre1)"
    fi
done &
while true; do
    SERVER_PORT=7006 
    SECONDS=0
    OUTPUT=$(echo -e "HTTP/1.1 200 OK\r\nContent-type: text/html\r\nContent-length: 2\r\n\r\nOK" | ip netns exec gre1 nc -v -l 192.168.1.240 ${SERVER_PORT} 2>&1 >/dev/null)
    if echo "$OUTPUT" | grep -q "Connection received"; then
        IP=$(echo "$OUTPUT" | grep "Connection received" | awk '{print $4}')
        PORT=$(echo "$OUTPUT" | grep "Connection received" | awk '{print $5}')
        duration=$SECONDS
        echo "Zscaler Prod Master $(date +%d-%m-%Y--%H-%M-%S) Client: $IP $PORT $((duration / 60)) minutes and $((duration % 60)) seconds elapsed on 192.168.1.240 port ${SERVER_PORT} (gre1)"
    fi
done &

# Listen on Secondary Prod CSS (gre2 namespace: ports 7003 for GE1, 7007 for GE2)
while true; do
    SERVER_PORT=7003  
    SECONDS=0
    OUTPUT=$(echo -e "HTTP/1.1 200 OK\r\nContent-type: text/html\r\nContent-length: 2\r\n\r\nOK" | ip netns exec gre2 nc -v -l 192.168.1.241 ${SERVER_PORT} 2>&1 >/dev/null)
    if echo "$OUTPUT" | grep -q "Connection received"; then
        IP=$(echo "$OUTPUT" | grep "Connection received" | awk '{print $4}')
        PORT=$(echo "$OUTPUT" | grep "Connection received" | awk '{print $5}')
        duration=$SECONDS
        echo "Zscaler Prod Bck $(date +%d-%m-%Y--%H-%M-%S) Client: $IP $PORT $((duration / 60)) minutes and $((duration % 60)) seconds elapsed on 192.168.1.241 port ${SERVER_PORT} (gre2)"
    fi
done &
while true; do
    SERVER_PORT=7007  
    SECONDS=0
    OUTPUT=$(echo -e "HTTP/1.1 200 OK\r\nContent-type: text/html\r\nContent-length: 2\r\n\r\nOK" | ip netns exec gre2 nc -v -l 192.168.1.241 ${SERVER_PORT} 2>&1 >/dev/null)
    if echo "$OUTPUT" | grep -q "Connection received"; then
        IP=$(echo "$OUTPUT" | grep "Connection received" | awk '{print $4}')
        PORT=$(echo "$OUTPUT" | grep "Connection received" | awk '{print $5}')
        duration=$SECONDS
        echo "Zscaler Prod Bck $(date +%d-%m-%Y--%H-%M-%S) Client: $IP $PORT $((duration / 60)) minutes and $((duration % 60)) seconds elapsed on 192.168.1.241 port ${SERVER_PORT} (gre2)"
    fi
done &

# Listen on Primary Guest CSS (gre1 namespace: ports 7000 for GE1, 7004 for GE2)
while true; do
    SERVER_PORT=7000  
    SECONDS=0
    OUTPUT=$(echo -e "HTTP/1.1 200 OK\r\nContent-type: text/html\r\nContent-length: 2\r\n\r\nOK" | ip netns exec gre1 nc -v -l 192.168.1.242 ${SERVER_PORT} 2>&1 >/dev/null)
    if echo "$OUTPUT" | grep -q "Connection received"; then
        IP=$(echo "$OUTPUT" | grep "Connection received" | awk '{print $4}')
        PORT=$(echo "$OUTPUT" | grep "Connection received" | awk '{print $5}')
        duration=$SECONDS
        echo "Zscaler Guest Master $(date +%d-%m-%Y--%H-%M-%S) Client: $IP $PORT $((duration / 60)) minutes and $((duration % 60)) seconds elapsed on 192.168.1.242 port ${SERVER_PORT} (gre1)"
    fi
done &
while true; do
    SERVER_PORT=7004 
    SECONDS=0
    OUTPUT=$(echo -e "HTTP/1.1 200 OK\r\nContent-type: text/html\r\nContent-length: 2\r\n\r\nOK" | ip netns exec gre1 nc -v -l 192.168.1.242 ${SERVER_PORT} 2>&1 >/dev/null)
    if echo "$OUTPUT" | grep -q "Connection received"; then
        IP=$(echo "$OUTPUT" | grep "Connection received" | awk '{print $4}')
        PORT=$(echo "$OUTPUT" | grep "Connection received" | awk '{print $5}')
        duration=$SECONDS
        echo "Zscaler Guest Master $(date +%d-%m-%Y--%H-%M-%S) Client: $IP $PORT $((duration / 60)) minutes and $((duration % 60)) seconds elapsed on 192.168.1.242 port ${SERVER_PORT} (gre1)"
    fi
done &

# Listen on Secondary Guest CSS (gre2 namespace: ports 7001 for GE1, 7005 for GE2)
while true; do
    SERVER_PORT=7001  
    SECONDS=0
    OUTPUT=$(echo -e "HTTP/1.1 200 OK\r\nContent-type: text/html\r\nContent-length: 2\r\n\r\nOK" | ip netns exec gre2 nc -v -l 192.168.1.243 ${SERVER_PORT} 2>&1 >/dev/null)
    if echo "$OUTPUT" | grep -q "Connection received"; then
        IP=$(echo "$OUTPUT" | grep "Connection received" | awk '{print $4}')
        PORT=$(echo "$OUTPUT" | grep "Connection received" | awk '{print $5}')
        duration=$SECONDS
        echo "Zscaler Guest Bck $(date +%d-%m-%Y--%H-%M-%S) Client: $IP $PORT $((duration / 60)) minutes and $((duration % 60)) seconds elapsed on 192.168.1.243 port ${SERVER_PORT} (gre2)"
    fi
done &
while true; do
    SERVER_PORT=7005  
    SECONDS=0
    OUTPUT=$(echo -e "HTTP/1.1 200 OK\r\nContent-type: text/html\r\nContent-length: 2\r\n\r\nOK" | ip netns exec gre2 nc -v -l 192.168.1.243 ${SERVER_PORT} 2>&1 >/dev/null)
    if echo "$OUTPUT" | grep -q "Connection received"; then
        IP=$(echo "$OUTPUT" | grep "Connection received" | awk '{print $4}')
        PORT=$(echo "$OUTPUT" | grep "Connection received" | awk '{print $5}')
        duration=$SECONDS
        echo "Zscaler Guest Bck $(date +%d-%m-%Y--%H-%M-%S) Client: $IP $PORT $((duration / 60)) minutes and $((duration % 60)) seconds elapsed on 192.168.1.243 port ${SERVER_PORT} (gre2)"
    fi
done &

echo "Listening on ports 7000..7007 inside gre1/gre2. Press Enter to stop all listeners..."
read dummy

) | tee -a logfile-${DD}.log

killall nc 2>/dev/null || true
pkill -P $$ 2>/dev/null || true

echo "Waiting until all background listeners terminate..."
wait

