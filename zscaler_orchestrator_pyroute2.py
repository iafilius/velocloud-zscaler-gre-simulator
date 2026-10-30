#!/usr/bin/env python3
"""
Zscaler GRE Tunnel L7 Health Check Orchestrator
================================================

Interactive CLI tool for simulating Zscaler endpoint failovers and monitoring 
VeloCloud SD-WAN tunnel failover behavior in real-time.

OVERVIEW:
---------
This orchestrator simulates Zscaler datacenter endpoints within Linux network 
namespaces, allowing you to dynamically control their health status and observe 
how VeloCloud Edge devices react to failures. Each endpoint can be in three states:
  - UP:        Returns HTTP 200 OK (normal operation)
  - DEGRADED:  Returns HTTP 200 OK with 2-second delay (performance issues)
  - DOWN:      Returns HTTP 503 Service Unavailable (complete failure)

The VeloCloud Edge continuously polls these endpoints via L7 health checks and 
will failover GRE tunnels based on the responses.

ARCHITECTURE:
-------------
Uses pyroute2 library for namespace verification and introspection, with
direct setns() system call for thread namespace switching:
  - Each endpoint runs in its own network namespace (gre1 or gre2)
  - Python threads handle HTTP listeners using native socket operations
  - Each thread switches into its namespace using setns() syscall via ctypes
  - Threads remain in their namespace for their entire lifecycle
  - Real HTTP/1.1 protocol with proper status codes and headers

Thread namespace switching:
  - Uses ctypes to call libc setns() system call directly
  - Opens /var/run/netns/{namespace} file descriptor
  - Calls setns(fd, CLONE_NEWNET) to switch thread permanently
  - Thread stays in namespace, allowing proper socket binding and accept()
  - This ensures connections arriving via GRE tunnels are properly received

PREREQUISITES:
--------------
1. Network namespaces must be created and configured:
   $ sudo ./mknetns-gre1.sh    # Creates gre1 and gre2 namespaces
   $ sudo ./doit.sh            # Configures IPs and GRE tunnels

2. Python 3.6+ required

3. pyroute2 library must be installed:
   
   # Option A: Using apt (Ubuntu/Debian - RECOMMENDED for sudo usage)
   $ sudo apt-get install python3-pyroute2
   
   # Option B: Using pip (any Linux distribution)
   $ sudo pip3 install pyroute2
   
   # Option C: Virtual environment (for development)
   $ python3 -m venv venv
   $ source venv/bin/activate
   $ pip install pyroute2
   
   The pyroute2 library provides:
   - NetNS: Network namespace management
   - IPRoute: Interface and routing inspection
   - Clean Python API wrapping Linux netlink sockets

INSTALLATION:
-------------
# Option A: Using apt-get (Ubuntu/Debian - RECOMMENDED)
# This installs system-wide and works automatically with sudo
sudo apt-get update
sudo apt-get install python3-pyroute2

# Option B: Using pip system-wide
sudo pip3 install pyroute2

# Option C: Using virtual environment (requires sudo venv/bin/python)
python3 -m venv venv
source venv/bin/activate
pip install pyroute2

# Verify installation
sudo python3 -c "from pyroute2 import NetNS; print('pyroute2 OK')"

USAGE:
------
# Must run as root to access network namespaces
sudo ./zscaler_orchestrator_pyroute2.py

# OR if using virtual environment
sudo venv/bin/python zscaler_orchestrator_pyroute2.py

INTERACTIVE COMMANDS:
---------------------
Once running, you can orchestrate failover scenarios:

[1-8]  Toggle individual endpoint status (cycles: up → degraded → down → up)
       GE1 Endpoints (Edge 192.168.1.64):
       1 = Prod Primary GE1    (192.168.1.240:7002 in gre1)
       2 = Prod Secondary GE1  (192.168.1.241:7003 in gre2)
       3 = Guest Primary GE1   (192.168.1.242:7000 in gre1)
       4 = Guest Secondary GE1 (192.168.1.243:7001 in gre2)
       
       GE2 Endpoints (Edge 192.168.1.65):
       5 = Prod Primary GE2    (192.168.1.240:7006 in gre1)
       6 = Prod Secondary GE2  (192.168.1.241:7007 in gre2)
       7 = Guest Primary GE2   (192.168.1.242:7004 in gre1)
       8 = Guest Secondary GE2 (192.168.1.243:7005 in gre2)

[p1]   Simulate Production GE1 failover: Primary → Secondary
[p2]   Simulate Production GE2 failover: Primary → Secondary
[g1]   Simulate Guest GE1 failover: Primary → Secondary
[g2]   Simulate Guest GE2 failover: Primary → Secondary
[pa]   Simulate Production failover on BOTH GE1+GE2
[ga]   Simulate Guest failover on BOTH GE1+GE2
[b]    Simulate ALL failovers simultaneously (all 4 pools)

[u]    Bring all endpoints UP (recover from failures)

[d]    Take all endpoints DOWN (test complete outage)

[s]    Refresh status dashboard

[l]    Show recent activity logs (last 30 lines)

[n]    Show namespace network configuration
       Displays interfaces, IPs, and state for each namespace

[q]    Quit orchestrator

FAILOVER TESTING SCENARIOS:
---------------------------
1. Single Endpoint Failure:
   Press [1] repeatedly to cycle prod primary: up → degraded → down
   Watch VeloCloud health checks fail and switch to secondary tunnel

2. Gradual Degradation:
   Press [p] for automated production failover
   Observe:
   - Health checks slow down (degraded phase)
   - Health checks fail (down phase)
   - VeloCloud switches to secondary tunnel
   - Recovery when brought back up

3. Complete Outage:
   Press [d] to take all endpoints down
   Observe VeloCloud behavior when all Zscaler endpoints are unreachable

4. Simultaneous Failover:
   Press [b] to failover both prod and guest pools
   Test VeloCloud handling of multiple concurrent tunnel changes

MONITORING:
-----------
The dashboard shows real-time statistics for each endpoint:
  - Current status (UP/DEGRADED/DOWN) with color coding
  - IP address and port binding
  - Network namespace location
  - Connection count (total health checks received)
  - Last check timestamp
  - Last client IP:port (VeloCloud Edge source)

All events are logged to: orchestrator-pyroute2-YYYYMMDD-HHMMSS.log

VELOCLOUD EDGE BEHAVIOR:
------------------------
The VeloCloud Edge performs L7 health checks approximately every 4-5 seconds:
  - Sends HTTP GET requests to configured health check ports
  - Expects HTTP 200 OK response
  - On failure, marks tunnel as down and switches to backup
  - Continuously monitors both primary and secondary

Expected behavior during failover:
  1. Primary endpoint degrades → slower responses
  2. Primary endpoint fails → 503 errors
  3. VeloCloud detects failure (typically 2-3 failed checks)
  4. VeloCloud switches traffic to secondary tunnel
  5. Primary recovers → VeloCloud may switch back (depends on config)

NETWORK NAMESPACE DETAILS:
--------------------------
This orchestrator supports 8 GRE tunnels (4 per Edge interface):

VeloCloud Edge Interfaces:
  - GE1: 192.168.1.64 (Primary WAN interface)
  - GE2: 192.168.1.65 (Secondary WAN interface)

gre1 (Primary namespace):
  - veth-b1 interface
  - 192.168.1.240 (Production Primary) - Ports: 7002 (GE1), 7006 (GE2)
  - 192.168.1.242 (Guest Primary) - Ports: 7000 (GE1), 7004 (GE2)
  - 4 GRE tunnels: gre1, gre11, gre21, gre31

gre2 (Secondary namespace):
  - veth-b2 interface  
  - 192.168.1.241 (Production Secondary) - Ports: 7003 (GE1), 7007 (GE2)
  - 192.168.1.243 (Guest Secondary) - Ports: 7001 (GE1), 7005 (GE2)
  - 4 GRE tunnels: gre2, gre12, gre22, gre32

Total: 8 health check endpoints listening on ports 7000-7007

TROUBLESHOOTING:
----------------
Error: "pyroute2 library not found"
  → Install: pip install pyroute2

Error: "Namespace 'gre1' not found"
  → Run: sudo ./mknetns-gre1.sh && sudo ./doit.sh

Error: "This script must be run as root"
  → Run with sudo: sudo ./zscaler_orchestrator_pyroute2.py

Error: Address already in use
  → Stop existing http2.sh: pkill -f http2.sh
  → Check processes: ps aux | grep -E "(nc|python)" | grep 7000

No health checks appearing:
  → Verify VeloCloud Edge configuration
  → Check GRE tunnels: sudo ip netns exec gre1 ip tunnel show
  → Check routing: sudo ip netns exec gre1 ip route
  → Verify firewall: sudo ip netns exec gre1 iptables -L

TECHNICAL IMPLEMENTATION:
-------------------------
Thread namespace switching uses direct setns() system call:

  import ctypes
  import os
  
  # Open namespace file descriptor
  nsfd = os.open('/var/run/netns/gre1', os.O_RDONLY)
  
  # Call setns() via ctypes to switch thread into namespace
  libc = ctypes.CDLL('libc.so.6', use_errno=True)
  CLONE_NEWNET = 0x40000000
  if libc.setns(nsfd, CLONE_NEWNET) == -1:
      raise OSError(ctypes.get_errno(), "setns failed")
  os.close(nsfd)
  
  # Now thread is IN gre1 namespace permanently
  sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
  sock.bind(('192.168.1.240', 7002))  # Binds to IP in gre1
  sock.listen(5)
  
  # Thread stays in namespace for entire lifecycle
  while running:
      conn, addr = sock.accept()  # Accepts from gre1 namespace
      # Handle connection...

Why direct setns() instead of NetNS context manager:
  - NetNS context manager in pyroute2 0.9.5 creates netlink socket in namespace
  - It does NOT switch the calling thread into the namespace
  - Direct setns() call is required for thread to actually enter namespace
  - Once in namespace, thread can bind/listen/accept on namespace IPs
  - This is essential for receiving connections via GRE tunnels

pyroute2 is still used for:
  - Namespace verification (NetNS object creation checks existence)
  - Network introspection via IPRoute (show interfaces, IPs)
  - Cleaner error handling than raw file operations

AUTHOR:
-------
VeloCloud GRE Tunnel Simulator
Based on http2.sh bash implementation
Rewritten in Python with pyroute2 for better orchestration

VERSION: 2.0 (pyroute2-based)
"""

