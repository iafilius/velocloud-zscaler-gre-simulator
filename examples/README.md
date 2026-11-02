# Cisco Zscaler ZIA 8-Tunnel GRE Reference Configurations (By Cisco Platform)

This directory contains complete, standalone, **YANG-validated** reference configurations for integrating **Cisco routers and SD-WAN appliances** with the **8-Tunnel Dual-Zscaler-Cloud Linux Network Namespace Simulator** ([`../mknetns-gre1.sh`](../mknetns-gre1.sh), [`../doit.sh`](../doit.sh), and [`../zscaler_orchestrator_pyroute2.py`](../zscaler_orchestrator_pyroute2.py)).

To avoid mixing different Cisco operating systems, CLI grammars, or controller models in a single document, each Cisco platform has its own dedicated, self-contained guide.

---

## 1. Select Your Cisco Platform Guide

```text
+======================================================================================+
|               CISCO PLATFORM SELECTOR FOR ZSCALER 8-TUNNEL GRE LABS                  |
+======================================================================================+
|                                                                                      |
|  1. Cisco Catalyst SD-WAN (cEdge — IOS-XE 17.9+ / 17.12+ in Controller Mode)         |
|     -> File: cisco_sdwan_cedge_zscaler_gre.md                                        |
|     * Target Hardware : Catalyst 8200 / 8300 / 8500, Catalyst 8000V (C8000V),        |
|                         ISR 1100 / 4000, ASR 1000 running Controller Mode            |
|     * Management/CLI  : Catalyst SD-WAN Manager (vManage) / "config-transaction"     |
|     * YANG Data Model : Cisco-IOS-XE-native, Cisco-IOS-XE-sdwan, -tunnel, -sla       |
|                                                                                      |
|  2. Classic / Autonomous Cisco IOS-XE (Traditional Non-SD-WAN Routing Mode)          |
|     -> File: cisco_autonomous_ios_xe_zscaler_gre.md                                  |
|     * Target Hardware : Catalyst 8200 / 8300 / 8500, C8000V, ISR 1000 / 4000,        |
|                         ASR 1000, CSR1000v running Autonomous Mode                   |
|     * Management/CLI  : Classic IOS-XE CLI ("configure terminal") / NETCONF          |
|     * YANG Data Model : Cisco-IOS-XE-native, -vrf, -tunnel, -sla, -track, -route-map |
|                                                                                      |
|  3. Cisco IOS-XR (64-Bit Service Provider & Core WAN Edge Operating System)          |
|     -> File: cisco_ios_xr_zscaler_gre.md                                             |
|     * Target Hardware : ASR 9000, NCS 540 / 560 / 5500, Cisco 8000,                  |
|                         IOS XRd / XRv9000 (IOS-XR 7.x / 24.x)                        |
|     * Management/CLI  : IOS-XR Two-Stage Transactional CLI ("configure" -> "commit") |
|     * YANG Data Model : Cisco-IOS-XR-ifmgr-cfg, -tunnel-nve-cfg, -man-ipsla-cfg,     |
|                         -infra-objmgr-cfg, -ip-static-cfg                            |
|                                                                                      |
|  4. Cisco SD-WAN vEdge (Classic Viptela OS 20.x — Legacy / Migration Reference)      |
|     -> File: cisco_sdwan_vedge_zscaler_gre.md                                        |
|     * Target Hardware : vEdge 100 / 1000 / 2000 / 5000, vEdge Cloud                  |
|     * Management/CLI  : Viptela Transactional CLI ("config" -> "commit") / vManage   |
|     * YANG Data Model : viptela-vpn.yang, viptela-system.yang, viptela-policy.yang   |
|                                                                                      |
+======================================================================================+
```

### Detailed Platform Comparison Matrix

