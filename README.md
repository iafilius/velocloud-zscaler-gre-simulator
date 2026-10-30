# VeloCloud SD-WAN to Zscaler ZIA GRE Tunnel Simulator & L7 Orchestrator

[![Linux Network Namespaces](https://img.shields.io/badge/Linux-Network%20Namespaces%20(netns)-FCC624?logo=linux&logoColor=black)](#1-end-to-end-network-architecture)
[![Python 3 + pyroute2](https://img.shields.io/badge/Python%203-pyroute2%20%2B%20setns()-3776AB?logo=python&logoColor=white)](ORCHESTRATOR_USAGE.md)
[![VMware VeloCloud SD-WAN](https://img.shields.io/badge/VMware-VeloCloud%20SD--WAN-607078?logo=vmware&logoColor=white)](docs/DEEP_DIVE_L7_VS_GRE_HEALTHCHECKS.md)
[![Zscaler ZIA](https://img.shields.io/badge/Zscaler-ZIA%208--Tunnel%20GRE-0076CE)](docs/DEEP_DIVE_NAMESPACES_AND_ROUTING.md)
[![License: MIT](https://img.shields.io/badge/License-MIT-10b981.svg)](LICENSE)

![VeloCloud SD-WAN to Zscaler ZIA 8-Tunnel & Dual Network Namespace Topology](docs/assets/hero-8-tunnel-topology.png)

## Overview

This project simulates a complete dual-datacenter **Zscaler Internet Access (ZIA)** GRE tunnel environment on a single Linux host to test, validate, and debug **VMware VeloCloud SD-WAN Edge** Cloud Security Service (CSS) behavior, Layer 7 health checks, and tunnel failover mechanisms.

Using **Linux Network Namespaces (`gre1` and `gre2`)**, a **MAC-preserving Linux Bridge (`br1`)**, **8 GRE tunnels**, and a **multi-threaded Python CLI Orchestrator (`pyroute2` + `setns()`)**, you can deterministically transition individual Zscaler endpoints or entire WAN pools between `UP`, `DEGRADED` (high RTT), and `DOWN` states in real time.

---

## Documentation Index

- **[`README.md`](README.md)** — Architecture overview, quick start, setup & teardown, and troubleshooting (this document).
- **[`ORCHESTRATOR_USAGE.md`](ORCHESTRATOR_USAGE.md)** — Complete guide to the interactive Python CLI tool (`zscaler_orchestrator_pyroute2.py`) for bringing endpoints and tunnels `UP`, `DEGRADED`, and `DOWN`.
- **[`QUICK_REFERENCE.md`](QUICK_REFERENCE.md)** — Port map (`7000`–`7007`), GRE tunnel matrix (`gre1`–`gre32`), CLI cheat sheet, and validation one-liners.
- **[`docs/DEEP_DIVE_NAMESPACES_AND_ROUTING.md`](docs/DEEP_DIVE_NAMESPACES_AND_ROUTING.md)** — In-depth explanation of why and how Linux Network Namespaces, `veth` pairs, MAC-preserving bridging, `accept_local=1`, `proxy_arp`, `setns()`, and the 3 return-path routing architectures work.
- **[`docs/DEEP_DIVE_L7_VS_GRE_HEALTHCHECKS.md`](docs/DEEP_DIVE_L7_VS_GRE_HEALTHCHECKS.md)** — Anatomy of VeloCloud **outside-the-tunnel** L7 HTTP health checks (`GET /vpntest`) vs. **inside-the-tunnel** L3 GRE keepalives and user traffic, Edge CLI diagnostics (`/opt/vc/bin/debug.py --l7_health_checks`), and firmware observations.
- **[`CHANGELOG.md`](CHANGELOG.md)** — Evolution from 4-tunnel single-WAN to 8-tunnel dual-WAN (`GE1` + `GE2`) simulation.

---

## 1. End-to-End Network Architecture: Clouds, Primary/Secondary DCs & Unique 3-Tuples

A production VeloCloud SD-WAN Edge with **2 WAN links (`GE1` and `GE2`)** and **2 Zscaler Clouds / CSS profiles (`Production: zscaler.net` and `Guest: zscalerbeta.net`)** builds **4 GRE connections per WAN interface (8 simultaneous GRE tunnels in total)**.

Every GRE tunnel—and its dedicated L7 HTTP health check port (`7000`–`7007`)—is uniquely defined by the **3-Tuple**:

$$\text{Unique Connection Tuple} = (\text{Zscaler Cloud}, \text{Datacenter Role [Primary / Secondary]}, \text{Edge WAN Interface [GE1 / GE2]})$$

### 1A. Logical Zscaler Cloud & Unique Tuple Hierarchy (4 Tunnels per Segment / 4 per WAN = 8 Total)

```mermaid
flowchart LR
    subgraph EDGE["VeloCloud SD-WAN Edge (2 Segments × 2 WANs = 8 GRE Tunnels)"]
        subgraph SEG_TRUSTED["Trusted / Production Segment (LAN 10.23.0.0/24)"]
            T_GE1["VeloCloud-GE1 (192.168.1.64)"]
            T_GE2["VeloCloud-GE2 (192.168.1.65)"]
        end
        subgraph SEG_GUEST["Guest Segment (LAN 172.16.0.0/24)"]
            G_GE1["VeloCloud-GE1 (192.168.1.64)"]
            G_GE2["VeloCloud-GE2 (192.168.1.65)"]
        end
    end

    subgraph CLOUD_PROD["Zscaler Cloud 1: zscaler.net (Trusted / Production)"]
        subgraph PROD_PRI["zscaler.net Primary DC (VIP: 192.168.1.240 | netns: gre1)"]
            T1["1. Trusted - GE1 - zscaler.net Primary\nGRE: gre1 (172.21.12.162/30) | L7: :7002"]
            T2["3. Trusted - GE2 - zscaler.net Primary\nGRE: gre11 (172.21.12.154/30) | L7: :7006"]
        end
        subgraph PROD_SEC["zscaler.net Secondary DC (VIP: 192.168.1.241 | netns: gre2)"]
            T3["2. Trusted - GE1 - zscaler.net Secondary\nGRE: gre2 (172.21.12.166/30) | L7: :7003"]
            T4["4. Trusted - GE2 - zscaler.net Secondary\nGRE: gre12 (172.21.12.158/30) | L7: :7007"]
        end
    end

    subgraph CLOUD_GUEST["Zscaler Cloud 2: zscalerbeta.net (Guest)"]
        subgraph GUEST_PRI["zscalerbeta.net Primary DC (VIP: 192.168.1.242 | netns: gre1)"]
            T5["5. Guest - GE1 - zscalerbeta.net Primary\nGRE: gre21 (172.20.67.74/30) | L7: :7000"]
            T6["7. Guest - GE2 - zscalerbeta.net Primary\nGRE: gre31 (172.20.67.66/30) | L7: :7004"]
        end
        subgraph GUEST_SEC["zscalerbeta.net Secondary DC (VIP: 192.168.1.243 | netns: gre2)"]
            T7["6. Guest - GE1 - zscalerbeta.net Secondary\nGRE: gre22 (172.20.67.78/30) | L7: :7001"]
            T8["8. Guest - GE2 - zscalerbeta.net Secondary\nGRE: gre32 (172.20.67.70/30) | L7: :7005"]
        end
    end

    T_GE1 -->|"gre1 (:7002)"| T1
    T_GE1 -->|"gre2 (:7003)"| T3
    T_GE2 -.->|"gre11 (:7006)"| T2
    T_GE2 -.->|"gre12 (:7007)"| T4

    G_GE1 -->|"gre21 (:7000)"| T5
    G_GE1 -->|"gre22 (:7001)"| T7
    G_GE2 -.->|"gre31 (:7004)"| T6
    G_GE2 -.->|"gre32 (:7005)"| T8

    style EDGE stroke:#3b82f6,stroke-width:2px
    style SEG_TRUSTED stroke:#0ea5e9,stroke-width:2px
    style SEG_GUEST stroke:#10b981,stroke-width:2px
    style CLOUD_PROD stroke:#0ea5e9,stroke-width:2px
    style CLOUD_GUEST stroke:#10b981,stroke-width:2px
    style PROD_PRI stroke:#10b981,stroke-width:2px
    style GUEST_PRI stroke:#10b981,stroke-width:2px
    style PROD_SEC stroke:#8b5cf6,stroke-width:2px
    style GUEST_SEC stroke:#8b5cf6,stroke-width:2px
```

### 1B. Physical Host Bridge (`br1`) & Linux Network Namespace Mapping (`gre1` vs `gre2`)

To terminate all 8 GRE tunnels on a single Linux laptop/server without routing table collisions (`10.23.0.0/24` and `172.16.0.0/24`) or local IP bypass, the simulator maps **all Primary DCs (`.240` & `.242`) into namespace `gre1`** and **all Secondary DCs (`.241` & `.243`) into namespace `gre2`**, connected via a MAC-preserving Linux Bridge (`br1`):

```mermaid
flowchart TB
    subgraph UNDERLAY["Physical LAN / WAN Underlay (192.168.1.0/24)"]
        EDGE_WAN["VeloCloud Edge WANs: GE1 (.64) & GE2 (.65)"]
        GW["Upstream Gateway / Internet: 192.168.1.254"]
    end

    subgraph HOST["Linux Simulator Host (Default Namespace)"]
        NIC["Physical NIC: enp0s25 (IP flushed)"]
        BR1["Linux Bridge: br1 (Clones enp0s25 MAC + DHCP IP)"]
        VA1["veth-a1"]
        VA2["veth-a2"]
        NIC --> BR1
        BR1 --> VA1
        BR1 --> VA2
    end

    subgraph NS_GRE1["Network Namespace: gre1 (Hosts BOTH Primary Zscaler DCs)"]
        VB1["veth-b1"]
        PRI_C1["Cloud 1 Primary DC (zscaler.net — VIP 192.168.1.240)\n- GE1 Tuple: gre1 (172.21.12.162/30) + L7 :7002\n- GE2 Tuple: gre11 (172.21.12.154/30) + L7 :7006"]
        PRI_C2["Cloud 2 Primary DC (zscalerbeta.net — VIP 192.168.1.242)\n- GE1 Tuple: gre21 (172.20.67.74/30) + L7 :7000\n- GE2 Tuple: gre31 (172.20.67.66/30) + L7 :7004"]
        VB1 --> PRI_C1
        VB1 --> PRI_C2
    end

    subgraph NS_GRE2["Network Namespace: gre2 (Hosts BOTH Secondary Zscaler DCs)"]
        VB2["veth-b2"]
        SEC_C1["Cloud 1 Secondary DC (zscaler.net — VIP 192.168.1.241)\n- GE1 Tuple: gre2 (172.21.12.166/30) + L7 :7003\n- GE2 Tuple: gre12 (172.21.12.158/30) + L7 :7007"]
        SEC_C2["Cloud 2 Secondary DC (zscalerbeta.net — VIP 192.168.1.243)\n- GE1 Tuple: gre22 (172.20.67.78/30) + L7 :7001\n- GE2 Tuple: gre32 (172.20.67.70/30) + L7 :7005"]
        VB2 --> SEC_C1
        VB2 --> SEC_C2
    end

    EDGE_WAN <-->|"8 GRE Tunnels + 8 L7 Probes"| NIC
    VA1 <-->|"Virtual Ethernet Pipe"| VB1
    VA2 <-->|"Virtual Ethernet Pipe"| VB2

    style HOST stroke:#64748b,stroke-width:2px
    style NS_GRE1 stroke:#10b981,stroke-width:2px
    style NS_GRE2 stroke:#8b5cf6,stroke-width:2px
```

<details>
<summary>📟 View Terminal-Friendly ASCII Topology Diagram</summary>

```text
+-----------------------------------------------------------------------------+
|                        Physical LAN / WAN Underlay                          |
|                          192.168.1.0/24 (DHCP)                              |
|                     Gateway / Internet: 192.168.1.254                       |
+--------------------------------------+--------------------------------------+
                                       |
                                +------+------+
                                |   enp0s25   | Physical NIC (IP flushed)
                                +------+------+
                                       |
                                +------+------+
                                |     br1     | Linux Bridge (inherits enp0s25
                                |  (DHCP IP)  | MAC address to keep DHCP lease)
                                +--+-------+--+
                                   |       |
                            +------+--+ +--+------+
                            | veth-a1 | | veth-a2 | Host-side veth interfaces
                            +----+----+ +----+----+
                                 |           |
                            +----+----+ +----+----+
                            | veth-b1 | | veth-b2 | Namespace-side veths
                            +----+----+ +----+----+
                                 |           |
        +------------------------+--+     +--+------------------------+
        |  Network Namespace: gre1  |     |  Network Namespace: gre2  |
        |   (Primary Zscaler DC)    |     |  (Secondary Zscaler DC)   |
        +---------------------------+     +---------------------------+
        | WAN IP Aliases (veth-b1): |     | WAN IP Aliases (veth-b2): |
        | - 192.168.1.240/24 (Prod) |     | - 192.168.1.241/24 (Prod) |
        | - 192.168.1.242/24 (Guest)|     | - 192.168.1.243/24 (Guest)|
        |                           |     |                           |
        | Production GRE Tunnels:   |     | Production GRE Tunnels:   |
        | +-----------------------+ |     | +-----------------------+ |
        | | gre1:  172.21.12.162  | |     | | gre2:  172.21.12.166  | |
        | | peer .161 --> GE1 .64 | |     | | peer .165 --> GE1 .64 | |
        | +-----------------------+ |     | +-----------------------+ |
        | +-----------------------+ |     | +-----------------------+ |
        | | gre11: 172.21.12.154  | |     | | gre12: 172.21.12.158  | |
        | | peer .153 --> GE2 .65 | |     | | peer .157 --> GE2 .65 | |
        | +-----------------------+ |     | +-----------------------+ |
        |                           |     |                           |
        | Guest GRE Tunnels:        |     | Guest GRE Tunnels:        |
        | +-----------------------+ |     | +-----------------------+ |
        | | gre21: 172.20.67.74   | |     | | gre22: 172.20.67.78   | |
        | | peer .73  --> GE1 .64 | |     | | peer .77  --> GE1 .64 | |
        | +-----------------------+ |     | +-----------------------+ |
        | +-----------------------+ |     | +-----------------------+ |
        | | gre31: 172.20.67.66   | |     | | gre32: 172.20.67.70   | |
        | | peer .65  --> GE2 .65 | |     | | peer .69  --> GE2 .65 | |
        | +-----------------------+ |     | +-----------------------+ |
        |                           |     |                           |
        | L7 HTTP Listeners:        |     | L7 HTTP Listeners:        |
        | - .240:7002 (Prod GE1)    |     | - .241:7003 (Prod GE1)    |
        | - .240:7006 (Prod GE2)    |     | - .241:7007 (Prod GE2)    |
        | - .242:7000 (Guest GE1)   |     | - .243:7001 (Guest GE1)   |
        | - .242:7004 (Guest GE2)   |     | - .243:7005 (Guest GE2)   |
        +-------------+-------------+     +-------------+-------------+
                      |                                 |
                      +----------------+----------------+
                                       |
                         All 8 GRE tunnels & L7 probes
                         terminate at VeloCloud Edge:
                         +---------------------------+
                         | GE1 (WAN1): 192.168.1.64  |
                         | GE2 (WAN2): 192.168.1.65  |
                         +---------------------------+
```

</details>

### Simulated Zscaler Endpoints & Tunnel Matrix

| Endpoint Role | Simulated Zscaler VIP | Namespace | WAN Link | Edge WAN IP | GRE Interface | Simulator Inner IP (/30) | Edge Inner Peer IP | L7 Health Check Port |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Prod Primary (GE1)** | `192.168.1.240` | `gre1` | `GE1` | `192.168.1.64` | `gre1` | `172.21.12.162/30` | `172.21.12.161` | `7002` |
| **Prod Primary (GE2)** | `192.168.1.240` | `gre1` | `GE2` | `192.168.1.65` | `gre11` | `172.21.12.154/30` | `172.21.12.153` | `7006` |
| **Prod Secondary (GE1)** | `192.168.1.241` | `gre2` | `GE1` | `192.168.1.64` | `gre2` | `172.21.12.166/30` | `172.21.12.165` | `7003` |
| **Prod Secondary (GE2)** | `192.168.1.241` | `gre2` | `GE2` | `192.168.1.65` | `gre12` | `172.21.12.158/30` | `172.21.12.157` | `7007` |
| **Guest Primary (GE1)** | `192.168.1.242` | `gre1` | `GE1` | `192.168.1.64` | `gre21` | `172.20.67.74/30` | `172.20.67.73` | `7000` |
| **Guest Primary (GE2)** | `192.168.1.242` | `gre1` | `GE2` | `192.168.1.65` | `gre31` | `172.20.67.66/30` | `172.20.67.65` | `7004` |
| **Guest Secondary (GE1)** | `192.168.1.243` | `gre2` | `GE1` | `192.168.1.64` | `gre22` | `172.20.67.78/30` | `172.20.67.77` | `7001` |
| **Guest Secondary (GE2)** | `192.168.1.243` | `gre2` | `GE2` | `192.168.1.65` | `gre32` | `172.20.67.70/30` | `172.20.67.69` | `7005` |

---

## 2. Outside-the-Tunnel L7 Monitoring vs. Inside-the-Tunnel GRE Traffic

One of the most important architectural insights when debugging VeloCloud SD-WAN with Zscaler CSS is understanding that **L7 Health Checks and GRE Tunnel Traffic take two different paths**:

![Outside-the-Tunnel L7 Health Checks vs. Inside-the-Tunnel GRE Traffic](docs/assets/l7-outside-vs-gre-inside.png)

```mermaid
flowchart LR
    subgraph EDGE["VeloCloud SD-WAN Edge (.64 / .65)"]
        L7_DAEMON["l7_health_check.py (src 169.254.3.x -> NAT to .64/.65)"]
        EDGED["edged Dataplane (GRE Encapsulation Engine)"]
    end

    subgraph PATH_A["PATH A: OUTSIDE THE GRE TUNNEL (WAN Underlay TCP)"]
        TCP_PROBE["Direct TCP to .240..243 : Ports 7000..7007\nGET /vpntest HTTP/1.1\nHost: gateway.zscalertwo.net"]
    end

    subgraph PATH_B["PATH B: INSIDE THE GRE TUNNEL (IP Protocol 47)"]
        GRE_PIPE["GREv0 Tunnel Interfaces (gre1..gre32)\n1. L3 GRE Keepalives (gre-proto-0x0)\n2. Backhauled LAN Traffic (10.23.0.0/24, 172.16.0.0/24)"]
    end

    subgraph SIM["Linux Network Namespace Simulator (gre1 & gre2)"]
        ORCH["Python Orchestrator Thread (setns)\n- UP: 200 OK (0ms)\n- DEGRADED: 200 OK (+4000ms)\n- DOWN: 503 Unavailable"]
        KERNEL_GRE["Linux Kernel ip_gre Decapsulation\n-> Namespace Routing Table\n-> iptables MASQUERADE NAT -> Internet"]
    end

    L7_DAEMON -->|"Bypasses GRE Tunnel"| TCP_PROBE --> ORCH
    EDGED -->|"Encapsulated Proto 47"| GRE_PIPE --> KERNEL_GRE

    style PATH_A stroke:#10b981,stroke-width:2px
    style PATH_B stroke:#3b82f6,stroke-width:2px
    style ORCH stroke:#10b981,stroke-width:2px
    style KERNEL_GRE stroke:#3b82f6,stroke-width:2px
```

<details>
<summary>📟 View Terminal-Friendly ASCII Split-Path Diagram</summary>

```text
+-----------------------------------------------------------------------------+
|            VELOCLOUD SD-WAN EDGE (GE1: .64 / GE2: .65)                      |
+-----------------------------------------------------------------------------+
       |                                                       |
       | PATH A: OUTSIDE THE GRE TUNNEL (WAN Underlay TCP)     | PATH B: INSIDE THE GRE TUNNEL (IP Proto 47)
       | -------------------------------------------------     | -------------------------------------------
       | * Source IP: 192.168.1.64 (GE1) or 192.168.1.65 (GE2) | * Outer IP: .64/.65 <--> .240/.241/.242/.243
       |   (internally originated from 169.254.3.x on Edge)    | * Inner IP: /30 tunnel IPs (172.21.12.x,
       | * Destination: 192.168.1.240..243, TCP port 7000..7007|   172.20.67.x) or LAN subnets (10.23.0.0/24,
       | * Payload:                                            |   172.16.0.0/24)
       |     GET /vpntest HTTP/1.1                             | * Traffic types:
       |     Host: gateway.zscalertwo.net                      |   1) L3 GRE Keepalives (gre-proto-0x0 with
       |     Accept: */*                                       |      mirrored inner IP headers)
       |     User-Agent: VMware SD-WAN                         |   2) Backhauled user traffic (HTTP/HTTPS,
       | * Traverses: enp0s25 -> br1 -> veth-a -> veth-b       |      DNS, ICMP) steered by Business Policy
       |   (NEVER enters gre1..gre32 tunnel interfaces!)       | * Traverses: gre1..gre32 tunnel interfaces
       v                                                       v
+-------------------------------------+ +-------------------------------------+
| Python Orchestrator Listener Thread | | Linux Kernel ip_gre Decapsulation   |
| (bound to .240..243:7000..7007      | | -> Namespace Routing Table          |
|  inside netns gre1 / gre2)          | | -> iptables MASQUERADE NAT          |
|                                     | | -> Outbound via veth-b -> Internet  |
| Replies:                            | +-------------------------------------+
| - UP:       200 OK ("OK", 0s delay) |
| - DEGRADED: 200 OK ("DEGRADED", +4s)|
| - DOWN:     503 Service Unavailable |
+-------------------------------------+
```

</details>

### Key Takeaways (See [`docs/DEEP_DIVE_L7_VS_GRE_HEALTHCHECKS.md`](docs/DEEP_DIVE_L7_VS_GRE_HEALTHCHECKS.md) for full details)

1. **L7 Health Checks run OUTSIDE the GRE tunnel:** VeloCloud's `l7_health_check.py` daemon connects via standard TCP directly to the Zscaler VIP (`192.168.1.240`–`.243`) on dynamically mapped local ports (`7000`–`7007`, chosen from range `7000`–`7063`).
2. **Why ports 7000–7007?** Internally, VeloCloud's `edged` process assigns a unique TCP port (`7000`..`7063`) per combination of Zscaler Cloud (`nvsLogicalId`), Destination (`Primary` vs `Secondary`), and WAN Link (`linkLogicalId` for `GE1` vs `GE2`), and translates outbound `/vpntest` probes accordingly.
3. **Both L3 GRE and L7 HTTP must succeed:** If L7 `/vpntest` returns `HTTP 200 OK` within the 3000 ms RTT threshold, `l7_health_check.log` reports success. However, if GRE tunnel interfaces or GRE keepalives (`gre-proto-0x0`) are down, the VeloCloud Orchestrator (VCO) will still mark the tunnel as `Failed`.

---

## 3. Interactive CLI Orchestrator (`zscaler_orchestrator_pyroute2.py`)

Instead of static `netcat` loops that only ever return `200 OK`, [`zscaler_orchestrator_pyroute2.py`](zscaler_orchestrator_pyroute2.py) provides an interactive terminal dashboard that controls all 8 Zscaler endpoints simultaneously:

- **Direct `setns(CLONE_NEWNET)` thread binding:** Spawns 8 daemon threads in a single Python process. Each thread opens `/var/run/netns/gre1` or `/var/run/netns/gre2` and calls `libc.setns()` via `ctypes` so its listening socket is permanently bound inside the target namespace.
- **Real-time state control:**
  - **`[1]`–`[8]`**: Cycle any single endpoint through **`UP`** (`200 OK` immediately) -> **`DEGRADED`** (`200 OK` delayed by `4.0s`, exceeding VeloCloud's `3.0s` RTT threshold) -> **`DOWN`** (`503 Service Unavailable`).
  - **`[p1]`, `[p2]`, `[g1]`, `[g2]`**: Run an automated 3-stage failover (Primary degrades -> Primary fails -> Secondary takes over) on a single WAN interface.
  - **`[pa]`, `[ga]`, `[b]`**: Trigger multi-interface or total chaos failovers across both `GE1` and `GE2` simultaneously.
  - **`[u]` / `[d]`**: Bring all 8 endpoints `UP` or `DOWN` at once.
  - **`[c]`**: Dynamically adjust the `DEGRADED` delay (e.g., `< 3.0s` for sub-threshold latency testing vs. `> 3.0s` to trigger RTT-based failover).

See **[`ORCHESTRATOR_USAGE.md`](ORCHESTRATOR_USAGE.md)** for full dashboard examples and failover timelines.

---

## 4. Usage Instructions

### Prerequisites & Pre-Flight Checks

1. **Console or Out-of-Band Access:** `mknetns-gre1.sh` stops `NetworkManager` and moves `enp0s25` into bridge `br1`. Although `br1` inherits `enp0s25`'s MAC address to retain the same DHCP IP, brief link interruption occurs during setup.
2. **Required Packages:**
   ```bash
   sudo apt-get update
   sudo apt-get install -y iproute2 bridge-utils jq isc-dhcp-client iptables conntrack python3-pyroute2
   ```
3. **Physical Interface Name:** Verify `NIC="enp0s25"` in `mknetns-gre1.sh` and `cleanup.sh` matches your host's physical interface.

### Step-by-Step Execution Order

```mermaid
flowchart LR
    S1["1. sudo ./mknetns-gre1.sh\n(Bridge br1 + NetNS gre1 & gre2)"] --> S2["2. sudo ./doit.sh\n(VIPs .240-.243 + 8 GRE Tunnels + NAT)"]
    S2 --> S3["3. sudo ./zscaler_orchestrator_pyroute2.py\n(8 L7 Listeners + Failover CLI)"]
    S3 --> S4["4. sudo ./cleanup.sh\n(Teardown & Restore NIC)"]
    style S1 stroke:#3b82f6,stroke-width:2px
    style S2 stroke:#10b981,stroke-width:2px
    style S3 stroke:#8b5cf6,stroke-width:2px
    style S4 stroke:#f59e0b,stroke-width:2px
```

<details>
<summary>📟 View Terminal-Friendly ASCII Execution Flow</summary>

```text
1. sudo ./mknetns-gre1.sh                --> Creates bridge br1, veth pairs, namespaces gre1 & gre2
          |
          v
2. sudo ./doit.sh                        --> Configures .240-.243 VIPs, 8 GRE tunnels, NAT & routes
          |
          v
3. sudo ./zscaler_orchestrator_pyroute2.py --> Starts 8 L7 HTTP listeners & interactive failover CLI
          |
          v
4. sudo ./cleanup.sh                     --> Tears down tunnels, namespaces, bridge & restores NIC
```

</details>

```bash
# 1. Make scripts executable
chmod +x mknetns-gre1.sh doit.sh cleanup.sh zscaler_orchestrator_pyroute2.py

# 2. Build bridge and network namespaces (with automatic pre-flight checks)
sudo ./mknetns-gre1.sh

# 3. Configure IP aliases, 8 GRE tunnels, routing, and iptables MASQUERADE
sudo ./doit.sh

# 4. Launch the interactive L7 Health Check Orchestrator
sudo ./zscaler_orchestrator_pyroute2.py
```

---

## 5. Verification Commands

```bash
# Verify namespaces exist
ip netns list

# Verify bridge br1 and attached veth/physical ports
ip link show br1
bridge link show

# Inspect IP aliases and GRE tunnels inside gre1 (Primary DC) and gre2 (Secondary DC)
sudo ip netns exec gre1 ip addr
sudo ip netns exec gre1 ip tunnel show
sudo ip netns exec gre2 ip addr
sudo ip netns exec gre2 ip tunnel show

# Verify all 8 L7 HTTP listeners (ports 7000-7007) inside namespaces
sudo ip netns exec gre1 ss -tlnp
sudo ip netns exec gre2 ss -tlnp

# Ping VeloCloud Edge WAN interfaces from gre1
sudo ip netns exec gre1 ping -c 3 192.168.1.64
sudo ip netns exec gre1 ping -c 3 192.168.1.65

# Ping across the inner GRE tunnel (/30 peer IP on Edge)
sudo ip netns exec gre1 ping -c 3 -I gre1 172.21.12.161

# Capture live GRE traffic (IP protocol 47) or L7 probes (ports 7000-7007)
sudo tcpdump -i enp0s25 -n "proto gre or tcp portrange 7000-7007"
```

---

## 6. Troubleshooting & Co-Existence with LAN Client Labs

### Macvlan Conflict & Automatic Migration (`mknetns-gre1.sh`)
If you also run a companion VeloCloud LAN/client namespace lab (`velocloud-lan-client-netns-macvlan-setup.sh`) that attaches a `macvlan` interface (`macvlanhostos` in namespace `nshost`) directly to `enp0s25`, Linux forbids enslaving `enp0s25` to bridge `br1` (`RTNETLINK answers: Device or resource busy`).

`mknetns-gre1.sh` automatically detects any `macvlan` children on `enp0s25` across all namespaces and offers **Option 2 (Automatic Migration)**:
- Saves the existing `macvlan` IP address, link state, and default route.
- Recreates the `macvlan` interface on top of `br1` (`link br1 type macvlan mode bridge`) instead of `enp0s25`.
- Moves it back into its namespace (`nshost`) and restores its IP and routes so **both the WAN Zscaler simulator and the LAN Client lab can run simultaneously on the same host**.

### Restoring Connectivity After an Interrupted Run
If a setup is interrupted mid-flight, run:
```bash
sudo ./cleanup.sh
```
Or manually restore `enp0s25`:
```bash
sudo ip link set dev enp0s25 nomaster 2>/dev/null || true
sudo ip link set dev enp0s25 up
sudo dhclient enp0s25
sudo systemctl start NetworkManager
```
