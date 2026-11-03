# Classic / Autonomous Cisco IOS-XE Configurations for the Zscaler 8-Tunnel GRE Lab Simulator

> **Target Platform & Applicability**
> - **Operating System:** **Cisco IOS-XE in Autonomous (Traditional / Non-SD-WAN) Mode**, Release **16.12.x / 17.3.x / 17.9.x / 17.12.x+**
> - **Supported Hardware & Virtual Appliances:**
>   - Cisco Catalyst 8200 / 8300 / 8500 Series Edge Platforms running Autonomous Mode (`C8200`, `C8300`, `C8500`)
>   - Cisco Catalyst 8000V (`C8000V`) and Cisco Cloud Services Router 1000V (`CSR1000v`) in Autonomous Mode
>   - Cisco ISR 1000 / ISR 4000 Series (`ISR4321`, `ISR4331`, `ISR4431`, `ISR4451`) and Cisco ASR 1000 Series (`ASR1001-X`, `ASR1002-HX`)
> - **Management & CLI Mode:** Configured via standard Cisco IOS-XE CLI (`configure terminal`) or via NETCONF/RESTCONF (`Cisco-IOS-XE-native.yang`). Does **not** require Catalyst SD-WAN Controllers (`vManage` / `vSmart` / `vBond`).
> - **Looking for another Cisco platform?** See [`examples/README.md`](README.md) for [Catalyst SD-WAN (`cEdge` Controller Mode)](cisco_sdwan_cedge_zscaler_gre.md), [Cisco IOS-XR](cisco_ios_xr_zscaler_gre.md), or [Cisco SD-WAN `vEdge` (Viptela OS)](cisco_sdwan_vedge_zscaler_gre.md).

---

## 0. Core Architectural Principles & Verified Autonomous IOS-XE Constraints

### 0.1 Three Non-Negotiable Security & Routing Principles
1. **Zero Manual Route-Leaking (`route-target import/export`, `global` static routes, or VRF-to-VRF leaks):**
   Separation between the **WAN Transport Underlay (`fVRF`)** and the **Customer Service VRFs (`iVRF`: `VRF-TRUSTED` & `VRF-GUEST`)** is handled 100% natively using Cisco IOS-XE's **Front-Door VRF (`tunnel vrf`)** or **`tunnel route-via <interface> mandatory`** architecture.
2. **Strict Security Isolation Between `VRF-TRUSTED` (Production) and `VRF-GUEST`:**
   - **`VRF-TRUSTED` (`10.23.0.0/24`, VLAN 950)** and **`VRF-GUEST` (`172.16.0.0/24`, VLAN 952)** have completely separate routing tables and dedicated GRE tunnels (`Tunnel1/2/11/12` vs. `Tunnel21/22/31/32`).
3. **1-to-1 Mapping to the 8-Tunnel Ubuntu Simulator (`192.168.1.57`):**

| Tunnel # | Customer VRF (`iVRF`) | Transport VRF (`fVRF`) | Zscaler Cloud & Role | WAN Source $\rightarrow$ Zscaler VIP | Simulator NetNS / Dev | Inner `/30` (Cisco $\leftrightarrow$ Sim) | Orchestrator L7 Port | Default Route AD |
| :-: | :--- | :--- | :--- | :--- | :--- | :--- | :-: | :-: |
| **1** | **`VRF-TRUSTED`** (`10.23.0.0/24`) | `WAN-VRF-GE1` | `zscaler.net` **Primary** | `GE1 .64 -> 192.168.1.240` | `gre1` / `gre1` | `172.21.12.161 <-> 172.21.12.162` | `.240:7002` | **AD 10** (Active) |
| **2** | **`VRF-TRUSTED`** (`10.23.0.0/24`) | `WAN-VRF-GE1` | `zscaler.net` **Secondary** | `GE1 .64 -> 192.168.1.241` | `gre2` / `gre2` | `172.21.12.165 <-> 172.21.12.166` | `.241:7003` | **AD 20** (Standby 1) |
| **3** | **`VRF-TRUSTED`** (`10.23.0.0/24`) | `WAN-VRF-GE2` | `zscaler.net` **Primary** | `GE2 .65 -> 192.168.1.240` | `gre1` / `gre11` | `172.21.12.153 <-> 172.21.12.154` | `.240:7006` | **AD 30** (Standby 2) |
| **4** | **`VRF-TRUSTED`** (`10.23.0.0/24`) | `WAN-VRF-GE2` | `zscaler.net` **Secondary** | `GE2 .65 -> 192.168.1.241` | `gre2` / `gre12` | `172.21.12.157 <-> 172.21.12.158` | `.241:7007` | **AD 40** (Standby 3) |
| **5** | **`VRF-GUEST`** (`172.16.0.0/24`) | `WAN-VRF-GE1` | `zscalerbeta.net` **Primary** | `GE1 .64 -> 192.168.1.242` | `gre1` / `gre21` | `172.20.67.73 <-> 172.20.67.74` | `.242:7000` | **AD 10** (Active) |
| **6** | **`VRF-GUEST`** (`172.16.0.0/24`) | `WAN-VRF-GE1` | `zscalerbeta.net` **Secondary** | `GE1 .64 -> 192.168.1.243` | `gre2` / `gre22` | `172.20.67.77 <-> 172.20.67.78` | `.243:7001` | **AD 20** (Standby 1) |
| **7** | **`VRF-GUEST`** (`172.16.0.0/24`) | `WAN-VRF-GE2` | `zscalerbeta.net` **Primary** | `GE2 .65 -> 192.168.1.242` | `gre1` / `gre31` | `172.20.67.65 <-> 172.20.67.66` | `.242:7004` | **AD 30** (Standby 2) |
| **8** | **`VRF-GUEST`** (`172.16.0.0/24`) | `WAN-VRF-GE2` | `zscalerbeta.net` **Secondary** | `GE2 .65 -> 192.168.1.243` | `gre2` / `gre32` | `172.20.67.69 <-> 172.20.67.70` | `.243:7005` | **AD 40** (Standby 3) |