| Dimension | [1. Catalyst SD-WAN (`cEdge` IOS-XE)](cisco_sdwan_cedge_zscaler_gre.md) | [2. Autonomous Cisco IOS-XE](cisco_autonomous_ios_xe_zscaler_gre.md) | [3. Cisco IOS-XR (`ASR9K` / `NCS`)](cisco_ios_xr_zscaler_gre.md) | [4. Cisco SD-WAN `vEdge` (Viptela OS)](cisco_sdwan_vedge_zscaler_gre.md) |
| :--- | :--- | :--- | :--- | :--- |
| **Target Hardware & VMs** | Cat 8200/8300/8500, C8000V, ISR 1K/4K, ASR 1K (Controller Mode) | Cat 8200/8300/8500, C8000V, ISR 1K/4K, ASR 1K, CSR1000v (Autonomous Mode) | ASR 9000, NCS 540/560/5500, Cisco 8000, IOS XRd / XRv9000 | vEdge 100/1000/2000/5000, vEdge Cloud *(EoL migration ref)* |
| **CLI Configuration Mode** | `config-transaction` (`commit`) | `configure terminal` | `configure` (`commit`) | `config` (`commit`) |
| **GRE Tunnel Interface Naming** | `interface Tunnel<id>` | `interface Tunnel<id>` | `interface tunnel-ip<id>` | `interface gre<id>` |
| **Dual Zscaler Cloud Support (`zscaler.net` + `zscalerbeta.net`)?** | **Option 1 (`service sig`):** Single global pool (1 Cloud).<br>**Option 2 (Per-VRF GRE):** Full Dual-Cloud (8 tunnels). | **Yes:** Full Dual-Cloud (8 tunnels) via Front-Door VRFs (`tunnel vrf`) or Global (`tunnel route-via`). | **Yes:** Full Dual-Cloud (8 tunnels) via Front-Door VRFs (`tunnel vrf`) + tenant `vrf`. | **Option 1 (`service sig`):** Single global pool.<br>**Option 2 (`ip gre-route`):** Full Dual-Cloud (8 tunnels). |
| **Native L7 `/vpntest` vs. L3 Health Probing** | **Option 1:** `endpoint-tracker` HTTP `/vpntest` (20s) + L3 `keepalive`.<br>**Option 2:** VRF `ip sla http raw` (5s) + `track`. | VRF-aware `ip sla http raw` (`/vpntest`, 5s) + `track <id> ip sla <id> state`. | **Verified XR Constraint:** Native `ipsla` supports ICMP/UDP only (`type icmp echo` to `/30` ZEN IP); optional XR bash/EEM for HTTP. | Viptela `system tracker` (`endpoint-api-url http://.../vpntest` in `vpn 0`). |
| **YANG Schema Family** | `Cisco-IOS-XE-native` + `Cisco-IOS-XE-sdwan` | `Cisco-IOS-XE-native` (`-vrf`, `-tunnel`, `-sla`, `-track`) | `Cisco-IOS-XR-*` (`-ifmgr-cfg`, `-man-ipsla-cfg`, `-ip-static-cfg`) | `viptela-*` (`viptela-vpn`, `viptela-system`, `viptela-policy`) |

---

## 2. Why Cisco Meraki MX & Cisco Secure Firewall (ASA / FTD) Are Not Listed Above

When evaluating the broader Cisco portfolio for Zscaler Internet Access (ZIA) traffic forwarding, two security appliance families intentionally use **IPsec IKEv2** rather than **GRE (`IP Protocol 47`)**:

1. **Cisco Meraki MX Security Appliances:**
   - **Verified Platform Constraint:** Meraki MX appliances do not support terminating unencrypted RFC 2784 GRE tunnels to third-party cloud providers via the Meraki Dashboard. Meraki integrates with Zscaler ZIA exclusively over **Non-Meraki IPsec VPN peers** (IKEv1/IKEv2) or via the **Cisco Meraki SD-WAN / Secure Connect** integration.
2. **Cisco Secure Firewall (ASA & Firepower Threat Defense / FTD):**
   - **Verified Platform Constraint:** Cisco ASA and FTD appliances do not terminate routable Virtual Tunnel Interfaces (VTIs) using unencrypted GREv0 (`IP Protocol 47`) for Zscaler cloud forwarding. Official Zscaler + Cisco ASA/FTD deployment guides use **Route-Based (VTI) or Policy-Based IPsec IKEv2 tunnels** (typically configured with `ESP-NULL` encryption and `SHA` integrity to maximize throughput without crypto overhead).