import socket
import threading
import time
import sys
import os
import signal
from datetime import datetime
from collections import defaultdict

try:
    from pyroute2 import NetNS
    from pyroute2 import IPRoute
except ImportError:
    print("ERROR: pyroute2 library not found!")
    print("Install with: sudo apt-get install python3-pyroute2")
    sys.exit(1)

# Check root permissions
if os.geteuid() != 0:
    print("ERROR: This script must be run as root (use sudo)")
    print(f"Usage: sudo {sys.argv[0]}")
    sys.exit(1)

# ANSI color codes
RESET = '\033[0m'
RED = '\033[91m'
GREEN = '\033[92m'
YELLOW = '\033[93m'
BLUE = '\033[94m'
MAGENTA = '\033[95m'
CYAN = '\033[96m'
BOLD = '\033[1m'
CLEAR = '\033[2J\033[H'

# Degraded state delay (seconds)
# VeloCloud RTT Threshold = 3000ms (3 seconds)
# Set > 3.0 to trigger failover, or < 3.0 to simulate slow-but-acceptable performance
DEGRADED_DELAY = 4.0  # Default: 4 seconds (exceeds VeloCloud RTT threshold)

# Endpoint configuration
# GE1 endpoints (VeloCloud Edge 192.168.1.64)
ENDPOINTS = {
    'prod_primary_ge1': {
        'name': 'Prod Primary GE1',
        'namespace': 'gre1',
        'ip': '192.168.1.240',
        'port': 7002,
        'gre_tunnel': 'gre1',
        'status': 'up',
        'color': GREEN,
        'edge': 'GE1'
    },
    'prod_secondary_ge1': {
        'name': 'Prod Secondary GE1', 
        'namespace': 'gre2',
        'ip': '192.168.1.241',
        'port': 7003,
        'gre_tunnel': 'gre2',
        'status': 'up',
        'color': BLUE,
        'edge': 'GE1'
    },
    'guest_primary_ge1': {
        'name': 'Guest Primary GE1',
        'namespace': 'gre1',
        'ip': '192.168.1.242',
        'port': 7000,
        'gre_tunnel': 'gre21',
        'status': 'up',
        'color': YELLOW,
        'edge': 'GE1'
    },
    'guest_secondary_ge1': {
        'name': 'Guest Secondary GE1',
        'namespace': 'gre2',
        'ip': '192.168.1.243',
        'port': 7001,
        'gre_tunnel': 'gre22',
        'status': 'up',
        'color': MAGENTA,
        'edge': 'GE1'
    },
    # GE2 endpoints (VeloCloud Edge 192.168.1.65)
    'prod_primary_ge2': {
        'name': 'Prod Primary GE2',
        'namespace': 'gre1',
        'ip': '192.168.1.240',
        'port': 7006,
        'gre_tunnel': 'gre11',
        'status': 'up',
        'color': GREEN,
        'edge': 'GE2'
    },
    'prod_secondary_ge2': {
        'name': 'Prod Secondary GE2',
        'namespace': 'gre2',
        'ip': '192.168.1.241',
        'port': 7007,
        'gre_tunnel': 'gre12',
        'status': 'up',
        'color': BLUE,
        'edge': 'GE2'
    },
    'guest_primary_ge2': {
        'name': 'Guest Primary GE2',
        'namespace': 'gre1',
        'ip': '192.168.1.242',
        'port': 7004,
        'gre_tunnel': 'gre31',
        'status': 'up',
        'color': YELLOW,
        'edge': 'GE2'
    },
    'guest_secondary_ge2': {
        'name': 'Guest Secondary GE2',
        'namespace': 'gre2',
        'ip': '192.168.1.243',
        'port': 7005,
        'gre_tunnel': 'gre32',
        'status': 'up',
        'color': MAGENTA,
        'edge': 'GE2'
    }
}