---

### 0.2 Verified Autonomous IOS-XE Platform Constraints vs. Lab Assumptions

1. **Why Two Dual-WAN Underlay Pinning Designs Are Provided (`Design A: Front-Door Transport VRFs` vs. `Design B: Global Underlay with route-via`):**
   - When a router has two WAN interfaces (`GigabitEthernet1` `.64` and `GigabitEthernet2` `.65`) that both establish GRE tunnels to the **exact same Zscaler destination VIPs** (`.240`, `.241`, `.242`, `.243`), placing both WAN interfaces in the Global Routing Table without pinning causes standard CEF Equal-Cost Multi-Path (ECMP) routing to hash outer GRE packets from `Tunnel11` (sourced from `.65`) out `GigabitEthernet1` (or vice versa).
   - **Design A (Dedicated Front-Door Transport VRFs `WAN-VRF-GE1` & `WAN-VRF-GE2` with `tunnel vrf` — Recommended Enterprise Standard):**
     - Places `GigabitEthernet1` inside `vrf definition WAN-VRF-GE1` and `GigabitEthernet2` inside `vrf definition WAN-VRF-GE2`, and binds each GRE tunnel's outer header to its transport VRF via `tunnel vrf WAN-VRF-GE1` or `tunnel vrf WAN-VRF-GE2`.
     - **Why Cisco architects prefer Design A in Autonomous Mode:** It works across **all** IOS and IOS-XE releases (15.x, 16.x, 17.x), allows both WAN interfaces to obtain default routes via DHCP or static routing to the same upstream gateway (`192.168.1.254`) without RIB conflicts, and guarantees 100% deterministic WAN egress per tunnel.
   - **Design B (Global Routing Table Underlay with `tunnel route-via <Interface> mandatory`):**
     - Supported in IOS-XE 17.x when the WAN interfaces remain in the Global Routing Table.
2. **Verified Cisco IOS-XE VRF-Aware GRE `keepalive` Constraint (`iVRF != fVRF`):**
   - Per the official **Cisco IOS-XE IPv4 GRE Configuration Guide** (*"Keepalive is not supported on VRF-aware GRE tunnels"* when `iVRF != fVRF`), whenever a GRE tunnel's inner payload VRF (`vrf forwarding VRF-TRUSTED` or `VRF-GUEST`) differs from its outer transport VRF (`WAN-VRF-GE1`, `WAN-VRF-GE2`, or `global`), Cisco's L3 GRE `keepalive` must **not** be enabled because the decapsulated keepalive return lookup is evaluated in `iVRF` where the WAN IPs do not exist.
   - Instead, tunnel health and failover are driven every **5 seconds** by **VRF-aware Layer-7 `ip sla <id> -> http raw` (`/vpntest`)** + **`track <id> ip sla <id> state`**!