---

## 3. Common 8-Tunnel Lab Topology & IP Addressing Across All 4 Guides

All 4 Cisco platform guides map 1-to-1 onto the exact IP addresses, VRFs/Segments, **dual-cloud default routes (`0.0.0.0/0`)**, and 8 GRE tunnels of the Ubuntu Network Namespace Simulator (`192.168.1.57`):

| Tunnel # | Segment / VRF (`0.0.0.0/0`) | Zscaler Cloud & Role | Cisco WAN Source $\rightarrow$ Zscaler VIP | Simulator NetNS / Dev | Inner `/30` (Cisco $\leftrightarrow$ Sim) | Orchestrator L7 Port | Default Route AD |
| :-: | :--- | :--- | :--- | :--- | :--- | :-: | :-: |
| **1** | **VPN 10 / `VRF-TRUSTED`** (`10.23.0.0/24`) | `zscaler.net` **Primary** | `GE1 .64 -> 192.168.1.240` | `gre1` / `gre1` | `172.21.12.161 <-> 172.21.12.162` | `.240:7002` | **AD 10** (Active) |
| **2** | **VPN 10 / `VRF-TRUSTED`** (`10.23.0.0/24`) | `zscaler.net` **Secondary** | `GE1 .64 -> 192.168.1.241` | `gre2` / `gre2` | `172.21.12.165 <-> 172.21.12.166` | `.241:7003` | **AD 20** (Standby 1) |
| **3** | **VPN 10 / `VRF-TRUSTED`** (`10.23.0.0/24`) | `zscaler.net` **Primary** | `GE2 .65 -> 192.168.1.240` | `gre1` / `gre11` | `172.21.12.153 <-> 172.21.12.154` | `.240:7006` | **AD 30** (Standby 2) |
| **4** | **VPN 10 / `VRF-TRUSTED`** (`10.23.0.0/24`) | `zscaler.net` **Secondary** | `GE2 .65 -> 192.168.1.241` | `gre2` / `gre12` | `172.21.12.157 <-> 172.21.12.158` | `.241:7007` | **AD 40** (Standby 3) |
| **5** | **VPN 20 / `VRF-GUEST`** (`172.16.0.0/24`) | `zscalerbeta.net` **Primary** | `GE1 .64 -> 192.168.1.242` | `gre1` / `gre21` | `172.20.67.73 <-> 172.20.67.74` | `.242:7000` | **AD 10** (Active) |
| **6** | **VPN 20 / `VRF-GUEST`** (`172.16.0.0/24`) | `zscalerbeta.net` **Secondary** | `GE1 .64 -> 192.168.1.243` | `gre2` / `gre22` | `172.20.67.77 <-> 172.20.67.78` | `.243:7001` | **AD 20** (Standby 1) |
| **7** | **VPN 20 / `VRF-GUEST`** (`172.16.0.0/24`) | `zscalerbeta.net` **Primary** | `GE2 .65 -> 192.168.1.242` | `gre1` / `gre31` | `172.20.67.65 <-> 172.20.67.66` | `.242:7004` | **AD 30** (Standby 2) |
| **8** | **VPN 20 / `VRF-GUEST`** (`172.16.0.0/24`) | `zscalerbeta.net` **Secondary** | `GE2 .65 -> 192.168.1.243` | `gre2` / `gre32` | `172.20.67.69 <-> 172.20.67.70` | `.243:7005` | **AD 40** (Standby 3) |

---

## 4. Common Ubuntu Simulator Preparation for Cisco Testing

In the Delft lab setup ([`../doit.sh`](../doit.sh)), both network namespaces (`gre1` Primary DC and `gre2` Secondary DC) are configured to terminate and NAT actual default-route (`0.0.0.0/0`) internet traffic arriving from **both** segments across **both** Zscaler clouds:

```text
+-----------------------------------------------------------------------------------+
|       END-TO-END DEFAULT ROUTE (0.0.0.0/0) FLOW OVER BOTH ZSCALER CLOUDS          |
+-----------------------------------------------------------------------------------+
|                                                                                   |
|  [VPN 10 Client: 10.23.0.14]               [VPN 20 Client: 172.16.0.14]           |
|       | (Dst: 8.8.8.8)                          | (Dst: 8.8.8.8)                  |
|       v                                         v                                 |
|  +-----------------------------------------------------------------------------+  |
|  | Cisco Router (cEdge / Autonomous IOS-XE / IOS-XR / vEdge)                   |  |
|  |  * VRF 10: 0.0.0.0/0 -> Tunnel1/2/11/12 (zscaler.net:     .240 / .241)      |  |
|  |  * VRF 20: 0.0.0.0/0 -> Tunnel21/22/31/32 (zscalerbeta.net: .242 / .243)    |  |
|  +-----------------------------------------------------------------------------+  |
|       | GRE Encapsulated (Outer: .64/.65 -> .240/.241)                            |
|       |                                         | GRE Encapsulated                |
|       |                                         | (Outer: .64/.65 -> .242/.243)   |
|       v                                         v                                 |
|  +-----------------------------------------------------------------------------+  |
|  | Ubuntu Simulator Host (192.168.1.57 / br1)                                  |  |
|  |  * netns gre1 (Primary DC:   .240 zscaler.net & .242 zscalerbeta.net)       |  |
|  |  * netns gre2 (Secondary DC: .241 zscaler.net & .243 zscalerbeta.net)       |  |
|  |                                                                             |  |
|  |  1. Decapsulates GRE packet on gre1/gre11/gre2/gre12 (Cloud 1)              |  |
|  |     or gre21/gre31/gre22/gre32 (Cloud 2)                                    |  |
|  |  2. Matches default route inside netns (doit.sh lines 56-57):               |  |
|  |       ip -n gre1 route add default via 192.168.1.254                        |  |
|  |       ip -n gre2 route add default via 192.168.1.254                        |  |
|  |  3. Performs Source NAT (MASQUERADE) on veth-b1 / veth-b2 (lines 192-195):  |  |
|  |       iptables -t nat -A POSTROUTING -s 10.23.0.0/24  -j MASQUERADE         |  |
|  |       iptables -t nat -A POSTROUTING -s 172.16.0.0/24 -j MASQUERADE         |  |
|  +-----------------------------------------------------------------------------+  |
|       |                                         ^                                 |
|       | Outbound to Internet                    | Return Route on Upstream Router |
|       v (Src: 192.168.1.240 in gre1 /           | (192.168.1.240/30 via .1.57     |
|               192.168.1.241 in gre2)            |  or direct L2 ARP over br1)     |
|  +-----------------------------------------------------------------------------+  |
|  | Upstream Lab Internet Gateway (192.168.1.254) -> Internet (8.8.8.8)         |  |
|  +-----------------------------------------------------------------------------+  |
+-----------------------------------------------------------------------------------+
```

### Step A: Enable Symmetric `CONNMARK` Return Routing & GRE Keepalive Reflection on All 8 Tunnels
After running `sudo ./mknetns-gre1.sh` and `sudo ./doit.sh` on the Ubuntu simulator host (`192.168.1.57`), run the following snippet so that:
1. `rp_filter=0` and `accept_local=1` are active on all 8 `gre*` interfaces (preventing RPF drops on Cisco L3 GRE keepalives), and
2. Stateful `CONNMARK` policy routing returns internet reply traffic through the exact GRE tunnel (`gre1..gre32`) that the session arrived on:

```bash
# Enable symmetric per-tunnel return routing & GRE keepalive forwarding in netns gre1 (gre1, gre11, gre21, gre31)
sudo ip netns exec gre1 sysctl -w net.ipv4.ip_forward=1 net.ipv4.conf.all.rp_filter=0 net.ipv4.conf.all.accept_local=1 >/dev/null
for pair in "gre1:1" "gre11:11" "gre21:21" "gre31:31"; do
    dev="${pair%%:*}"; mark="${pair##*:}"
    sudo ip netns exec gre1 sysctl -w net.ipv4.conf.${dev}.rp_filter=0 net.ipv4.conf.${dev}.accept_local=1 >/dev/null
    sudo ip netns exec gre1 iptables -t mangle -A PREROUTING -i ${dev} -j CONNMARK --set-mark ${mark}
    sudo ip netns exec gre1 ip rule add fwmark ${mark} table ${mark} 2>/dev/null || true
    sudo ip netns exec gre1 ip route replace 10.23.0.0/24  dev ${dev} table ${mark}
    sudo ip netns exec gre1 ip route replace 172.16.0.0/24 dev ${dev} table ${mark}
done
sudo ip netns exec gre1 iptables -t mangle -A PREROUTING -i veth-b1 -j CONNMARK --restore-mark

# Enable symmetric per-tunnel return routing & GRE keepalive forwarding in netns gre2 (gre2, gre12, gre22, gre32)
sudo ip netns exec gre2 sysctl -w net.ipv4.ip_forward=1 net.ipv4.conf.all.rp_filter=0 net.ipv4.conf.all.accept_local=1 >/dev/null
for pair in "gre2:2" "gre12:12" "gre22:22" "gre32:32"; do
    dev="${pair%%:*}"; mark="${pair##*:}"
    sudo ip netns exec gre2 sysctl -w net.ipv4.conf.${dev}.rp_filter=0 net.ipv4.conf.${dev}.accept_local=1 >/dev/null
    sudo ip netns exec gre2 iptables -t mangle -A PREROUTING -i ${dev} -j CONNMARK --set-mark ${mark}
    sudo ip netns exec gre2 ip rule add fwmark ${mark} table ${mark} 2>/dev/null || true
    sudo ip netns exec gre2 ip route replace 10.23.0.0/24  dev ${dev} table ${mark}
    sudo ip netns exec gre2 ip route replace 172.16.0.0/24 dev ${dev} table ${mark}
done
sudo ip netns exec gre2 iptables -t mangle -A PREROUTING -i veth-b2 -j CONNMARK --restore-mark
```

### Step B: Enable the 8 `iptables` TCP Port `80` `DNAT` Rules for Inside-the-Tunnel HTTP `/vpntest` Probes
Cisco routers send their Layer-7 HTTP `GET /vpntest` probes **inside** the GRE tunnel to **TCP Port `80`** on the connected `/30` Zscaler ZEN IP (`172.21.12.162:80`, etc.). Apply these 8 `DNAT` rules on the Ubuntu host so inside-the-tunnel TCP port `80` probes are steered 1-to-1 to the corresponding `zscaler_orchestrator_pyroute2.py` listener ports (`7000–7007`):

```bash
# In netns gre1 (Primary DC): redirect incoming TCP port 80 probes per GRE tunnel to the matching Orchestrator port
sudo ip netns exec gre1 iptables -t nat -A PREROUTING -i gre1  -p tcp --dport 80 -j DNAT --to-destination 192.168.1.240:7002
sudo ip netns exec gre1 iptables -t nat -A PREROUTING -i gre11 -p tcp --dport 80 -j DNAT --to-destination 192.168.1.240:7006
sudo ip netns exec gre1 iptables -t nat -A PREROUTING -i gre21 -p tcp --dport 80 -j DNAT --to-destination 192.168.1.242:7000
sudo ip netns exec gre1 iptables -t nat -A PREROUTING -i gre31 -p tcp --dport 80 -j DNAT --to-destination 192.168.1.242:7004

# In netns gre2 (Secondary DC): redirect incoming TCP port 80 probes per GRE tunnel to the matching Orchestrator port
sudo ip netns exec gre2 iptables -t nat -A PREROUTING -i gre2  -p tcp --dport 80 -j DNAT --to-destination 192.168.1.241:7003
sudo ip netns exec gre2 iptables -t nat -A PREROUTING -i gre12 -p tcp --dport 80 -j DNAT --to-destination 192.168.1.241:7007
sudo ip netns exec gre2 iptables -t nat -A PREROUTING -i gre22 -p tcp --dport 80 -j DNAT --to-destination 192.168.1.243:7001
sudo ip netns exec gre2 iptables -t nat -A PREROUTING -i gre32 -p tcp --dport 80 -j DNAT --to-destination 192.168.1.243:7005
```