# Global state
stats = defaultdict(lambda: {'connections': 0, 'last_check': None, 'last_client': None})
running = True
logfile = None
log_lock = threading.Lock()


def log_message(message, endpoint_key=None):
    """Thread-safe logging to file and console"""
    timestamp = datetime.now().strftime('%d-%m-%Y %H:%M:%S')
    color = ENDPOINTS[endpoint_key]['color'] if endpoint_key else ''
    log_entry = f"[{timestamp}] {message}"
    
    with log_lock:
        if logfile:
            logfile.write(log_entry + '\n')
            logfile.flush()
        print(f"{color}{log_entry}{RESET}")


def http_response(status='up'):
    """
    Generate HTTP response based on endpoint status.
    
    Args:
        status: Endpoint health status ('up', 'degraded', or 'down')
    
    Returns:
        bytes: Complete HTTP/1.1 response with headers and body
    
    Response codes:
        - up:       HTTP 200 OK with body "OK" (immediate response)
        - degraded: HTTP 200 OK with body "DEGRADED" (delayed by DEGRADED_DELAY seconds)
        - down:     HTTP 503 Service Unavailable with body "DOWN"
    
    VeloCloud Edge expects HTTP 200 for successful health check.
    VeloCloud RTT Threshold: 3000ms - delays > 3s will trigger failover.
    """
    if status == 'up':
        return (
            b"HTTP/1.1 200 OK\r\n"
            b"Content-Type: text/plain\r\n"
            b"Content-Length: 2\r\n"
            b"Server: Zscaler-Simulator\r\n"
            b"Connection: close\r\n"
            b"\r\n"
            b"OK"
        )
    elif status == 'degraded':
        return (
            b"HTTP/1.1 200 OK\r\n"
            b"Content-Type: text/plain\r\n"
            b"Content-Length: 8\r\n"
            b"Server: Zscaler-Simulator\r\n"
            b"Connection: close\r\n"
            b"\r\n"
            b"DEGRADED"
        )
    else:  # down
        return (
            b"HTTP/1.1 503 Service Unavailable\r\n"
            b"Content-Type: text/plain\r\n"
            b"Content-Length: 4\r\n"
            b"Server: Zscaler-Simulator\r\n"
            b"Connection: close\r\n"
            b"\r\n"
            b"DOWN"
        )