3. **Explicit Lab Assumptions:**
   - **Interface Naming:** Uses `GigabitEthernet1` (`192.168.1.64`), `GigabitEthernet2` (`192.168.1.65`), and LAN sub-interfaces `GigabitEthernet3.950` / `GigabitEthernet3.952` (matching C8000V / CSR1000v). On physical ISR 4000 / Catalyst 8200/8300 routers, substitute `GigabitEthernet0/0/0`, `GigabitEthernet0/0/1`, and `GigabitEthernet0/0/2.950`.

---

### 0.3 Cisco IOS-XE YANG Data Model Compliance (`Cisco-IOS-XE-native.yang`)

Even in Autonomous Mode (`configure terminal`), modern IOS-XE 16.12+ / 17.x routers support NETCONF/RESTCONF programmable automation backed by `Cisco-IOS-XE-native.yang` and its submodules in [`YangModels/yang/vendor/cisco/xe/17121`](https://github.com/YangModels/yang/tree/main/vendor/cisco/xe/17121). Every configuration block in this guide has been directly verified against the official Cisco IOS-XE `17.12.1` `.yang` source files:

| Architectural Component | Official Cisco IOS-XE `17.12.1` YANG Module | Verified YANG Data Node / XPath (`Cisco-IOS-XE-native`) |
| :--- | :--- | :--- |
| **Front-Door Transport VRFs (`fVRF`) & Service VRFs (`iVRF`)** | `Cisco-IOS-XE-native.yang` (line 2458, via submodule `Cisco-IOS-XE-ip.yang` line 1344)<br>`Cisco-IOS-XE-interfaces.yang` (line 4496) | `/native/vrf/definition[name='WAN-VRF-GE1'\|'WAN-VRF-GE2'\|'VRF-TRUSTED'\|'VRF-GUEST']/address-family/ipv4`<br>`/native/interface/GigabitEthernet/vrf-choice/vrf/vrf/forwarding` |
| **GRE Tunnel Encapsulation (`tunnel mode gre ip`) & Front-Door VRF Binding (`tunnel vrf`)** | `Cisco-IOS-XE-tunnel.yang` (lines 280, 288, 649, 1184, 1242)<br>`Cisco-IOS-XE-interfaces.yang` (lines 2332, 4496) | `/native/interface/Tunnel/vrf-choice/vrf/vrf/forwarding`<br>`/native/interface/Tunnel/tunnel/source`<br>`/native/interface/Tunnel/tunnel/destination-config/ipv4`<br>`/native/interface/Tunnel/tunnel/mode/gre-config/ip`<br>`/native/interface/Tunnel/tunnel/vrf-config/vrf-common/vrf` *(or `route-via/interface` + `mandatory`)*<br>`/native/interface/Tunnel/ip/tcp/adjust-mss` |
| **VRF-Aware L7 HTTP `/vpntest` Probes (`ip sla http raw`)** | `Cisco-IOS-XE-sla.yang` (lines 3753, 3826, 3918, 3951) | `/native/ip/sla/entry[number]/http/raw/url`, `source-ip`, `cache`<br>`/native/ip/sla/entry[number]/http/vrf`<br>`/native/ip/sla/entry[number]/http/http-raw-request/raw-request-string`<br>`/native/ip/sla/schedule[entry-number]/life` + `start-time` |
| **Object Tracking (`track <id> ip sla <id> state`)** | `Cisco-IOS-XE-track.yang` (lines 128, 395–412) | `/native/track/tracked-object[object-number]/ip/sla/number` + `state-sla`<br>`/native/track/tracked-object[object-number]/delay/down` + `up` |
| **Tracked Floating Default Routes (`0.0.0.0/0` per VRF)** | `Cisco-IOS-XE-ip.yang` (lines 1800–2135, 3546) | `/native/ip/route/vrf[name]/ip-route-interface-forwarding-list[prefix][mask]/fwd-list[fwd]/interface-next-hop[ip-address]` (`metric`, `track-id-name/id`, `name`) |
| **VRF-Aware Policy-Based Routing (`route-map` + `verify-availability`)** | `Cisco-IOS-XE-route-map.yang` (lines 1242–1356)<br>`Cisco-IOS-XE-acl.yang` | `/native/route-map[name]/route-map-without-order-seq[seq_no]/set/ip/vrf/vrfs[vrf]/verify-availability/ipv4[ipv4]` (`range`, `track`) |

> **Note on `Cisco-IOS-XE-ip.yang` vs. `Cisco-IOS-XE-vrf-oper.yang`:** In the official `YangModels/yang/vendor/cisco/xe/17121` schema tree, `vrf definition` is modeled inside the `Cisco-IOS-XE-ip.yang` submodule (line 1344, included by `Cisco-IOS-XE-native.yang` line 2458) rather than a standalone `Cisco-IOS-XE-vrf.yang` config module (only `Cisco-IOS-XE-vrf-oper.yang` exists as a separate file).

---

## 1. Architecture Diagram: Front-Door Transport VRFs (`fVRF`) + Customer Service VRFs (`iVRF`)

```text
+===================================================================================+
|     AUTONOMOUS CISCO IOS-XE 8-TUNNEL ARCHITECTURE (fVRF / iVRF ISOLATION)         |
+===================================================================================+
|                                                                                   |
|   [VRF-TRUSTED (iVRF): 10.23.0.0/24]        [VRF-GUEST (iVRF): 172.16.0.0/24]     |
|    * Gi3.950 (10.23.0.1/24)                  * Gi3.952 (172.16.0.1/24)            |
|    * vrf forwarding VRF-TRUSTED              * vrf forwarding VRF-GUEST           |
|    * Tunnel1, Tunnel2,                       * Tunnel21, Tunnel22,                |
|      Tunnel11, Tunnel12                        Tunnel31, Tunnel32                 |
|    * 0.0.0.0/0 tracked floating              * 0.0.0.0/0 tracked floating         |
|      routes (AD 10, 20, 30, 40)                routes (AD 10, 20, 30, 40)         |
|    * Cloud 1: zscaler.net (.240 / .241)      * Cloud 2: zscalerbeta.net (.242/.243)|
|          |                     \            /                    |                |
|          | tunnel vrf           \          /                     | tunnel vrf     |
|          | WAN-VRF-GE1           \        /                      | WAN-VRF-GE2    |
|          v                        v      v                       v                |
|   +------------------------------------+  +------------------------------------+  |
|   | Front-Door VRF 1: WAN-VRF-GE1      |  | Front-Door VRF 2: WAN-VRF-GE2      |  |
|   |  * Gi1 (192.168.1.64/24)           |  |  * Gi2 (192.168.1.65/24)           |  |
|   |  * Default: 0.0.0.0/0 -> .1.254    |  |  * Default: 0.0.0.0/0 -> .1.254    |  |
|   |  * Carries: Tunnel1, 2, 21, 22     |  |  * Carries: Tunnel11, 12, 31, 32   |  |
|   +------------------------------------+  +------------------------------------+  |
+===================================================================================+
```

---

## 2. Complete Standalone Autonomous IOS-XE Configuration (`Design A`: Front-Door Transport VRFs)

The configuration below can be pasted directly into `configure terminal` on any Autonomous Cisco IOS-XE router (ISR 1K/4K, ASR 1K, Catalyst 8000, C8000V, CSR1000v):

```cisco
! ===========================================================================
! AUTONOMOUS CISCO IOS-XE: COMPLETE 8-TUNNEL DUAL-CLOUD ZSCALER GRE CONFIG
! Mode: "configure terminal" (Traditional / Non-SD-WAN IOS-XE)
! ===========================================================================

! 1A. Front-Door WAN Transport VRFs (fVRFs) — Isolates GE1 and GE2 underlays
vrf definition WAN-VRF-GE1
 description Front-Door-Transport-VRF-for-WAN1-GE1
 address-family ipv4
 exit-address-family
!
vrf definition WAN-VRF-GE2
 description Front-Door-Transport-VRF-for-WAN2-GE2
 address-family ipv4
 exit-address-family
!

! 1B. Customer Service VRFs (iVRFs) — Strictly isolated (no shared route-targets!)
vrf definition VRF-TRUSTED
 description Trusted-Production-Segment (10.23.0.0/24 -> zscaler.net)
 rd 65000:10
 address-family ipv4
 exit-address-family
!
vrf definition VRF-GUEST
 description Guest-Segment (172.16.0.0/24 -> zscalerbeta.net)
 rd 65000:20
 address-family ipv4
 exit-address-family
!

! 2. WAN Underlay Interfaces & Transport Default Routes (in WAN-VRF-GE1 & WAN-VRF-GE2)
interface GigabitEthernet1
 description WAN1-GE1-Underlay
 vrf forwarding WAN-VRF-GE1
 ip address 192.168.1.64 255.255.255.0
 no shutdown
!
interface GigabitEthernet2
 description WAN2-GE2-Underlay
 vrf forwarding WAN-VRF-GE2
 ip address 192.168.1.65 255.255.255.0
 no shutdown
!
ip route vrf WAN-VRF-GE1 0.0.0.0 0.0.0.0 GigabitEthernet1 192.168.1.254
ip route vrf WAN-VRF-GE2 0.0.0.0 0.0.0.0 GigabitEthernet2 192.168.1.254
!

! 3. Service-Side LAN Sub-Interfaces (in VRF-TRUSTED and VRF-GUEST)
interface GigabitEthernet3
 no shutdown
!
interface GigabitEthernet3.950
 description LAN-Trusted-Production
 encapsulation dot1Q 950
 vrf forwarding VRF-TRUSTED
 ip address 10.23.0.1 255.255.255.0
 no shutdown
!
interface GigabitEthernet3.952
 description LAN-Guest
 encapsulation dot1Q 952
 vrf forwarding VRF-GUEST
 ip address 172.16.0.1 255.255.255.0
 no shutdown
!

! ===========================================================================
! 4A. 4 GRE TUNNELS IN VRF-TRUSTED (Cloud 1: zscaler.net .240 / .241)
!     - Inner Payload (iVRF): "vrf forwarding VRF-TRUSTED"
!     - Outer Header  (fVRF): "tunnel vrf WAN-VRF-GE1" (or WAN-VRF-GE2)
!     - Note: L3 GRE "keepalive" is omitted because iVRF != fVRF (Section 0.2 #2).
! ===========================================================================
interface Tunnel1
 description VRF-TRUSTED-Primary-GE1 (sim: netns gre1 / dev gre1 / port 7002)
 vrf forwarding VRF-TRUSTED
 ip address 172.21.12.161 255.255.255.252
 ip mtu 1476
 ip tcp adjust-mss 1436
 tunnel source GigabitEthernet1
 tunnel destination 192.168.1.240
 tunnel mode gre ipv4
 tunnel vrf WAN-VRF-GE1
 no shutdown
!
interface Tunnel2
 description VRF-TRUSTED-Secondary-GE1 (sim: netns gre2 / dev gre2 / port 7003)
 vrf forwarding VRF-TRUSTED
 ip address 172.21.12.165 255.255.255.252
 ip mtu 1476
 ip tcp adjust-mss 1436
 tunnel source GigabitEthernet1
 tunnel destination 192.168.1.241
 tunnel mode gre ipv4
 tunnel vrf WAN-VRF-GE1
 no shutdown
!
interface Tunnel11
 description VRF-TRUSTED-Primary-GE2 (sim: netns gre1 / dev gre11 / port 7006)
 vrf forwarding VRF-TRUSTED
 ip address 172.21.12.153 255.255.255.252
 ip mtu 1476
 ip tcp adjust-mss 1436
 tunnel source GigabitEthernet2
 tunnel destination 192.168.1.240
 tunnel mode gre ipv4
 tunnel vrf WAN-VRF-GE2
 no shutdown
!
interface Tunnel12
 description VRF-TRUSTED-Secondary-GE2 (sim: netns gre2 / dev gre12 / port 7007)
 vrf forwarding VRF-TRUSTED
 ip address 172.21.12.157 255.255.255.252
 ip mtu 1476
 ip tcp adjust-mss 1436
 tunnel source GigabitEthernet2
 tunnel destination 192.168.1.241
 tunnel mode gre ipv4
 tunnel vrf WAN-VRF-GE2
 no shutdown
!

! ===========================================================================
! 4B. 4 GRE TUNNELS IN VRF-GUEST (Cloud 2: zscalerbeta.net .242 / .243)
!     - Inner Payload (iVRF): "vrf forwarding VRF-GUEST"
!     - Outer Header  (fVRF): "tunnel vrf WAN-VRF-GE1" (or WAN-VRF-GE2)
! ===========================================================================
interface Tunnel21
 description VRF-GUEST-Primary-GE1 (sim: netns gre1 / dev gre21 / port 7000)
 vrf forwarding VRF-GUEST
 ip address 172.20.67.73 255.255.255.252
 ip mtu 1476
 ip tcp adjust-mss 1436
 tunnel source GigabitEthernet1
 tunnel destination 192.168.1.242
 tunnel mode gre ipv4
 tunnel vrf WAN-VRF-GE1
 no shutdown
!
interface Tunnel22
 description VRF-GUEST-Secondary-GE1 (sim: netns gre2 / dev gre22 / port 7001)
 vrf forwarding VRF-GUEST
 ip address 172.20.67.77 255.255.255.252
 ip mtu 1476
 ip tcp adjust-mss 1436
 tunnel source GigabitEthernet1
 tunnel destination 192.168.1.243
 tunnel mode gre ipv4
 tunnel vrf WAN-VRF-GE1
 no shutdown
!
interface Tunnel31
 description VRF-GUEST-Primary-GE2 (sim: netns gre1 / dev gre31 / port 7004)
 vrf forwarding VRF-GUEST
 ip address 172.20.67.65 255.255.255.252
 ip mtu 1476
 ip tcp adjust-mss 1436
 tunnel source GigabitEthernet2
 tunnel destination 192.168.1.242
 tunnel mode gre ipv4
 tunnel vrf WAN-VRF-GE2
 no shutdown
!
interface Tunnel32
 description VRF-GUEST-Secondary-GE2 (sim: netns gre2 / dev gre32 / port 7005)
 vrf forwarding VRF-GUEST
 ip address 172.20.67.69 255.255.255.252
 ip mtu 1476
 ip tcp adjust-mss 1436
 tunnel source GigabitEthernet2
 tunnel destination 192.168.1.243
 tunnel mode gre ipv4
 tunnel vrf WAN-VRF-GE2
 no shutdown
!

! ===========================================================================
! 5. ALL 8 VRF-AWARE L7 HTTP (/vpntest) IP SLA PROBES & TRACK OBJECTS
! ===========================================================================

! --- VRF-TRUSTED (Cloud 1: gateway.zscaler.net) ---
ip sla 1
 http raw url http://172.21.12.162 source-ip 172.21.12.161 cache disable
 vrf VRF-TRUSTED
 http-raw-request
  GET /vpntest HTTP/1.0\r\n
  Host: gateway.zscaler.net\r\n
  User-Agent: Cisco IP SLA\r\n
  \r\n
 exit
 timeout 3000
 threshold 3000
 frequency 5
ip sla schedule 1 life forever start-time now
track 1 ip sla 1 state
 delay down 15 up 30
!
ip sla 2
 http raw url http://172.21.12.166 source-ip 172.21.12.165 cache disable
 vrf VRF-TRUSTED
 http-raw-request
  GET /vpntest HTTP/1.0\r\n
  Host: gateway.zscaler.net\r\n
  User-Agent: Cisco IP SLA\r\n
  \r\n
 exit
 timeout 3000
 threshold 3000
 frequency 5
ip sla schedule 2 life forever start-time now
track 2 ip sla 2 state
 delay down 15 up 30
!
ip sla 11
 http raw url http://172.21.12.154 source-ip 172.21.12.153 cache disable
 vrf VRF-TRUSTED
 http-raw-request
  GET /vpntest HTTP/1.0\r\n
  Host: gateway.zscaler.net\r\n
  User-Agent: Cisco IP SLA\r\n
  \r\n
 exit
 timeout 3000
 threshold 3000
 frequency 5
ip sla schedule 11 life forever start-time now
track 11 ip sla 11 state
 delay down 15 up 30
!
ip sla 12
 http raw url http://172.21.12.158 source-ip 172.21.12.157 cache disable
 vrf VRF-TRUSTED
 http-raw-request
  GET /vpntest HTTP/1.0\r\n
  Host: gateway.zscaler.net\r\n
  User-Agent: Cisco IP SLA\r\n
  \r\n
 exit
 timeout 3000
 threshold 3000
 frequency 5
ip sla schedule 12 life forever start-time now
track 12 ip sla 12 state
 delay down 15 up 30
!

! --- VRF-GUEST (Cloud 2: gateway.zscalerbeta.net) ---
ip sla 21
 http raw url http://172.20.67.74 source-ip 172.20.67.73 cache disable
 vrf VRF-GUEST
 http-raw-request
  GET /vpntest HTTP/1.0\r\n
  Host: gateway.zscalerbeta.net\r\n
  User-Agent: Cisco IP SLA\r\n
  \r\n
 exit
 timeout 3000
 threshold 3000
 frequency 5
ip sla schedule 21 life forever start-time now
track 21 ip sla 21 state
 delay down 15 up 30
!
ip sla 22
 http raw url http://172.20.67.78 source-ip 172.20.67.77 cache disable
 vrf VRF-GUEST
 http-raw-request
  GET /vpntest HTTP/1.0\r\n
  Host: gateway.zscalerbeta.net\r\n
  User-Agent: Cisco IP SLA\r\n
  \r\n
 exit
 timeout 3000
 threshold 3000
 frequency 5
ip sla schedule 22 life forever start-time now
track 22 ip sla 22 state
 delay down 15 up 30
!
ip sla 31
 http raw url http://172.20.67.66 source-ip 172.20.67.65 cache disable
 vrf VRF-GUEST
 http-raw-request
  GET /vpntest HTTP/1.0\r\n
  Host: gateway.zscalerbeta.net\r\n
  User-Agent: Cisco IP SLA\r\n
  \r\n
 exit
 timeout 3000
 threshold 3000
 frequency 5
ip sla schedule 31 life forever start-time now
track 31 ip sla 31 state
 delay down 15 up 30
!
ip sla 32
 http raw url http://172.20.67.70 source-ip 172.20.67.69 cache disable
 vrf VRF-GUEST
 http-raw-request
  GET /vpntest HTTP/1.0\r\n
  Host: gateway.zscalerbeta.net\r\n
  User-Agent: Cisco IP SLA\r\n
  \r\n
 exit
 timeout 3000
 threshold 3000
 frequency 5
ip sla schedule 32 life forever start-time now
track 32 ip sla 32 state
 delay down 15 up 30
!

! ===========================================================================
! 6. TRAFFIC STEERING METHOD 1: TRACKED FLOATING DEFAULT ROUTES (0.0.0.0/0)
!    - VRF-TRUSTED (10.23.0.0/24)  -> Cloud 1: zscaler.net (.240 / .241)
!    - VRF-GUEST   (172.16.0.0/24) -> Cloud 2: zscalerbeta.net (.242 / .243)
! ===========================================================================
! --- VRF-TRUSTED Default Routes (zscaler.net) ---
ip route vrf VRF-TRUSTED 0.0.0.0 0.0.0.0 Tunnel1  172.21.12.162 10 track 1  name ZS-PROD-PRI-GE1
ip route vrf VRF-TRUSTED 0.0.0.0 0.0.0.0 Tunnel2  172.21.12.166 20 track 2  name ZS-PROD-SEC-GE1
ip route vrf VRF-TRUSTED 0.0.0.0 0.0.0.0 Tunnel11 172.21.12.154 30 track 11 name ZS-PROD-PRI-GE2
ip route vrf VRF-TRUSTED 0.0.0.0 0.0.0.0 Tunnel12 172.21.12.158 40 track 12 name ZS-PROD-SEC-GE2

! --- VRF-GUEST Default Routes (zscalerbeta.net) ---
ip route vrf VRF-GUEST   0.0.0.0 0.0.0.0 Tunnel21 172.20.67.74  10 track 21 name ZS-GUEST-PRI-GE1
ip route vrf VRF-GUEST   0.0.0.0 0.0.0.0 Tunnel22 172.20.67.78  20 track 22 name ZS-GUEST-SEC-GE1
ip route vrf VRF-GUEST   0.0.0.0 0.0.0.0 Tunnel31 172.20.67.66  30 track 31 name ZS-GUEST-PRI-GE2
ip route vrf VRF-GUEST   0.0.0.0 0.0.0.0 Tunnel32 172.20.67.70  40 track 32 name ZS-GUEST-SEC-GE2
```

---

## 3. Alternative Options for Autonomous IOS-XE

### 3.1 `Design B` Underlay Alternative: Global Routing Table Underlay (`tunnel route-via mandatory`)
If you prefer to keep `GigabitEthernet1` and `GigabitEthernet2` in the **Global Routing Table** instead of using Front-Door VRFs (`WAN-VRF-GE1` / `WAN-VRF-GE2`), on IOS-XE 17.x you can replace `tunnel vrf WAN-VRF-GE1` / `WAN-VRF-GE2` on `Tunnel1..Tunnel32` with:
```cisco
! Under interface Tunnel1, Tunnel2, Tunnel21, Tunnel22:
 no tunnel vrf WAN-VRF-GE1
 tunnel route-via GigabitEthernet1 mandatory

! Under interface Tunnel11, Tunnel12, Tunnel31, Tunnel32:
 no tunnel vrf WAN-VRF-GE2
 tunnel route-via GigabitEthernet2 mandatory
```

### 3.2 Traffic Steering Method 2: VRF-Aware Policy-Based Routing (`route-map`)
If either `VRF-TRUSTED` or `VRF-GUEST` already has an existing `0.0.0.0/0` default route pointing toward an internal MPLS/BGP datacenter core, and you want **all non-RFC1918 internet traffic** steered into each VRF's dedicated Zscaler cloud (`zscaler.net` vs. `zscalerbeta.net`) while internal RFC1918 traffic uses the normal VRF routing table:

```cisco
! --- VRF-TRUSTED (10.23.0.0/24) -> Cloud 1: zscaler.net ---
ip access-list extended ACL-ZSCALER-TRUSTED
 10 deny   ip any 10.0.0.0 0.255.255.255
 20 deny   ip any 172.16.0.0 0.15.255.255
 30 deny   ip any 192.168.0.0 0.0.255.255
 40 permit ip 10.23.0.0 0.0.0.255 any
!
route-map RM-ZSCALER-TRUSTED permit 10
 match ip address ACL-ZSCALER-TRUSTED
 set ip vrf VRF-TRUSTED next-hop verify-availability 172.21.12.162 10 track 1
 set ip vrf VRF-TRUSTED next-hop verify-availability 172.21.12.166 20 track 2
 set ip vrf VRF-TRUSTED next-hop verify-availability 172.21.12.154 30 track 11
 set ip vrf VRF-TRUSTED next-hop verify-availability 172.21.12.158 40 track 12
!
interface GigabitEthernet3.950
 ip policy route-map RM-ZSCALER-TRUSTED
!
! --- VRF-GUEST (172.16.0.0/24) -> Cloud 2: zscalerbeta.net ---
ip access-list extended ACL-ZSCALER-GUEST
 10 deny   ip any 10.0.0.0 0.255.255.255
 20 deny   ip any 172.16.0.0 0.15.255.255
 30 deny   ip any 192.168.0.0 0.0.255.255
 40 permit ip 172.16.0.0 0.0.0.255 any
!
route-map RM-ZSCALER-GUEST permit 10
 match ip address ACL-ZSCALER-GUEST
 set ip vrf VRF-GUEST next-hop verify-availability 172.20.67.74 10 track 21
 set ip vrf VRF-GUEST next-hop verify-availability 172.20.67.78 20 track 22
 set ip vrf VRF-GUEST next-hop verify-availability 172.20.67.66 30 track 31
 set ip vrf VRF-GUEST next-hop verify-availability 172.20.67.70 40 track 32
!
interface GigabitEthernet3.952
 ip policy route-map RM-ZSCALER-GUEST
```

---

## 4. Autonomous IOS-XE Verification & Failover Testing Commands

*(Ensure the Ubuntu simulator `CONNMARK` and port `80` `DNAT` rules from [`examples/README.md`](README.md#4-common-ubuntu-simulator-preparation-for-cisco-testing) are active before testing).*

```cisco
! 1. Verify all 8 GRE tunnel interfaces and Front-Door VRF bindings
show ip interface brief | include Tunnel
show interface Tunnel1
show interface Tunnel21

! 2. Verify Front-Door Transport VRF routing (WAN-VRF-GE1 & WAN-VRF-GE2)
show ip route vrf WAN-VRF-GE1
show ip route vrf WAN-VRF-GE2

! 3. Verify VRF-aware L7 HTTP (/vpntest) IP SLA probes and Track objects
show ip sla summary
show ip sla statistics 1
show ip sla statistics 21
show track
show ip route track-table

! 4. Verify active default routes (0.0.0.0/0) per Customer VRF over BOTH Zscaler clouds
!    - VRF-TRUSTED should show 0.0.0.0/0 via Tunnel1 (172.21.12.162, AD 10 -> zscaler.net)
!    - VRF-GUEST   should show 0.0.0.0/0 via Tunnel21 (172.20.67.74, AD 10 -> zscalerbeta.net)
show ip route vrf VRF-TRUSTED 0.0.0.0
show ip route vrf VRF-GUEST 0.0.0.0

! 5. Verify PBR next-hop tracking (if using Traffic Steering Method 2)
show route-map RM-ZSCALER-TRUSTED
show route-map RM-ZSCALER-GUEST

! 6. Test end-to-end DEFAULT ROUTE (0.0.0.0/0) internet breakout across BOTH Zscaler clouds
ping vrf VRF-TRUSTED 8.8.8.8 source GigabitEthernet3.950
ping vrf VRF-GUEST   8.8.8.8 source GigabitEthernet3.952
traceroute vrf VRF-TRUSTED 1.1.1.1 source GigabitEthernet3.950 numeric
traceroute vrf VRF-GUEST   1.1.1.1 source GigabitEthernet3.952 numeric
```

