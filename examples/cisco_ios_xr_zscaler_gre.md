# Cisco IOS-XR (`ASR 9000` / `NCS 540` / `NCS 5500` / `Cisco 8000` / `XRd`) Configurations for the Zscaler 8-Tunnel GRE Lab Simulator

> **Target Platform & Applicability**
> - **Operating System:** **Cisco IOS-XR (64-bit eXR / Linux-based Service Provider & Core WAN OS)**, Release **7.5.x / 7.9.x / 7.11.x / 24.x+**
> - **Supported Hardware & Virtual Appliances:**
>   - **Cisco ASR 9000 Series** (`ASR 9901`, `ASR 9902`, `ASR 9903`, `ASR 9006`, `ASR 9010` — Typhoon / Tomahawk / LightSpeed NPUs)
>   - **Cisco Network Convergence System (NCS) Series** (`NCS 540`, `NCS 560`, `NCS 5500` — Broadcom DNX Jericho+ / Jericho2 / Qumran NPUs)
>   - **Cisco 8000 Series Routers** (`8201`, `8202`, `8800` — Cisco Silicon One)
>   - **Virtual Routers:** Cisco **IOS XRd** (Container / VM) and **IOS XRv 9000** (`XRv9K`)
> - **Management & CLI Mode:** Two-stage transactional CLI (`configure` $\rightarrow$ `commit`) or model-driven NETCONF / gNMI (`Cisco-IOS-XR-*` YANG models).
> - **Looking for another Cisco platform?** See [`examples/README.md`](README.md) for [Catalyst SD-WAN (`cEdge`)](cisco_sdwan_cedge_zscaler_gre.md), [Autonomous IOS-XE](cisco_autonomous_ios_xe_zscaler_gre.md), or [Cisco SD-WAN `vEdge` (Viptela OS)](cisco_sdwan_vedge_zscaler_gre.md).

---

## 0. Core Architectural Principles & Verified Cisco IOS-XR Platform Constraints

### 0.1 Three Non-Negotiable Security & Routing Principles
1. **Zero Manual Route-Leaking:**
   Separation between the **WAN Transport Underlay (`fVRF`: `WAN-VRF-GE1` & `WAN-VRF-GE2`)** and the **Customer Tenant VRFs (`iVRF`: `VRF-TRUSTED` & `VRF-GUEST`)** is handled 100% natively on `interface tunnel-ip` via `vrf <iVRF>` (payload VRF) and `tunnel vrf <fVRF>` (transport VRF).
2. **Strict Security Isolation Between `VRF-TRUSTED` (Production) and `VRF-GUEST`:**
   - **`VRF-TRUSTED` (`10.23.0.0/24`, VLAN 950)** and **`VRF-GUEST` (`172.16.0.0/24`, VLAN 952)** have completely separate RIB/FIB tables and dedicated `tunnel-ip` interfaces (`tunnel-ip1, 2, 11, 12` vs. `tunnel-ip21, 22, 31, 32`).
3. **1-to-1 Mapping to the 8-Tunnel Ubuntu Simulator (`192.168.1.57`):**

