# Quick Reference: 8-Tunnel VeloCloud Zscaler GRE Simulator

## 1. L7 Health Check Port & GRE Tunnel Matrix

| Port | Segment & Cloud | DC Role | WAN $\rightarrow$ VIP | NetNS / GRE | Inner `/30` (Edge $\leftrightarrow$ Sim) |
| :-: | :--- | :--- | :--- | :--- | :--- |
| **`7000`** | **Guest** (`zscalerbeta.net`) | Primary (`0`) | `GE1 .64 -> .242` | `gre1` / `gre21` | `172.20.67.73 <-> .74` |
| **`7001`** | **Guest** (`zscalerbeta.net`) | Secondary (`1`) | `GE1 .64 -> .243` | `gre2` / `gre22` | `172.20.67.77 <-> .78` |
| **`7002`** | **Trusted** (`zscaler.net`) | Primary (`0`) | `GE1 .64 -> .240` | `gre1` / `gre1` | `172.21.12.161 <-> .162` |
| **`7003`** | **Trusted** (`zscaler.net`) | Secondary (`1`) | `GE1 .64 -> .241` | `gre2` / `gre2` | `172.21.12.165 <-> .166` |
| **`7004`** | **Guest** (`zscalerbeta.net`) | Primary (`0`) | `GE2 .65 -> .242` | `gre1` / `gre31` | `172.20.67.65 <-> .66` |
| **`7005`** | **Guest** (`zscalerbeta.net`) | Secondary (`1`) | `GE2 .65 -> .243` | `gre2` / `gre32` | `172.20.67.69 <-> .70` |
| **`7006`** | **Trusted** (`zscaler.net`) | Primary (`0`) | `GE2 .65 -> .240` | `gre1` / `gre11` | `172.21.12.153 <-> .154` |
| **`7007`** | **Trusted** (`zscaler.net`) | Secondary (`1`) | `GE2 .65 -> .241` | `gre2` / `gre12` | `172.21.12.157 <-> .158` |

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