def create_socket_in_namespace(namespace, ip, port):
    """
    Create a socket within a network namespace using pyroute2.
    
    This function demonstrates the key pyroute2 pattern for namespace operations:
    
    How it works:
    -------------
    1. NetNS(namespace) opens /var/run/netns/<namespace>
    2. The 'with' context switches the calling thread into that namespace
    3. socket() creates a socket - the FD is created IN the namespace
    4. bind() binds to the namespace's IP address
    5. When 'with' exits, thread switches back to default namespace
    6. BUT: The socket FD remains bound to the original namespace!
    
    This is the magic: socket file descriptors are namespace-aware.
    Even though the thread switches back, the socket continues to
    operate within its creation namespace.
    
    Args:
        namespace: Network namespace name (e.g., 'gre1', 'gre2')
        ip: IP address to bind to (must exist in namespace)
        port: TCP port number for listening
    
    Returns:
        socket.socket: Bound and listening socket in the namespace
    
    Raises:
        Exception: If namespace doesn't exist or bind fails
    
    Example:
        sock = create_socket_in_namespace('gre1', '192.168.1.240', 7002)
        # Thread is back in default namespace, but sock listens in gre1
        conn, addr = sock.accept()  # Accepts connections arriving in gre1
    """
    try:
        # Create a NetNS object - this gives us access to the namespace
        # but doesn't switch into it yet
        ns = NetNS(namespace)
        
        # The NetNS object has a socket() method that creates a socket
        # inside the namespace without switching the thread
        # But for our use case, we want to switch the thread permanently
        
        # Alternative approach: use NetNS as context manager
        # This switches the thread into the namespace
        with NetNS(namespace):
            # Now we're IN the namespace - create socket normally
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            sock.bind((ip, port))
            sock.listen(5)
            sock.settimeout(1.0)
            
            # IMPORTANT: When we exit this context, the thread switches back
            # But the socket fd was created IN the namespace, so it stays there
            return sock
        
    except Exception as e:
        raise Exception(f"Failed to create socket in namespace {namespace}: {e}")


def listener_thread(endpoint_key):
    """
    HTTP listener thread for a single Zscaler endpoint.
    
    Thread-based architecture:
    -------------------------
    Each endpoint runs in its own daemon thread:
    - Thread switches INTO the namespace permanently using pyroute2
    - Thread creates socket in that namespace
    - Thread runs accept() loop waiting for VeloCloud health checks
    - Thread reads endpoint status from shared ENDPOINTS dict
    - Thread updates stats in thread-safe manner
    - Thread sends appropriate HTTP response based on current status
    
    Namespace integration:
    ---------------------
    The thread permanently switches into the namespace at startup:
      with NetNS('gre1'):
          # Thread is NOW in gre1 namespace
          sock = socket.socket(...)
          sock.bind(('192.168.1.240', 7002))
          while running:
              conn, addr = sock.accept()  # Accept in namespace
              # Handle connection...
      
    The thread stays in the namespace for its entire lifecycle, which is
    necessary for accept() to work with connections arriving via GRE tunnels.
    
    Dynamic status control:
    ----------------------
    Status is checked on EACH connection, enabling real-time orchestration:
    - 'up':       Returns HTTP 200 OK immediately
    - 'degraded': Sleeps 2s then returns HTTP 200 OK (simulate slow DC)
    - 'down':     Returns HTTP 503 Service Unavailable
    
    VeloCloud polls every 4-5 seconds, so status changes take effect
    within a few health check cycles.
    
    Args:
        endpoint_key: Key in ENDPOINTS dict ('prod_primary_ge1', etc.)
    
    Thread lifecycle:
        - Started as daemon thread at orchestrator startup
        - Runs until global 'running' flag becomes False
        - Automatically terminates on program exit
    """
    endpoint = ENDPOINTS[endpoint_key]
    namespace = endpoint['namespace']
    ip = endpoint['ip']
    port = endpoint['port']
    
    log_message(f"Starting listener for {endpoint['name']} on {ip}:{port} ({namespace})", endpoint_key)
    
    try:
        # Switch this thread into the namespace permanently
        # Open the namespace file descriptor
        nsfd = os.open(f'/var/run/netns/{namespace}', os.O_RDONLY)
        
        # Use the NetNS libc wrapper to call setns()
        import ctypes
        libc = ctypes.CDLL('libc.so.6', use_errno=True)
        CLONE_NEWNET = 0x40000000
        
        if libc.setns(nsfd, CLONE_NEWNET) == -1:
            errno = ctypes.get_errno()
            raise OSError(errno, f"setns failed: {os.strerror(errno)}")
        
        os.close(nsfd)
        
        # Now we're IN the namespace - create socket normally
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.bind((ip, port))
        sock.listen(5)
        sock.settimeout(1.0)
        
        log_message(f"Listener ready for {endpoint['name']}", endpoint_key)
        
        # Main listener loop - stays in namespace
        while running:
            try:
                # Accept connections with timeout
                try:
                    conn, addr = sock.accept()
                except socket.timeout:
                    continue
                except OSError:
                    if not running:
                        break
                    continue
                
                start_time = time.time()
                client_ip, client_port = addr
                
                # Read the HTTP request
                try:
                    request = conn.recv(1024)
                except:
                    conn.close()
                    continue
                
                # Get current status
                status = endpoint['status']
                
                # Update stats
                stats[endpoint_key]['connections'] += 1
                stats[endpoint_key]['last_check'] = datetime.now()
                stats[endpoint_key]['last_client'] = f"{client_ip}:{client_port}"
                
                # Add delay for degraded status
                if status == 'degraded':
                    time.sleep(DEGRADED_DELAY)
                
                # Send HTTP response based on status
                response = http_response(status)
                try:
                    conn.sendall(response)
                except:
                    pass
                
                duration = time.time() - start_time
                gre_tunnel = endpoint['gre_tunnel']
                log_message(f"{endpoint['name']} [{namespace}/{gre_tunnel}] - Client: {client_ip}:{client_port} → {ip}:{port} - Status: {status.upper()} - Duration: {duration:.1f}s", endpoint_key)
                
                conn.close()
            
            except Exception as e:
                if running:
                    log_message(f"Error in listener for {endpoint['name']}: {e}", endpoint_key)
                    time.sleep(0.1)
        
        sock.close()
    
    except Exception as e:
        log_message(f"FATAL: Listener for {endpoint['name']} crashed: {e}", endpoint_key)