| Tunnel # | Tenant VRF (`iVRF`) | Transport VRF (`fVRF`) | Zscaler Cloud & Role | XR Interface | WAN Source $\rightarrow$ Zscaler VIP | Simulator NetNS / Dev | Inner `/30` (XR $\leftrightarrow$ Sim) | Default Route AD |
| :-: | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :-: |
| **1** | **`VRF-TRUSTED`** (`10.23.0.0/24`) | `WAN-VRF-GE1` | `zscaler.net` **Primary** | `tunnel-ip1` | `Gi0/0/0/0 .64 -> 192.168.1.240` | `gre1` / `gre1` | `172.21.12.161 <-> 172.21.12.162` | **AD 10** (Active) |
| **2** | **`VRF-TRUSTED`** (`10.23.0.0/24`) | `WAN-VRF-GE1` | `zscaler.net` **Secondary** | `tunnel-ip2` | `Gi0/0/0/0 .64 -> 192.168.1.241` | `gre2` / `gre2` | `172.21.12.165 <-> 172.21.166` | **AD 20** (Standby 1) |
| **3** | **`VRF-TRUSTED`** (`10.23.0.0/24`) | `WAN-VRF-GE2` | `zscaler.net` **Primary** | `tunnel-ip11` | `Gi0/0/0/1 .65 -> 192.168.1.240` | `gre1` / `gre11` | `172.21.12.153 <-> 172.21.12.154` | **AD 30** (Standby 2) |
| **4** | **`VRF-TRUSTED`** (`10.23.0.0/24`) | `WAN-VRF-GE2` | `zscaler.net` **Secondary** | `tunnel-ip12` | `Gi0/0/0/1 .65 -> 192.168.1.241` | `gre2` / `gre12` | `172.21.12.157 <-> 172.21.12.158` | **AD 40** (Standby 3) |
| **5** | **`VRF-GUEST`** (`172.16.0.0/24`) | `WAN-VRF-GE1` | `zscalerbeta.net` **Primary** | `tunnel-ip21` | `Gi0/0/0/0 .64 -> 192.168.1.242` | `gre1` / `gre21` | `172.20.67.73 <-> 172.20.67.74` | **AD 10** (Active) |
| **6** | **`VRF-GUEST`** (`172.16.0.0/24`) | `WAN-VRF-GE1` | `zscalerbeta.net` **Secondary** | `tunnel-ip22` | `Gi0/0/0/0 .64 -> 192.168.1.243` | `gre2` / `gre22` | `172.20.67.77 <-> 172.20.67.78` | **AD 20** (Standby 1) |
| **7** | **`VRF-GUEST`** (`172.16.0.0/24`) | `WAN-VRF-GE2` | `zscalerbeta.net` **Primary** | `tunnel-ip31` | `Gi0/0/0/1 .65 -> 192.168.1.242` | `gre1` / `gre31` | `172.20.67.65 <-> 172.20.67.66` | **AD 30** (Standby 2) |
| **8** | **`VRF-GUEST`** (`172.16.0.0/24`) | `WAN-VRF-GE2` | `zscalerbeta.net` **Secondary** | `tunnel-ip32` | `Gi0/0/0/1 .65 -> 192.168.1.243` | `gre2` / `gre32` | `172.20.67.69 <-> 172.20.67.70` | **AD 40** (Standby 3) |

---

### 0.2 Verified Cisco IOS-XR Platform Constraints vs. Lab Assumptions (Read First!)

When reviewing this configuration with Cisco IOS-XR specialists, note four **verified IOS-XR architectural differences** compared to IOS-XE:

1. **Verified IOS-XR `ipsla` Constraint — No Native `http raw` / `http get` Probe in XR CLI/YANG:**
   - Unlike Cisco IOS-XE (`Cisco-IOS-XE-sla.yang`), **Cisco IOS-XR's native `ipsla` subsystem (`Cisco-IOS-XR-man-ipsla-cfg.yang`) supports only `icmp echo`, `icmp path-echo`, `icmp path-jitter`, `udp echo`, `udp jitter`, and `mpls lsp` operations**—it does **not** implement an `http` operation type in native XR CLI or YANG.
   - **How IOS-XR Monitors Each Zscaler GRE Tunnel:**
     - **Primary Native XR Method (Section 2):** Configures VRF-aware `ipsla -> operation <id> -> type icmp echo` inside `vrf VRF-TRUSTED` / `vrf VRF-GUEST` sourced from the local `/30` tunnel IP (`172.21.12.161`) to the remote Zscaler ZEN `/30` IP (`172.21.12.162`) every 5 seconds, paired with `track <name> -> type rtr <id> reachability` (`delay down 15`, `delay up 30`). Because the `/30` subnet is directly connected on `tunnel-ip1`, the ICMP echo travels strictly inside `tunnel-ip1`.
     - **Optional L7 HTTP `/vpntest` Method on IOS-XR (Section 3):** Because IOS-XR 7.x / 24.x runs on a 64-bit Linux kernel with native VRF network namespaces (`ip netns exec vrf-VRF-TRUSTED curl ...`) and **IOS-XR Application Manager / Event Manager (EEM)**, we also provide a lightweight XR EEM/Python option if true HTTP `GET /vpntest` status-code verification against `zscaler_orchestrator_pyroute2.py` is desired.
