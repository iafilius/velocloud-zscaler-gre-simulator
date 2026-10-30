# Quick Reference: 8-Tunnel VeloCloud Zscaler GRE Simulator

## 1. L7 Health Check Port & GRE Tunnel Matrix

| Port | Pool | Role | Edge WAN | Namespace | Simulated Zscaler VIP | GRE Tunnel | Inner Simulator IP | Inner Edge Peer IP |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **`7000`** | Guest | Primary | `GE1` (`.64`) | `gre1` | `192.168.1.242` | `gre21` | `172.20.67.74/30` | `172.20.67.73` |
| **`7001`** | Guest | Secondary | `GE1` (`.64`) | `gre2` | `192.168.1.243` | `gre22` | `172.20.67.78/30` | `172.20.67.77` |
| **`7002`** | Production | Primary | `GE1` (`.64`) | `gre1` | `192.168.1.240` | `gre1` | `172.21.12.162/30` | `172.21.12.161` |
| **`7003`** | Production | Secondary | `GE1` (`.64`) | `gre2` | `192.168.1.241` | `gre2` | `172.21.12.166/30` | `172.21.12.165` |
| **`7004`** | Guest | Primary | `GE2` (`.65`) | `gre1` | `192.168.1.242` | `gre31` | `172.20.67.66/30` | `172.20.67.65` |
| **`7005`** | Guest | Secondary | `GE2` (`.65`) | `gre2` | `192.168.1.243` | `gre32` | `172.20.67.70/30` | `172.20.67.69` |
| **`7006`** | Production | Primary | `GE2` (`.65`) | `gre1` | `192.168.1.240` | `gre11` | `172.21.12.154/30` | `172.21.12.153` |
| **`7007`** | Production | Secondary | `GE2` (`.65`) | `gre2` | `192.168.1.241` | `gre12` | `172.21.12.158/30` | `172.21.12.157` |

---

## 2. Orchestrator Command Cheat Sheet (`zscaler_orchestrator_pyroute2.py`)

### Toggle Individual Endpoints (`UP -> DEGRADED -> DOWN -> UP`)
```text
[1] Prod Primary GE1     (192.168.1.240:7002, gre1)
[2] Prod Secondary GE1   (192.168.1.241:7003, gre2)
[3] Guest Primary GE1    (192.168.1.242:7000, gre1)
[4] Guest Secondary GE1  (192.168.1.243:7001, gre2)
[5] Prod Primary GE2     (192.168.1.240:7006, gre1)
[6] Prod Secondary GE2   (192.168.1.241:7007, gre2)
[7] Guest Primary GE2    (192.168.1.242:7004, gre1)
[8] Guest Secondary GE2  (192.168.1.243:7005, gre2)
```

### Automated Failovers
```text
[p1] Production GE1 failover    (240:7002 -> 241:7003)
[p2] Production GE2 failover    (240:7006 -> 241:7007)
[g1] Guest GE1 failover         (242:7000 -> 243:7001)
[g2] Guest GE2 failover         (242:7004 -> 243:7005)
[pa] Production Both            (GE1 + GE2 Prod fail over simultaneously)
[ga] Guest Both                 (GE1 + GE2 Guest fail over simultaneously)
[b]  ALL                        (All 4 pools fail over simultaneously)
```

### Bulk & Utility Commands
```text
[u] All UP           [d] All DOWN         [c] Configure DEGRADED delay
[s] Refresh          [l] Logs             [n] Namespace info        [q] Quit
```

---

## 3. Essential Verification One-Liners

### On the Linux Simulator Host
```bash
# Check listening L7 sockets in both namespaces
sudo ip netns exec gre1 ss -tlnp
sudo ip netns exec gre2 ss -tlnp

# Check GRE tunnels and IP addresses
sudo ip netns exec gre1 ip -br addr
sudo ip netns exec gre2 ip -br addr
sudo ip netns exec gre1 ip tunnel show
sudo ip netns exec gre2 ip tunnel show

# Watch live L7 HTTP probes and GRE traffic on the wire
sudo tcpdump -i enp0s25 -n "proto gre or tcp portrange 7000-7007"
```

### On the VeloCloud SD-WAN Edge CLI
```bash
# Show active L7 health check table as sorted CSV
/opt/vc/bin/debug.py --l7_health_checks | jq -r '.[] | [ .cloud, .nvsIp, .dstPort ] | @csv' | sort

# Follow L7 health check probe logs in real time
tail -f /var/log/l7_health_check.log

# Check NVS destination port allocation in edged.log
grep NVS /var/log/edged.log | grep dst_port
```