def display_status():
    """Display current status dashboard"""
    print(CLEAR)
    print(f"{BOLD}{CYAN}{'='*100}{RESET}")
    print(f"{BOLD}{CYAN}{'Zscaler GRE Tunnel Orchestrator - VeloCloud Failover Simulator':^100}{RESET}")
    print(f"{BOLD}{CYAN}{'(pyroute2 version - 8 Tunnel Support)':^100}{RESET}")
    print(f"{BOLD}{CYAN}{'='*100}{RESET}\n")
    
    # Group by Edge interface
    print(f"{BOLD}{YELLOW}GE1 Endpoints (Edge 192.168.1.64):{RESET}")
    print(f"{BOLD}Production:{RESET}")
    for key in ['prod_primary_ge1', 'prod_secondary_ge1']:
        display_endpoint(key)
    print(f"{BOLD}Guest:{RESET}")
    for key in ['guest_primary_ge1', 'guest_secondary_ge1']:
        display_endpoint(key)
    
    print(f"\n{BOLD}{CYAN}GE2 Endpoints (Edge 192.168.1.65):{RESET}")
    print(f"{BOLD}Production:{RESET}")
    for key in ['prod_primary_ge2', 'prod_secondary_ge2']:
        display_endpoint(key)
    print(f"{BOLD}Guest:{RESET}")
    for key in ['guest_primary_ge2', 'guest_secondary_ge2']:
        display_endpoint(key)
    
    print(f"\n{BOLD}{CYAN}{'='*100}{RESET}\n")


def display_endpoint(key):
    """Display single endpoint status"""
    endpoint = ENDPOINTS[key]
    status = endpoint['status']
    color = endpoint['color']
    
    # Status icon
    if status == 'up':
        icon = f"{GREEN}●{RESET}"
        status_text = f"{GREEN}UP{RESET}"
    elif status == 'degraded':
        icon = f"{YELLOW}◐{RESET}"
        status_text = f"{YELLOW}DEGRADED{RESET}"
    else:
        icon = f"{RED}○{RESET}"
        status_text = f"{RED}DOWN{RESET}"
    
    # Get stats
    ep_stats = stats[key]
    connections = ep_stats.get('connections', 0)
    last_check = ep_stats.get('last_check')
    last_client = ep_stats.get('last_client', 'none')
    
    last_check_str = last_check.strftime('%H:%M:%S') if last_check else 'never'
    
    print(f"{icon} {color}{endpoint['name']:<20}{RESET} {status_text:<20} "
          f"{endpoint['ip']}:{endpoint['port']:<6} ({endpoint['namespace']})  "
          f"Checks: {connections:<5} Last: {last_check_str} from {last_client}")