2. **Verified IOS-XR Hardware NPU TCP MSS Adjustment (`tcp-mss-adjust`) Constraint:**
   - Unlike IOS-XE (where `ip tcp adjust-mss 1436` is configured per interface), high-speed IOS-XR line-card NPUs handle TCP MSS clamping differently by hardware family:
     - **Cisco ASR 9000 Series (Typhoon / Tomahawk / LightSpeed NPUs):** Configured in two steps: `ipv4 tcp-mss-adjust enable` under the interface (`tunnel-ip` or LAN sub-interface) **plus** the NPU hardware profile `hw-module location <rack/slot/CPU0> tcp-mss-adjust np <np-id> value 1360`.
     - **Cisco NCS 5500 / NCS 540 Series (Broadcom Jericho+ / Jericho2 DNX NPUs) & XRd:** Broadcom DNX NPUs do **not** rewrite transit TCP SYN MSS options in hardware. On NCS 5500/540, set `mtu 1476` on `interface tunnel-ip<id>` and ensure ICMP Type 3 Code 4 (`Fragmentation Needed`) is permitted so Path MTU Discovery (PMTUD) clamps TCP segments on the endpoints.
3. **Verified IOS-XR `mtu` Accounting Rule (L2 vs. L3 MTU):**
   - On physical Ethernet interfaces (`GigabitEthernet0/0/0/0`), IOS-XR's `mtu` command includes the **14-byte Ethernet header** (`mtu 1514` = 1500-byte IP MTU; on VLAN sub-interfaces `GigabitEthernet0/0/0/2.950`, `mtu 1518` = 1500-byte IP payload + 14B Ethernet + 4B 802.1Q tag).
   - On logical `interface tunnel-ip<id>`, `mtu 1476` sets the Layer-3 IP payload MTU directly (`1500 - 20B Outer IPv4 - 4B GRE = 1476`).
4. **Verified IOS-XR VRF-Aware GRE `keepalive` Constraint (`iVRF != fVRF`):**
   - Just like IOS-XE, when `interface tunnel-ip<id>` uses split VRFs (`vrf VRF-TRUSTED` for inner payload and `tunnel vrf WAN-VRF-GE1` for outer transport, so `iVRF != fVRF`), L3 GRE `keepalive` is omitted and tunnel health is tracked via the 5-second VRF-aware `ipsla` probe.

---

### 0.3 Cisco IOS-XR YANG Data Model & Transactional (`commit`) Compliance

Every configuration block in this guide maps 1-to-1 to Cisco IOS-XR's native YANG data models and is validated atomically when `commit` is executed:

| Architectural Component | Cisco IOS-XR YANG Module (`7.x` / `24.x`) | Canonical YANG Container / XPath |
| :--- | :--- | :--- |
| **Front-Door Transport VRFs (`fVRF`) & Tenant VRFs (`iVRF`)** | `Cisco-IOS-XR-infra-rsi-cfg.yang` | `/vrfs/vrf[vrf-name='WAN-VRF-GE1'\|'WAN-VRF-GE2'\|'VRF-TRUSTED'\|'VRF-GUEST']/afs/af` |
| **Physical Interfaces, 802.1Q Sub-Interfaces & `tunnel-ip` Creation** | `Cisco-IOS-XR-ifmgr-cfg.yang`<br>`Cisco-IOS-XR-l2-eth-infra-cfg.yang`<br>`Cisco-IOS-XR-ipv4-io-cfg.yang` | `/interface-configurations/interface-configuration[interface-name='tunnel-ip1'\|...]`<br>`.../vrf`, `.../mtus/mtu`, `.../ipv4-network/addresses/primary` |
| **GRE Encapsulation, Source/Destination & `tunnel vrf` Binding** | `Cisco-IOS-XR-tunnel-gre-cfg.yang` (augments `Cisco-IOS-XR-ifmgr-cfg`) | `/interface-configurations/interface-configuration/tunnel-ip/mode` (`gre-ipv4`)<br>`.../tunnel-ip/source`, `.../tunnel-ip/destination`, `.../tunnel-ip/vrf` |
| **VRF-Aware IP SLA Operations & Schedules (`ipsla`)** | `Cisco-IOS-XR-man-ipsla-cfg.yang` | `/ipsla/operation/operations/operation[operation-id='1']/operation-type/icmp-echo`<br>`/ipsla/schedule/schedules/schedule[operation-id='1']` |
| **Object Tracking (`track <name> -> type rtr <id> reachability`)** | `Cisco-IOS-XR-manageability-object-tracking-cfg.yang` | `/object-trackings/object-tracking[track-name='TRACK-TUN1']/type-rtr`<br>`.../delay-up`, `.../delay-down` |
| **Tracked Floating Static Default Routes (`router static`)** | `Cisco-IOS-XR-ip-static-cfg.yang` | `/router-static/vrfs/vrf[vrf-name='VRF-TRUSTED'\|'VRF-GUEST']/address-family/vrfipv4/vrf-unicast/vrf-prefixes/vrf-prefix` |

