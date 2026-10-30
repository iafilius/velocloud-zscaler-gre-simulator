# Official Zscaler / SD-WAN Documentation Pointers & Cross-Vendor Lab Notes

Rather than duplicating official vendor deployment guides, this document provides **curated links to the authoritative Zscaler, Broadcom (VeloCloud), and Cisco documentation**, followed by the **undocumented wire-level differences and Linux simulator tips** needed when testing **VeloCloud SD-WAN** vs. **Cisco Catalyst SD-WAN (cEdge / IOS-XE)** against Zscaler GRE tunnels.

---

## 1. Official Vendor Documentation & Best-Practice Pointers

### Zscaler Internet Access (ZIA) — Core GRE & Health Monitoring
- **[About GRE Tunnels (Zscaler ZIA Help Portal)](https://help.zscaler.com/zia/about-gre-tunnels)** — Architectural overview of keyless GREv0 (`IP Protocol 47`), `/29` internal IP range allocation (split into two `/30` subnets for Primary and Secondary DCs), and un-NATted internal IP visibility for Zscaler Sub-Locations.
- **[Configuring GRE Tunnels (Zscaler ZIA Help Portal)](https://help.zscaler.com/zia/configuring-gre-tunnels)** — Step-by-step ZIA Admin Portal workflow for registering static WAN IPs, provisioning GRE tunnels, and binding Locations/Sub-Locations.
- **[Best Practices for Deploying GRE Tunnels (Zscaler ZIA Help Portal)](https://help.zscaler.com/zia/best-practices-deploying-gre-tunnels)** — Official Zscaler recommendations on:
  - **Primary + Secondary ZEN Redundancy:** Always terminate tunnels on two geographically distinct Zscaler Data Centers (VIPs).
  - **GRE MTU & TCP MSS Clamping:** Standard IPv4 GRE adds **24 bytes** of overhead (`20B Outer IP + 4B GRE`). On a `1500`-byte WAN interface, set **Tunnel MTU = `1476`** and **TCP MSS = `1436`** (or `1360` conservatively across path MTU bottlenecks) so Zscaler Service Edges never receive fragmented GRE packets.
  - **L7 Health Check Endpoint (`vpntest`):** Probe `http://gateway.<zscaler_cloud_name>/vpntest` (e.g., `http://gateway.zscaler.net/vpntest`) rather than third-party websites (`google.com`, etc.) to avoid rate-limiting or CAPTCHAs.

### VMware VeloCloud SD-WAN + Zscaler ZIA
- **[Zscaler and VMware SD-WAN by VeloCloud Deployment Guide (Official PDF)](https://docs.broadcom.com/docs/Zscaler-VMware-SDWAN-Deployment-Guide)** — Reference guide for configuring Zscaler Cloud Security Service (CSS), manual vs. automated GRE tunnels, L7 health checks, and Business Policy traffic steering in VeloCloud Orchestrator (VCO).
- **[VMware VeloCloud SD-WAN Release Notes & Known Issues (Broadcom TechDocs)](https://techdocs.broadcom.com/us/en/vmware-sde/velocloud-sase/vmware-velocloud-sd-wan/6-2.html)** — Official release notes covering CSS/Zscaler defect fixes (`60073`, `79598`, `81852`, `83526`, `122029`, `134332`, `136336`; summarized in [`DEEP_DIVE_L7_VS_GRE_HEALTHCHECKS.md`](DEEP_DIVE_L7_VS_GRE_HEALTHCHECKS.md#5-known-velocloud-firmware-quirks--public-defect-references)).

### Cisco Catalyst SD-WAN (Viptela / cEdge IOS-XE) + Zscaler ZIA
- **[Zscaler and Cisco SD-WAN Deployment Guide (Official Zscaler Partner PDF)](https://help.zscaler.com/downloads/zscaler-technology-partners/c-e/zscaler-and-cisco-sd-wan-deployment-guide/Zscaler-Cisco-SD-WAN-Deployment-Guide-FINAL.pdf)** — End-to-end joint deployment guide for Cisco Catalyst SD-WAN (vManage / SD-WAN Manager) with Zscaler ZIA via Secure Internet Gateway (SIG) templates, GRE keepalives, and service-side routing.
- **[Cisco Catalyst SD-WAN Security Configuration Guide: Secure Internet Gateway (SIG)](https://www.cisco.com/c/en/us/td/docs/routers/sdwan/configuration/security/ios-xe-17/security-book-xe/m-secure-internet-gateway.html)** — Official Cisco IOS-XE 17.x documentation for SIG GRE tunnel templates, active/backup vs. active/active ECMP weighting, tracker/health-check configuration, and `show sdwan sig` / `show sse` verification commands.
- **[Zscaler GRE Configuration Example: Cisco ISR Router (Zscaler Help Portal)](https://help.zscaler.com/legacy-zia/gre-configuration-example-cisco-881-isr)** — Classic autonomous Cisco IOS/IOS-XE configuration showing `interface Tunnel`, `keepalive 10 3`, `ip tcp adjust-mss`, `ip sla` HTTP `/vpntest` probing, `track`, and Policy-Based Routing (PBR).

---

## 2. Undocumented Wire-Level Deltas: VeloCloud vs. Cisco Catalyst SD-WAN

When capturing packets (`tcpdump`) on the WAN underlay or reusing this Linux namespace simulator (`gre1` / `gre2`) with a **Cisco Catalyst SD-WAN (cEdge)** router, three critical wire-level behavioral differences stand out compared to **VeloCloud SD-WAN**:

| Behavior | VMware VeloCloud SD-WAN Edge | Cisco Catalyst SD-WAN (`cEdge` IOS-XE) |
| :--- | :--- | :--- |
| **L3 GRE Keepalive Inner IPs (`gre-proto-0x0`)** | Uses **inner `/30` tunnel IPs** (`src: 172.21.12.162 -> dst: 172.21.12.161`). Reflected packet is routed **back inside the GRE tunnel** (GRE-in-GRE both ways). | Uses **outer WAN IPs** (`src: 192.168.1.240 -> dst: 192.168.1.64`). Reflected packet is forwarded **unencapsulated on the WAN underlay** (`veth-b1`). |
| **L7 HTTP `/vpntest` Path & Port** | Sent **OUTSIDE the GRE tunnel** on dynamically mapped TCP ports **`7000`–`7063`** directly to the outer Zscaler VIP (`.240`–`.243`). | Sent **INSIDE the GRE tunnel** on standard **TCP Port `80`** (`GET http://gateway.<cloud>/vpntest` via IP SLA / SIG tracker). |
| **Multi-Segment / Multi-VRF Separation** | Maps each Segment to its own CSS / Zscaler Cloud VIP pair so every tunnel has a unique outer `(WAN IP, VIP)` tuple. | Can either share a SIG GRE tunnel across Service VPNs (using Zscaler Sub-Locations by internal `/24` source subnet) or use distinct source WAN IPs / VIPs. |

---

## 3. Linux Simulator Tips for Cisco Catalyst SD-WAN Labbing

### Tip 1: Why `rp_filter=0` Is Required for Cisco GRE Keepalives (`keepalive 10 3`)
When a Cisco IOS-XE / `cEdge` router sends a GRE keepalive from `192.168.1.64` to `192.168.1.240`, the packet on the wire is:
- **Outer IP Header:** `192.168.1.64 -> 192.168.1.240` (`IP Protocol 47`)
- **Inner IP Header (inside GRE):** `192.168.1.240 -> 192.168.1.64` (`IP Protocol 47`, `GRE Proto 0x0000`)

When Linux decapsulates the outer header on `gre1`, the inner packet appears to arrive on interface `gre1` with `src=192.168.1.240` (which is a local IP owned by `veth-b1` in the same namespace).
- If `rp_filter` is `1` or `2` (Ubuntu's default), the Linux kernel drops the decapsulated Cisco keepalive as a Martian (`IPv4: martian source 192.168.1.64 from 192.168.1.240, on dev gre1`).
- **`doit.sh` includes `accept_local=1` and `rp_filter=0`** on `all`, `default`, and `gre*` in both `gre1` and `gre2`, allowing the Linux kernel to accept and reflect both VeloCloud (inner `/30`) and Cisco (outer VIP) GRE keepalives automatically.

### Tip 2: Steering Cisco's Inside-the-Tunnel Port `80` `/vpntest` Probes to the Python Orchestrator
If you configure a Cisco `cEdge` / IOS-XE router to run an **inside-the-tunnel** HTTP health check (`GET /vpntest` on **TCP Port `80`**) through the GRE tunnels (`gre1`..`gre32`), you can steer those port `80` requests directly into the existing [`zscaler_orchestrator_pyroute2.py`](../zscaler_orchestrator_pyroute2.py) listener threads (`7000`–`7007`) without modifying a single line of Python code:

```bash
# Inside gre1 (Primary DC): Redirect inside-the-tunnel TCP port 80 probes to the matching orchestrator port
sudo ip netns exec gre1 iptables -t nat -A PREROUTING -i gre1  -p tcp --dport 80 -j DNAT --to-destination 192.168.1.240:7002
sudo ip netns exec gre1 iptables -t nat -A PREROUTING -i gre11 -p tcp --dport 80 -j DNAT --to-destination 192.168.1.240:7006
sudo ip netns exec gre1 iptables -t nat -A PREROUTING -i gre21 -p tcp --dport 80 -j DNAT --to-destination 192.168.1.242:7000
sudo ip netns exec gre1 iptables -t nat -A PREROUTING -i gre31 -p tcp --dport 80 -j DNAT --to-destination 192.168.1.242:7004

# Inside gre2 (Secondary DC): Redirect inside-the-tunnel TCP port 80 probes to the matching orchestrator port
sudo ip netns exec gre2 iptables -t nat -A PREROUTING -i gre2  -p tcp --dport 80 -j DNAT --to-destination 192.168.1.241:7003
sudo ip netns exec gre2 iptables -t nat -A PREROUTING -i gre12 -p tcp --dport 80 -j DNAT --to-destination 192.168.1.241:7007
sudo ip netns exec gre2 iptables -t nat -A PREROUTING -i gre22 -p tcp --dport 80 -j DNAT --to-destination 192.168.1.243:7001
sudo ip netns exec gre2 iptables -t nat -A PREROUTING -i gre32 -p tcp --dport 80 -j DNAT --to-destination 192.168.1.243:7005
```

With those 8 `DNAT` rules active, pressing `[1]`–`[8]`, `[p1]`, `[p2]`, etc. in `zscaler_orchestrator_pyroute2.py` controls `UP` (`200 OK`), `DEGRADED` (`+4s` delay), and `DOWN` (`503 Service Unavailable`) for **both** VeloCloud outside-the-tunnel probes (`:7000–7007`) and Cisco inside-the-tunnel probes (`:80`) simultaneously!

### Tip 3: Simulating Pure Layer 3 GRE Keepalive Outages
Because `zscaler_orchestrator_pyroute2.py` operates at Layer 7 (HTTP), a Cisco router configured **only** with Layer 3 GRE keepalives (`keepalive 10 3`) and no HTTP tracker will keep its tunnel `UP` unless Layer 3 GRE keepalive reflection is interrupted. To test L3 GRE keepalive failover on a specific tunnel (e.g., `gre1`):

```bash
# Option A: Bring down the specific GRE tunnel interface inside gre1
sudo ip -n gre1 link set dev gre1 down
# Restore:
sudo ip -n gre1 link set dev gre1 up

# Option B: Silently drop incoming GRE keepalives (blackhole test) without tearing down the interface
sudo ip netns exec gre1 iptables -I INPUT -i gre1 -p gre -j DROP
sudo ip netns exec gre1 iptables -I FORWARD -i gre1 -p gre -j DROP
# Restore:
sudo ip netns exec gre1 iptables -D INPUT -i gre1 -p gre -j DROP
sudo ip netns exec gre1 iptables -D FORWARD -i gre1 -p gre -j DROP
```