def display_menu():
    """Display interactive menu"""
    print(f"{BOLD}Orchestration Commands:{RESET}")
    print(f"  {GREEN}[1-8]{RESET} Toggle endpoint (cycles: UP → DEGRADED → DOWN):")
    print(f"        GE1: 1=Prod Pri, 2=Prod Sec, 3=Guest Pri, 4=Guest Sec")
    print(f"        GE2: 5=Prod Pri, 6=Prod Sec, 7=Guest Pri, 8=Guest Sec")
    print(f"  {YELLOW}Failover Commands (Primary Zscaler → Secondary Zscaler):{RESET}")
    print(f"    [p1] Prod GE1  [p2] Prod GE2  [pa] Prod Both")
    print(f"    [g1] Guest GE1 [g2] Guest GE2 [ga] Guest Both")
    print(f"    [b]  ALL failovers (4 pools simultaneously)")
    print(f"  {GREEN}[u]{RESET}   Bring all UP  {RED}[d]{RESET} Take all DOWN  {CYAN}[c]{RESET} Configure DEGRADED delay")
    print(f"  {CYAN}[s]{RESET}   Refresh  {CYAN}[l]{RESET} Logs  {CYAN}[n]{RESET} Namespace info  {RED}[q]{RESET} Quit")
    print(f"\n{BOLD}Current DEGRADED delay: {YELLOW}{DEGRADED_DELAY}s{RESET} (VeloCloud RTT threshold: 3.0s){RESET}")
    print(f"\n{BOLD}> {RESET}", end='', flush=True)


def simulate_failover(primary_key, secondary_key, name=""):
    """
    Simulate realistic datacenter failover scenario.
    
    Failover sequence:
    ------------------
    1. DEGRADATION phase (3 seconds):
       - Primary endpoint set to 'degraded' status
       - Returns HTTP 200 OK but with DEGRADED_DELAY second delay
       - Simulates datacenter performance issues
       - If DEGRADED_DELAY > 3s: VeloCloud detects RTT threshold exceeded
       - If DEGRADED_DELAY < 3s: VeloCloud sees slow but acceptable response
    
    2. FAILURE phase (2 seconds):
       - Primary endpoint set to 'down' status  
       - Returns HTTP 503 Service Unavailable
       - VeloCloud detects failed health checks
       - After 3 consecutive failures, VeloCloud fails over
    
    3. RECOVERY confirmation:
       - Secondary endpoint confirmed 'up' status
       - VeloCloud now using secondary tunnel
       - Primary can be brought back up later
    
    This sequence mimics real-world scenarios:
    - Zscaler datacenter experiencing high load (degraded)
    - Complete datacenter outage (down)
    - Traffic rerouted to backup datacenter (secondary)
    
    VeloCloud L7 Health Check Parameters:
    - HTTP Probe Interval: 5 seconds
    - Number of Retries: 3
    - RTT Threshold: 3000ms (3 seconds)
    
    Args:
        primary_key: Endpoint to fail (e.g., 'prod_primary')
        secondary_key: Endpoint to promote (e.g., 'prod_secondary')
        name: Human-readable name for logging (e.g., 'Production')
    
    Usage:
        simulate_failover('prod_primary', 'prod_secondary', 'Production')
        # Watch VeloCloud switch GRE tunnels from gre1 to gre2
    """
    print(f"\n{YELLOW}{'='*80}{RESET}")
    print(f"{YELLOW}Simulating {name} Failover{RESET}")
    print(f"{YELLOW}{'='*80}{RESET}\n")
    
    primary = ENDPOINTS[primary_key]
    secondary = ENDPOINTS[secondary_key]
    
    print(f"Step 1: Degrading {primary['name']}...")
    ENDPOINTS[primary_key]['status'] = 'degraded'
    log_message(f"FAILOVER: {primary['name']} → DEGRADED", primary_key)
    time.sleep(3)
    
    print(f"Step 2: Taking down {primary['name']}...")
    ENDPOINTS[primary_key]['status'] = 'down'
    log_message(f"FAILOVER: {primary['name']} → DOWN", primary_key)
    time.sleep(2)
    
    print(f"Step 3: Ensuring {secondary['name']} is UP...")
    ENDPOINTS[secondary_key]['status'] = 'up'
    log_message(f"FAILOVER: {secondary['name']} → UP (active)", secondary_key)
    
    print(f"\n{GREEN}✓ Failover complete: {primary['name']} → {secondary['name']}{RESET}\n")
    time.sleep(1)


def show_logs():
    """Display recent log entries"""
    print(f"\n{BOLD}{CYAN}Recent Activity Log (last 30 lines):{RESET}")
    print(f"{CYAN}{'='*100}{RESET}\n")
    try:
        with open(logfile.name, 'r') as f:
            lines = f.readlines()
            for line in lines[-30:]:
                print(line.rstrip())
    except Exception as e:
        print(f"{RED}Error reading logs: {e}{RESET}")
    print(f"\n{CYAN}{'='*100}{RESET}")
    input(f"\n{BOLD}Press Enter to continue...{RESET}")