---

## 1. Cisco IOS-XR 8-Tunnel Architecture Diagram

```text
+===================================================================================+
|         CISCO IOS-XR 8-TUNNEL ARCHITECTURE (tunnel-ip + fVRF / iVRF)              |
+===================================================================================+
|                                                                                   |
|   [VRF-TRUSTED (iVRF): 10.23.0.0/24]        [VRF-GUEST (iVRF): 172.16.0.0/24]     |
|    * Gi0/0/0/2.950 (10.23.0.1/24)            * Gi0/0/0/2.952 (172.16.0.1/24)      |
|    * vrf VRF-TRUSTED                         * vrf VRF-GUEST                      |
|    * tunnel-ip1, tunnel-ip2,                 * tunnel-ip21, tunnel-ip22,          |
|      tunnel-ip11, tunnel-ip12                  tunnel-ip31, tunnel-ip32           |
|    * router static vrf VRF-TRUSTED:          * router static vrf VRF-GUEST:       |
|      0.0.0.0/0 tracked (AD 10, 20, 30, 40)     0.0.0.0/0 tracked (AD 10,20,30,40) |
|    * Cloud 1: zscaler.net (.240 / .241)      * Cloud 2: zscalerbeta.net (.242/.243)|
|          |                     \            /                    |                |
|          | tunnel vrf           \          /                     | tunnel vrf     |
|          | WAN-VRF-GE1           \        /                      | WAN-VRF-GE2    |
|          v                        v      v                       v                |
|   +------------------------------------+  +------------------------------------+  |
|   | Front-Door VRF 1: WAN-VRF-GE1      |  | Front-Door VRF 2: WAN-VRF-GE2      |  |
|   |  * Gi0/0/0/0 (192.168.1.64/24)     |  |  * Gi0/0/0/1 (192.168.1.65/24)     |  |
|   |  * Default: 0.0.0.0/0 -> .1.254    |  |  * Default: 0.0.0.0/0 -> .1.254    |  |
|   |  * Carries: tunnel-ip1, 2, 21, 22  |  |  * Carries: tunnel-ip11, 12, 31, 32|  |
|   +------------------------------------+  +------------------------------------+  |
+===================================================================================+
```

---

## 2. Complete Standalone Cisco IOS-XR Configuration (`configure` $\rightarrow$ `commit`)

