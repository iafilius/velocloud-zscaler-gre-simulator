# Changelog

## Version 2.0 — 8-Tunnel Dual-WAN Support (`GE1` + `GE2`)

### Overview
Extended the Zscaler GRE Tunnel Simulator and Python `pyroute2` Orchestrator from 4 tunnels (single Edge WAN interface `GE1`) to **8 tunnels total** (4 tunnels per VeloCloud Edge WAN interface across `GE1` and `GE2`).

### What Changed

1. **8 L7 Health Check Endpoints (`7000`–`7007`):**
   - **GE1 Endpoints (`192.168.1.64`):**
     - `192.168.1.240:7002` — Prod Primary GE1 (`gre1` namespace, tunnel `gre1`)
     - `192.168.1.241:7003` — Prod Secondary GE1 (`gre2` namespace, tunnel `gre2`)
     - `192.168.1.242:7000` — Guest Primary GE1 (`gre1` namespace, tunnel `gre21`)
     - `192.168.1.243:7001` — Guest Secondary GE1 (`gre2` namespace, tunnel `gre22`)
   - **GE2 Endpoints (`192.168.1.65`):**
     - `192.168.1.240:7006` — Prod Primary GE2 (`gre1` namespace, tunnel `gre11`)
     - `192.168.1.241:7007` — Prod Secondary GE2 (`gre2` namespace, tunnel `gre12`)
     - `192.168.1.242:7004` — Guest Primary GE2 (`gre1` namespace, tunnel `gre31`)
     - `192.168.1.243:7005` — Guest Secondary GE2 (`gre2` namespace, tunnel `gre32`)

2. **Interactive CLI Orchestrator (`zscaler_orchestrator_pyroute2.py`):**
   - Added keys `[1]`–`[8]` for independent per-interface endpoint state cycling (`UP -> DEGRADED -> DOWN -> UP`).
   - Added single-interface (`[p1]`, `[p2]`, `[g1]`, `[g2]`) and dual-interface (`[pa]`, `[ga]`, `[b]`) failover orchestration.
   - Added configurable `DEGRADED_DELAY` (`[c]`) to test sub-threshold vs. above-threshold (`3.0s`) VeloCloud L7 RTT behavior.

3. **Automatic Macvlan Co-Existence Migration (`mknetns-gre1.sh`):**
   - Detects existing `macvlan` interfaces on the physical NIC across all namespaces and offers automatic migration onto bridge `br1` so companion LAN/client labs and the WAN Zscaler simulator can run concurrently.