def show_namespace_info():
    """
    Display detailed network configuration for each namespace.
    
    Uses pyroute2.IPRoute to introspect namespace networking:
    ---------------------------------------------------------
    
    1. NetNS context manager switches into namespace
    2. IPRoute() provides netlink socket API for querying:
       - get_links(): Returns all network interfaces
       - get_addr():  Returns all IP addresses
    3. Parse netlink attributes to extract:
       - Interface names (IFLA_IFNAME)
       - Interface state (IFLA_OPERSTATE: UP/DOWN)
       - IP addresses (IFA_ADDRESS)
       - Interface indices for correlation
    
    This demonstrates pyroute2's introspection capabilities beyond
    just namespace switching - full network configuration access.
    
    Output shows:
    - Interface names and operational state
    - IP address assignments per interface
    - Useful for debugging namespace configuration issues
    
    Example output:
        Prod Primary (gre1):
          Interfaces:
            - lo: DOWN
            - veth-b1: UP
            - gre1: UP
          IP Addresses:
            - veth-b1: 192.168.1.240
            - veth-b1: 192.168.1.242
    """
    print(f"\n{BOLD}{CYAN}Network Namespace Information:{RESET}")
    print(f"{CYAN}{'='*100}{RESET}\n")
    
    for key, endpoint in ENDPOINTS.items():
        ns_name = endpoint['namespace']
        print(f"{BOLD}{endpoint['color']}{endpoint['name']} ({ns_name}):{RESET}")
        
        try:
            with NetNS(ns_name) as ns:
                # Get interface information
                ipr = IPRoute()
                links = ipr.get_links()
                
                print(f"  Interfaces:")
                for link in links:
                    ifname = link.get_attr('IFLA_IFNAME')
                    state = link.get_attr('IFLA_OPERSTATE')
                    print(f"    - {ifname}: {state}")
                
                # Get IP addresses
                addrs = ipr.get_addr()
                print(f"  IP Addresses:")
                for addr in addrs:
                    if addr['family'] == 2:  # AF_INET
                        ifindex = addr['index']
                        ip = addr.get_attr('IFA_ADDRESS')
                        # Find interface name
                        for link in links:
                            if link['index'] == ifindex:
                                ifname = link.get_attr('IFLA_IFNAME')
                                print(f"    - {ifname}: {ip}")
                                break
                
                ipr.close()
        except Exception as e:
            print(f"  {RED}Error: {e}{RESET}")
        
        print()
    
    print(f"{CYAN}{'='*100}{RESET}")
    input(f"\n{BOLD}Press Enter to continue...{RESET}")


def interactive_cli():
    """Interactive command-line interface"""
    global running, DEGRADED_DELAY
    
    while running:
        display_status()
        display_menu()
        
        try:
            choice = input().strip().lower()
            
            if choice == 'q':
                print(f"\n{YELLOW}Shutting down orchestrator...{RESET}")
                running = False
                break
            
            elif choice in ['1', '2', '3', '4', '5', '6', '7', '8']:
                endpoint_map = {
                    '1': 'prod_primary_ge1',
                    '2': 'prod_secondary_ge1',
                    '3': 'guest_primary_ge1',
                    '4': 'guest_secondary_ge1',
                    '5': 'prod_primary_ge2',
                    '6': 'prod_secondary_ge2',
                    '7': 'guest_primary_ge2',
                    '8': 'guest_secondary_ge2'
                }
                key = endpoint_map[choice]
                current = ENDPOINTS[key]['status']
                
                # Cycle: up → degraded → down → up
                if current == 'up':
                    new_status = 'degraded'
                elif current == 'degraded':
                    new_status = 'down'
                else:
                    new_status = 'up'
                
                ENDPOINTS[key]['status'] = new_status
                log_message(f"MANUAL: {ENDPOINTS[key]['name']} → {new_status.upper()}", key)
                time.sleep(0.3)
            
            elif choice == 'p1':
                simulate_failover('prod_primary_ge1', 'prod_secondary_ge1', "Production GE1")
            
            elif choice == 'p2':
                simulate_failover('prod_primary_ge2', 'prod_secondary_ge2', "Production GE2")
            
            elif choice == 'pa':
                print(f"\n{YELLOW}Simulating Production failover (both GE1+GE2)...{RESET}\n")
                threads = [
                    threading.Thread(target=simulate_failover, args=('prod_primary_ge1', 'prod_secondary_ge1', "Production GE1")),
                    threading.Thread(target=simulate_failover, args=('prod_primary_ge2', 'prod_secondary_ge2', "Production GE2"))
                ]
                for t in threads:
                    t.start()
                for t in threads:
                    t.join()
            
            elif choice == 'g1':
                simulate_failover('guest_primary_ge1', 'guest_secondary_ge1', "Guest GE1")
            
            elif choice == 'g2':
                simulate_failover('guest_primary_ge2', 'guest_secondary_ge2', "Guest GE2")
            
            elif choice == 'ga':
                print(f"\n{YELLOW}Simulating Guest failover (both GE1+GE2)...{RESET}\n")
                threads = [
                    threading.Thread(target=simulate_failover, args=('guest_primary_ge1', 'guest_secondary_ge1', "Guest GE1")),
                    threading.Thread(target=simulate_failover, args=('guest_primary_ge2', 'guest_secondary_ge2', "Guest GE2"))
                ]
                for t in threads:
                    t.start()
                for t in threads:
                    t.join()
            
            elif choice == 'b':
                print(f"\n{YELLOW}Simulating complete failover (all 4 pools)...{RESET}\n")
                threads = [
                    threading.Thread(target=simulate_failover, args=('prod_primary_ge1', 'prod_secondary_ge1', "Production GE1")),
                    threading.Thread(target=simulate_failover, args=('prod_primary_ge2', 'prod_secondary_ge2', "Production GE2")),
                    threading.Thread(target=simulate_failover, args=('guest_primary_ge1', 'guest_secondary_ge1', "Guest GE1")),
                    threading.Thread(target=simulate_failover, args=('guest_primary_ge2', 'guest_secondary_ge2', "Guest GE2"))
                ]
                for t in threads:
                    t.start()
                for t in threads:
                    t.join()
            
            elif choice == 'u':
                for key in ENDPOINTS.keys():
                    ENDPOINTS[key]['status'] = 'up'
                log_message("MANUAL: All endpoints → UP")
                time.sleep(0.3)
            
            elif choice == 'd':
                for key in ENDPOINTS.keys():
                    ENDPOINTS[key]['status'] = 'down'
                log_message("MANUAL: All endpoints → DOWN")
                time.sleep(0.3)
            
            elif choice == 's':
                # Just refresh (happens at loop start)
                pass
            
            elif choice == 'l':
                show_logs()
            
            elif choice == 'n':
                show_namespace_info()
            
            elif choice == 'c':
                print(f"\n{BOLD}Configure DEGRADED Delay{RESET}")
                print(f"Current: {YELLOW}{DEGRADED_DELAY}s{RESET}")
                print(f"VeloCloud RTT Threshold: {CYAN}3.0s{RESET}")
                print(f"  • Delay > 3.0s: VeloCloud will detect as slow and may failover")
                print(f"  • Delay < 3.0s: VeloCloud considers acceptable performance")
                try:
                    new_delay = input(f"\nEnter new delay in seconds (0.5-10.0): ").strip()
                    new_delay = float(new_delay)
                    if 0.5 <= new_delay <= 10.0:
                        DEGRADED_DELAY = new_delay
                        log_message(f"DEGRADED_DELAY changed to {DEGRADED_DELAY}s")
                        print(f"{GREEN}✓ Delay updated to {DEGRADED_DELAY}s{RESET}")
                        time.sleep(1)
                    else:
                        print(f"{RED}Error: Delay must be between 0.5 and 10.0 seconds{RESET}")
                        time.sleep(2)
                except ValueError:
                    print(f"{RED}Error: Invalid number{RESET}")
                    time.sleep(2)
            
            else:
                print(f"{RED}Invalid choice!{RESET}")
                time.sleep(1)
        
        except KeyboardInterrupt:
            print(f"\n{YELLOW}Interrupted. Shutting down...{RESET}")
            running = False
            break
        except Exception as e:
            print(f"{RED}Error: {e}{RESET}")
            time.sleep(1)