```cisco
! ===========================================================================
! CISCO IOS-XR (ASR 9000 / NCS 540 / NCS 5500 / Cisco 8000 / XRd / XRv9000)
! Complete 8-Tunnel Dual-Cloud Zscaler GRE Configuration
! ===========================================================================

! 1A. Front-Door WAN Transport VRFs (fVRFs)
vrf WAN-VRF-GE1
 description Front-Door-Transport-VRF-for-WAN1-Gi0/0/0/0
 address-family ipv4 unicast
 !
!
vrf WAN-VRF-GE2
 description Front-Door-Transport-VRF-for-WAN2-Gi0/0/0/1
 address-family ipv4 unicast
 !
!

! 1B. Customer Tenant VRFs (iVRFs) — Strictly isolated
vrf VRF-TRUSTED
 description Trusted-Production-Segment (10.23.0.0/24 -> zscaler.net)
 address-family ipv4 unicast
 !
!
vrf VRF-GUEST
 description Guest-Segment (172.16.0.0/24 -> zscalerbeta.net)
 address-family ipv4 unicast
 !
!

! 2. WAN Underlay Interfaces (in WAN-VRF-GE1 & WAN-VRF-GE2)
interface GigabitEthernet0/0/0/0
 description WAN1-GE1-Underlay
 vrf WAN-VRF-GE1
 ipv4 address 192.168.1.64 255.255.255.0
 no shutdown
!
interface GigabitEthernet0/0/0/1
 description WAN2-GE2-Underlay
 vrf WAN-VRF-GE2
 ipv4 address 192.168.1.65 255.255.255.0
 no shutdown
!

! 3. Service-Side LAN Sub-Interfaces (in VRF-TRUSTED and VRF-GUEST)
interface GigabitEthernet0/0/0/2
 no shutdown
!
interface GigabitEthernet0/0/0/2.950
 description LAN-Trusted-Production
 encapsulation dot1q 950
 vrf VRF-TRUSTED
 ipv4 address 10.23.0.1 255.255.255.0
 no shutdown
!
interface GigabitEthernet0/0/0/2.952
 description LAN-Guest
 encapsulation dot1q 952
 vrf VRF-GUEST
 ipv4 address 172.16.0.1 255.255.255.0
 no shutdown
!

! ===========================================================================
! 4A. 4 GRE TUNNELS IN VRF-TRUSTED (Cloud 1: zscaler.net .240 / .241)
!     - Inner Payload (iVRF): "vrf VRF-TRUSTED"
!     - Outer Header  (fVRF): "tunnel vrf WAN-VRF-GE1" (or WAN-VRF-GE2)
!     - Note on ASR 9000 TCP MSS Clamping:
!       On ASR 9000 hardware, you can optionally uncomment:
!         "ipv4 tcp-mss-adjust enable"
!       and set "hw-module location 0/0/CPU0 tcp-mss-adjust np 0 value 1360".
! ===========================================================================
interface tunnel-ip1
 description VRF-TRUSTED-Primary-GE1 (sim: netns gre1 / dev gre1 / port 7002)
 vrf VRF-TRUSTED
 mtu 1476
 ipv4 address 172.21.12.161 255.255.255.252
 ! ipv4 tcp-mss-adjust enable
 tunnel mode gre ipv4
 tunnel source GigabitEthernet0/0/0/0
 tunnel destination 192.168.1.240
 tunnel vrf WAN-VRF-GE1
 no shutdown
!
interface tunnel-ip2
 description VRF-TRUSTED-Secondary-GE1 (sim: netns gre2 / dev gre2 / port 7003)
 vrf VRF-TRUSTED
 mtu 1476
 ipv4 address 172.21.12.165 255.255.255.252
 ! ipv4 tcp-mss-adjust enable
 tunnel mode gre ipv4
 tunnel source GigabitEthernet0/0/0/0
 tunnel destination 192.168.1.241
 tunnel vrf WAN-VRF-GE1
 no shutdown
!
interface tunnel-ip11
 description VRF-TRUSTED-Primary-GE2 (sim: netns gre1 / dev gre11 / port 7006)
 vrf VRF-TRUSTED
 mtu 1476
 ipv4 address 172.21.12.153 255.255.255.252
 ! ipv4 tcp-mss-adjust enable
 tunnel mode gre ipv4
 tunnel source GigabitEthernet0/0/0/1
 tunnel destination 192.168.1.240
 tunnel vrf WAN-VRF-GE2
 no shutdown
!
interface tunnel-ip12
 description VRF-TRUSTED-Secondary-GE2 (sim: netns gre2 / dev gre12 / port 7007)
 vrf VRF-TRUSTED
 mtu 1476
 ipv4 address 172.21.12.157 255.255.255.252
 ! ipv4 tcp-mss-adjust enable
 tunnel mode gre ipv4
 tunnel source GigabitEthernet0/0/0/1
 tunnel destination 192.168.1.241
 tunnel vrf WAN-VRF-GE2
 no shutdown
!

! ===========================================================================
! 4B. 4 GRE TUNNELS IN VRF-GUEST (Cloud 2: zscalerbeta.net .242 / .243)
!     - Inner Payload (iVRF): "vrf VRF-GUEST"
!     - Outer Header  (fVRF): "tunnel vrf WAN-VRF-GE1" (or WAN-VRF-GE2)
! ===========================================================================
interface tunnel-ip21
 description VRF-GUEST-Primary-GE1 (sim: netns gre1 / dev gre21 / port 7000)
 vrf VRF-GUEST
 mtu 1476
 ipv4 address 172.20.67.73 255.255.255.252
 ! ipv4 tcp-mss-adjust enable
 tunnel mode gre ipv4
 tunnel source GigabitEthernet0/0/0/0
 tunnel destination 192.168.1.242
 tunnel vrf WAN-VRF-GE1
 no shutdown
!
interface tunnel-ip22
 description VRF-GUEST-Secondary-GE1 (sim: netns gre2 / dev gre22 / port 7001)
 vrf VRF-GUEST
 mtu 1476
 ipv4 address 172.20.67.77 255.255.255.252
 ! ipv4 tcp-mss-adjust enable
 tunnel mode gre ipv4
 tunnel source GigabitEthernet0/0/0/0
 tunnel destination 192.168.1.243
 tunnel vrf WAN-VRF-GE1
 no shutdown
!
interface tunnel-ip31
 description VRF-GUEST-Primary-GE2 (sim: netns gre1 / dev gre31 / port 7004)
 vrf VRF-GUEST
 mtu 1476
 ipv4 address 172.20.67.65 255.255.255.252
 ! ipv4 tcp-mss-adjust enable
 tunnel mode gre ipv4
 tunnel source GigabitEthernet0/0/0/1
 tunnel destination 192.168.1.242
 tunnel vrf WAN-VRF-GE2
 no shutdown
!
interface tunnel-ip32
 description VRF-GUEST-Secondary-GE2 (sim: netns gre2 / dev gre32 / port 7005)
 vrf VRF-GUEST
 mtu 1476
 ipv4 address 172.20.67.69 255.255.255.252
 ! ipv4 tcp-mss-adjust enable
 tunnel mode gre ipv4
 tunnel source GigabitEthernet0/0/0/1
 tunnel destination 192.168.1.243
 tunnel vrf WAN-VRF-GE2
 no shutdown
!

! ===========================================================================
! 5. NATIVE IOS-XR VRF-AWARE IP SLA PROBES & OBJECT TRACKING
!    Note: As documented in Section 0.2 #1, native IOS-XR "ipsla"
!    (Cisco-IOS-XR-man-ipsla-cfg) supports ICMP/UDP/MPLS operations (not HTTP).
!    Each probe pings the connected /30 Zscaler ZEN IP inside its GRE tunnel.
! ===========================================================================
ipsla
 ! --- VRF-TRUSTED Probes (Cloud 1: zscaler.net) ---
 operation 1
  type icmp echo
   vrf VRF-TRUSTED
   source address 172.21.12.161
   destination address 172.21.12.162
   timeout 3000
   frequency 5
  !
 !
 operation 2
  type icmp echo
   vrf VRF-TRUSTED
   source address 172.21.12.165
   destination address 172.21.12.166
   timeout 3000
   frequency 5
  !
 !
 operation 11
  type icmp echo
   vrf VRF-TRUSTED
   source address 172.21.12.153
   destination address 172.21.12.154
   timeout 3000
   frequency 5
  !
 !
 operation 12
  type icmp echo
   vrf VRF-TRUSTED
   source address 172.21.12.157
   destination address 172.21.12.158
   timeout 3000
   frequency 5
  !
 !
 ! --- VRF-GUEST Probes (Cloud 2: zscalerbeta.net) ---
 operation 21
  type icmp echo
   vrf VRF-GUEST
   source address 172.20.67.73
   destination address 172.20.67.74
   timeout 3000
   frequency 5
  !
 !
 operation 22
  type icmp echo
   vrf VRF-GUEST
   source address 172.20.67.77
   destination address 172.20.67.78
   timeout 3000
   frequency 5
  !
 !
 operation 31
  type icmp echo
   vrf VRF-GUEST
   source address 172.20.67.65
   destination address 172.20.67.66
   timeout 3000
   frequency 5
  !
 !
 operation 32
  type icmp echo
   vrf VRF-GUEST
   source address 172.20.67.69
   destination address 172.20.67.70
   timeout 3000
   frequency 5
  !
 !
 schedule operation 1
  start-time now
  life forever
 !
 schedule operation 2
  start-time now
  life forever
 !
 schedule operation 11
  start-time now
  life forever
 !
 schedule operation 12
  start-time now
  life forever
 !
 schedule operation 21
  start-time now
  life forever
 !
 schedule operation 22
  start-time now
  life forever
 !
 schedule operation 31
  start-time now
  life forever
 !
 schedule operation 32
  start-time now
  life forever
 !
!

! --- Object Trackers (Cisco-IOS-XR-manageability-object-tracking-cfg) ---
track TRACK-TUN1
 type rtr 1 reachability
 delay up 30
 delay down 15
!
track TRACK-TUN2
 type rtr 2 reachability
 delay up 30
 delay down 15
!
track TRACK-TUN11
 type rtr 11 reachability
 delay up 30
 delay down 15
!
track TRACK-TUN12
 type rtr 12 reachability
 delay up 30
 delay down 15
!
track TRACK-TUN21
 type rtr 21 reachability
 delay up 30
 delay down 15
!
track TRACK-TUN22
 type rtr 22 reachability
 delay up 30
 delay down 15
!
track TRACK-TUN31
 type rtr 31 reachability
 delay up 30
 delay down 15
!
track TRACK-TUN32
 type rtr 32 reachability
 delay up 30
 delay down 15
!

! ===========================================================================
! 6. UNDERLAY & OVERLAY STATIC ROUTING (Cisco-IOS-XR-ip-static-cfg)
!    - Front-Door VRFs: WAN-VRF-GE1 & WAN-VRF-GE2 -> 192.168.1.254
!    - VRF-TRUSTED: 0.0.0.0/0 -> Cloud 1: zscaler.net (AD 10, 20, 30, 40)
!    - VRF-GUEST:   0.0.0.0/0 -> Cloud 2: zscalerbeta.net (AD 10, 20, 30, 40)
! ===========================================================================
router static
 vrf WAN-VRF-GE1
  address-family ipv4 unicast
   0.0.0.0/0 GigabitEthernet0/0/0/0 192.168.1.254
  !
 !
 vrf WAN-VRF-GE2
  address-family ipv4 unicast
   0.0.0.0/0 GigabitEthernet0/0/0/1 192.168.1.254
  !
 !
 vrf VRF-TRUSTED
  address-family ipv4 unicast
   0.0.0.0/0 tunnel-ip1  172.21.12.162 10 track TRACK-TUN1  description ZS-PROD-PRI-GE1
   0.0.0.0/0 tunnel-ip2  172.21.12.166 20 track TRACK-TUN2  description ZS-PROD-SEC-GE1
   0.0.0.0/0 tunnel-ip11 172.21.12.154 30 track TRACK-TUN11 description ZS-PROD-PRI-GE2
   0.0.0.0/0 tunnel-ip12 172.21.12.158 40 track TRACK-TUN12 description ZS-PROD-SEC-GE2
  !
 !
 vrf VRF-GUEST
  address-family ipv4 unicast
   0.0.0.0/0 tunnel-ip21 172.20.67.74  10 track TRACK-TUN21 description ZS-GUEST-PRI-GE1
   0.0.0.0/0 tunnel-ip22 172.20.67.78  20 track TRACK-TUN22 description ZS-GUEST-SEC-GE1
   0.0.0.0/0 tunnel-ip31 172.20.67.66  30 track TRACK-TUN31 description ZS-GUEST-PRI-GE2
   0.0.0.0/0 tunnel-ip32 172.20.67.70  40 track TRACK-TUN32 description ZS-GUEST-SEC-GE2
  !
 !
!
commit
```

---

## 3. Bridging IOS-XR ICMP Tracking with the Layer-7 Python Orchestrator (`zscaler_orchestrator_pyroute2.py`)

Because native IOS-XR `ipsla` sends **ICMP Echo (`ping`)** probes to `172.21.12.162`, etc., whereas `zscaler_orchestrator_pyroute2.py` toggles **Layer-7 HTTP (`/vpntest`)** responses (`200 OK` vs. `503 Service Unavailable`), you have two clean options when testing IOS-XR failover against the simulator:

### Option A: Test Failover Directly from the Ubuntu Simulator via ICMP Drop Rules
To fail over `tunnel-ip1` (`gre1`) on IOS-XR without bringing down the `gre1` link:
```bash
# Block ICMP echo probes on gre1 (triggers IPSLA 1 -> TRACK-TUN1 DOWN in 15s -> fails over to tunnel-ip2 AD 20)
sudo ip netns exec gre1 iptables -I INPUT -i gre1 -p icmp --icmp-type echo-request -j DROP

# Restore tunnel-ip1 (TRACK-TUN1 recovers after delay up 30s):
sudo ip netns exec gre1 iptables -D INPUT -i gre1 -p icmp --icmp-type echo-request -j DROP
```

### Option B: Run True Layer-7 HTTP `/vpntest` Probing from IOS-XR's Native Linux Shell
On 64-bit Cisco IOS-XR (eXR 7.x / 24.x), every XR VRF with `tpm` / Linux network namespace mapping can execute `curl` inside the VRF namespace:
```bash
# From the IOS-XR "run" bash prompt, test L7 HTTP /vpntest over tunnel-ip1 (172.21.12.162:80):
ip netns exec vrf-VRF-TRUSTED curl -s -o /dev/null -w "%{http_code}\n" --interface 172.21.12.161 --max-time 3 -H "Host: gateway.zscaler.net" http://172.21.12.162/vpntest
```