def signal_handler(sig, frame):
    """Handle Ctrl+C gracefully"""
    global running
    print(f"\n{YELLOW}Signal received. Shutting down...{RESET}")
    running = False
    sys.exit(0)


def verify_namespaces():
    """
    Verify all required network namespaces exist.
    
    Uses pyroute2 to check namespace availability:
    - Attempts to open each namespace with NetNS()
    - If successful, namespace exists and is accessible
    - If exception, namespace is missing or inaccessible
    
    This is cleaner than parsing 'ip netns list' output.
    
    Returns:
        tuple: (success: bool, missing_namespace: str or None)
    
    Example:
        ok, missing = verify_namespaces()
        if not ok:
            print(f"Namespace {missing} not found")
            # User needs to run mknetns-gre1.sh
    """
    missing = []
    for endpoint in ENDPOINTS.values():
        ns = endpoint['namespace']
        try:
            # Try to open the namespace
            test_ns = NetNS(ns)
            test_ns.close()
        except Exception:
            if ns not in missing:
                missing.append(ns)
    
    if missing:
        return False, missing[0]
    return True, None


def main():
    global logfile, running
    
    # Setup signal handler
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    # Banner
    print(f"\n{BOLD}{GREEN}{'='*100}{RESET}")
    print(f"{BOLD}{GREEN}{'Zscaler GRE Tunnel Orchestrator (pyroute2)':^100}{RESET}")
    print(f"{BOLD}{GREEN}{'VeloCloud SD-WAN Failover Testing Tool':^100}{RESET}")
    print(f"{BOLD}{GREEN}{'='*100}{RESET}\n")
    
    # Verify namespaces
    print("Verifying network namespaces...")
    ok, missing_ns = verify_namespaces()
    if not ok:
        print(f"{RED}ERROR: Namespace '{missing_ns}' not found!{RESET}")
        print(f"{YELLOW}Please run: sudo ./mknetns-gre1.sh && sudo ./doit.sh{RESET}")
        sys.exit(1)
    print(f"{GREEN}✓ All namespaces verified{RESET}\n")
    
    # Open log file
    timestamp = datetime.now().strftime('%Y%m%d-%H%M%S')
    logfile = open(f'orchestrator-pyroute2-{timestamp}.log', 'a', buffering=1)
    log_message("=== Orchestrator Started (pyroute2 version) ===")
    
    # Start listener threads
    print("Starting HTTP listeners...")
    threads = []
    for key in ENDPOINTS.keys():
        t = threading.Thread(target=listener_thread, args=(key,), daemon=True, name=f"listener-{key}")
        t.start()
        threads.append(t)
        time.sleep(0.5)
    
    print(f"{GREEN}✓ All listeners started{RESET}\n")
    time.sleep(2)
    
    # Start interactive CLI
    try:
        interactive_cli()
    except Exception as e:
        print(f"{RED}Fatal error: {e}{RESET}")
        import traceback
        traceback.print_exc()
    finally:
        running = False
        print(f"\n{YELLOW}Cleaning up...{RESET}")
        
        if logfile:
            log_message("=== Orchestrator Stopped ===")
            logfile.close()
        
        print(f"{GREEN}Shutdown complete{RESET}\n")


if __name__ == '__main__':
    main()