---

## 4. Cisco IOS-XR Verification & Failover Testing Commands

```cisco
! 1. Verify all 8 tunnel-ip interfaces and line-protocol status
show ipv4 interface brief | include tunnel-ip
show interface tunnel-ip1
show interface tunnel-ip21
show tunnel ip ea database tunnel-ip1

! 2. Verify Front-Door Transport VRF routing (WAN-VRF-GE1 & WAN-VRF-GE2)
show route vrf WAN-VRF-GE1
show route vrf WAN-VRF-GE2

! 3. Verify VRF-aware IP SLA operations and Object Trackers
show ipsla statistics
show ipsla statistics 1
show ipsla statistics 21
show track
show track TRACK-TUN1

! 4. Verify active default routes (0.0.0.0/0) per Tenant VRF over BOTH Zscaler clouds
!    - VRF-TRUSTED should show 0.0.0.0/0 via tunnel-ip1 (172.21.12.162, AD 10 -> zscaler.net)
!    - VRF-GUEST   should show 0.0.0.0/0 via tunnel-ip21 (172.20.67.74, AD 10 -> zscalerbeta.net)
show route vrf VRF-TRUSTED 0.0.0.0/0
show route vrf VRF-GUEST 0.0.0.0/0

! 5. Test end-to-end DEFAULT ROUTE (0.0.0.0/0) internet breakout across BOTH Zscaler clouds
ping vrf VRF-TRUSTED 8.8.8.8 source 10.23.0.1
ping vrf VRF-GUEST   8.8.8.8 source 172.16.0.1
traceroute vrf VRF-TRUSTED 1.1.1.1 source 10.23.0.1 numeric
traceroute vrf VRF-GUEST   1.1.1.1 source 172.16.0.1 numeric
```
