# Cisco SD-WAN `vEdge` (Classic Viptela OS 20.x) Configurations for the Zscaler 8-Tunnel GRE Lab Simulator

> **Target Platform & Applicability**
> - **Operating System:** **Classic Viptela OS (`vEdge`)**, Release **20.3.x / 20.6.x / 20.9.x / 20.12.x**
> - **Supported Hardware & Virtual Appliances:**
>   - Cisco `vEdge 100` (`100b`, `100m`, `100wm`), `vEdge 1000`, `vEdge 2000`, `vEdge 5000`
>   - Cisco **`vEdge Cloud`** Virtual Router (KVM / ESXi / AWS / Azure)
> - **Lifecycle Note:** Classic Viptela OS (`vEdge`) hardware and `vEdge Cloud` are in End-of-Life (EoL) migration toward **Cisco Catalyst SD-WAN (`cEdge` IOS-XE)** (see [`cisco_sdwan_cedge_zscaler_gre.md`](cisco_sdwan_cedge_zscaler_gre.md)). This guide is provided for existing `vEdge` production estates and lab environments running `vEdge Cloud` images.
> - **Management & CLI Mode:** Two-stage transactional Viptela CLI (`config` $\rightarrow$ `commit`) or **Cisco SD-WAN Manager (`vManage`)** (`viptela-vpn.yang`, `viptela-system.yang`, `viptela-policy.yang`).

---

## 0. Core Architectural Principles & Verified `vEdge` (Viptela OS) Platform Constraints

### 0.1 Three Non-Negotiable Security & Routing Principles
1. **Zero Manual Route-Leaking:**
   Separation between **Transport VPN `0`** and **Service VPNs `10` (`Trusted`) & `20` (`Guest`)** is handled 100% natively via Viptela's **`ip service-route ... vpn 0 service sig`** (Option 1) or **`ip gre-route 0.0.0.0/0 vpn 0 interface gre<id>`** (Option 2).
2. **Strict Security Isolation Between `VPN 10` (`Trusted`) and `VPN 20` (`Guest`):**
   - **Service VPN `10` (`10.23.0.0/24`, VLAN 950)** and **Service VPN `20` (`172.16.0.0/24`, VLAN 952)** are completely isolated VRFs/VPNs on the `vEdge`.
3. **1-to-1 Mapping to the 8-Tunnel Ubuntu Simulator (`192.168.1.57`):**

| Tunnel # | Service VPN (`0.0.0.0/0`) | Zscaler Cloud & Role | `vEdge` Interface (`vpn 0`) | WAN Source $\rightarrow$ Zscaler VIP | Simulator NetNS / Dev | Inner `/30` (`vEdge` $\leftrightarrow$ Sim) | Orchestrator L7 Port | Failover Order |
| :-: | :--- | :--- | :--- | :--- | :--- | :--- | :-: | :-: |
| **1** | **VPN 10** (`10.23.0.0/24`) | `zscaler.net` **Primary** | `gre1` | `ge0/0 .64 -> 192.168.1.240` | `gre1` / `gre1` | `172.21.12.161 <-> 172.21.12.162` | `.240:7002` | **1st** (Active) |
| **2** | **VPN 10** (`10.23.0.0/24`) | `zscaler.net` **Secondary** | `gre2` | `ge0/0 .64 -> 192.168.1.241` | `gre2` / `gre2` | `172.21.12.165 <-> 172.21.12.166` | `.241:7003` | **2nd** (Standby 1) |
| **3** | **VPN 10** (`10.23.0.0/24`) | `zscaler.net` **Primary** | `gre11` | `ge0/1 .65 -> 192.168.1.240` | `gre1` / `gre11` | `172.21.12.153 <-> 172.21.12.154` | `.240:7006` | **3rd** (Standby 2) |
| **4** | **VPN 10** (`10.23.0.0/24`) | `zscaler.net` **Secondary** | `gre12` | `ge0/1 .65 -> 192.168.1.241` | `gre2` / `gre12` | `172.21.12.157 <-> 172.21.12.158` | `.241:7007` | **4th** (Standby 3) |
| **5** | **VPN 20** (`172.16.0.0/24`) | `zscalerbeta.net` **Primary** | `gre21` | `ge0/0 .64 -> 192.168.1.242` | `gre1` / `gre21` | `172.20.67.73 <-> 172.20.67.74` | `.242:7000` | **1st** (Active) |
| **6** | **VPN 20** (`172.16.0.0/24`) | `zscalerbeta.net` **Secondary** | `gre22` | `ge0/0 .64 -> 192.168.1.243` | `gre2` / `gre22` | `172.20.67.77 <-> 172.20.67.78` | `.243:7001` | **2nd** (Standby 1) |
| **7** | **VPN 20** (`172.16.0.0/24`) | `zscalerbeta.net` **Primary** | `gre31` | `ge0/1 .65 -> 192.168.1.242` | `gre1` / `gre31` | `172.20.67.65 <-> 172.20.67.66` | `.242:7004` | **3rd** (Standby 2) |
| **8** | **VPN 20** (`172.16.0.0/24`) | `zscalerbeta.net` **Secondary** | `gre32` | `ge0/1 .65 -> 192.168.1.243` | `gre2` / `gre32` | `172.20.67.69 <-> 172.20.67.70` | `.243:7005` | **4th** (Standby 3) |

---

### 0.2 Verified `vEdge` (Viptela OS) Platform Constraints vs. Lab Assumptions

1. **Key Architectural Advantage of `vEdge` `ip gre-route` (`Option 2`) vs. `cEdge`:**
   - Unlike IOS-XE `cEdge` (where routing different Service VPNs to different GRE tunnel pools requires placing the GRE interfaces directly inside `vrf forwarding 10/20`), on **Viptela `vEdge` OS**, all 8 `interface gre<id>` tunnels reside in **Transport `vpn 0`** (`iVRF == fVRF == vpn 0`), and each Service VPN (`vpn 10` vs. `vpn 20`) can explicitly list **which specific `vpn 0` GRE tunnels** its `0.0.0.0/0` route uses via:
     - `vpn 10` $\rightarrow$ `ip gre-route 0.0.0.0/0 vpn 0 interface gre1 gre2 gre11 gre12` (**Cloud 1: `zscaler.net`**)
     - `vpn 20` $\rightarrow$ `ip gre-route 0.0.0.0/0 vpn 0 interface gre21 gre22 gre31 gre32` (**Cloud 2: `zscalerbeta.net`**)
   - Because all 8 `interface gre<id>` interfaces live in `vpn 0` on `vEdge`, **both** L3 GRE `keepalive 5 3` **and** Viptela's native L7 HTTP `system -> tracker` (`endpoint-api-url http://172.21.12.162/vpntest`, etc.) are supported simultaneously on all 8 tunnels!
2. **Verified `vEdge` Interface Numbering & Ordering Constraints:**
   - On Viptela `vEdge` OS (`viptela-vpn.yang`), GRE interfaces are named `gre1..gre255`.
   - Under `ip gre-route 0.0.0.0/0 vpn 0 interface <gre-list>`, Viptela OS evaluates the listed GRE interfaces in **strict Active/Standby priority order**: the first listed interface (`gre1` / `gre21`) is Active, the second (`gre2` / `gre22`) is Standby 1, etc. (Note: Depending on the exact `vEdge` 19.x / 20.x software release, `ip gre-route` accepts up to 2 or 4 space-separated `gre` interfaces; if your specific `vEdge` image caps `ip gre-route` at 2 interfaces per statement, specify the primary pair `gre1 gre2` or use `vSmart` data policy `set local-tloc-list` / `service sig`).
3. **Verified `vEdge` Tracker Timer Constraint:**
   - Under `system -> tracker <name>`, `endpoint-api-url` requires a minimum `interval` of **20 seconds** (`range 20..600`) when probing an HTTP URL (`http://172.21.12.162/vpntest`).

---

### 0.3 Viptela OS YANG Data Model & Transactional (`commit`) Compliance

On `vEdge` routers, the onboard ConfD engine validates all configuration statements against Viptela's native on-box YANG data models (`viptela-system.yang` under namespace `http://viptela.com/system` and `viptela-vpn.yang` under namespace `http://viptela.com/vpn`, shipped inside the Viptela OS / vManage YANG schema bundle):

| Architectural Component | On-Box Viptela OS YANG Module (`20.x`) | Canonical YANG Container / XPath |
| :--- | :--- | :--- |
| **System L7 `/vpntest` Trackers (`system -> tracker`)** | `viptela-system.yang` (`http://viptela.com/system`) | `/system/tracker[name='ZS-TRACK-TUN1']/endpoint-api-url`<br>`.../interval`, `.../threshold`, `.../multiplier`, `.../tracker-type` |
| **Transport VPN 0, WAN Interfaces (`ge0/0`, `ge0/1`) & GRE Tunnels (`gre1..32`)** | `viptela-vpn.yang` (`http://viptela.com/vpn`) | `/vpn/vpn-instance[vpn-id='0']/interface[if-name='gre1']`<br>`.../tunnel-source-interface`, `.../tunnel-destination`, `.../tracker`, `.../keepalive`, `.../clear-dont-fragment` |
| **Transport VPN 0 Native `service sig` (`Option 1`)** | `viptela-vpn.yang` (`http://viptela.com/vpn`) | `/vpn/vpn-instance[vpn-id='0']/service[svc-type='sig']/ha-pairs/interface-pair` |
| **Service VPNs (`vpn 10` & `vpn 20`), `ip service-route` & `ip gre-route`** | `viptela-vpn.yang` (`http://viptela.com/vpn`) | `/vpn/vpn-instance[vpn-id='10'\|'20']/ip/service-route`<br>`/vpn/vpn-instance[vpn-id='10'\|'20']/ip/gre-route` |

---

## 1. `vEdge` Option 1: Native `service sig` in `vpn 0` (Single Global SIG Pool)

Use **`vEdge` Option 1** when both `vpn 10` (`10.23.0.0/24`) and `vpn 20` (`172.16.0.0/24`) share the same Zscaler Cloud (`zscaler.net`, `.240/.241`) and Zscaler enforces per-VPN policy via **Zscaler Sub-Locations**:

```cisco
! ===========================================================================
! vEDGE OPTION 1: NATIVE VIPTELA OS "service sig" IN TRANSPORT VPN 0
! Mode: Viptela transactional CLI ("config" -> "commit")
! ===========================================================================

system
 tracker ZS-TRACK-PRI-GE1
  endpoint-api-url http://172.21.12.162/vpntest
  threshold        3000
  interval         20
  multiplier       3
  tracker-type     interface
 !
 tracker ZS-TRACK-SEC-GE1
  endpoint-api-url http://172.21.12.166/vpntest
  threshold        3000
  interval         20
  multiplier       3
  tracker-type     interface
 !
 tracker ZS-TRACK-PRI-GE2
  endpoint-api-url http://172.21.12.154/vpntest
  threshold        3000
  interval         20
  multiplier       3
  tracker-type     interface
 !
 tracker ZS-TRACK-SEC-GE2
  endpoint-api-url http://172.21.12.158/vpntest
  threshold        3000
  interval         20
  multiplier       3
  tracker-type     interface
 !
!
vpn 0
 name Transport-VPN0
 interface ge0/0
  description WAN1-GE1-Underlay
  ip address 192.168.1.64/24
  tunnel-interface
   encapsulation ipsec
   color biz-internet
  !
  no shutdown
 !
 interface ge0/1
  description WAN2-GE2-Underlay
  ip address 192.168.1.65/24
  tunnel-interface
   encapsulation ipsec
   color public-internet
  !
  no shutdown
 !
 ! --- 4 Manual SIG GRE Tunnels in VPN 0 (Cloud 1: zscaler.net .240/.241) ---
 interface gre1
  description ZS-SIG-Primary-GE1 (sim: netns gre1 / dev gre1 / port 7002)
  ip address 172.21.12.161/30
  tunnel-source-interface ge0/0
  tunnel-destination 192.168.1.240
  mtu 1476
  tcp-mss-adjust 1360
  keepalive 5 3
  tracker ZS-TRACK-PRI-GE1
  no shutdown
 !
 interface gre2
  description ZS-SIG-Secondary-GE1 (sim: netns gre2 / dev gre2 / port 7003)
  ip address 172.21.12.165/30
  tunnel-source-interface ge0/0
  tunnel-destination 192.168.1.241
  mtu 1476
  tcp-mss-adjust 1360
  keepalive 5 3
  tracker ZS-TRACK-SEC-GE1
  no shutdown
 !
 interface gre11
  description ZS-SIG-Primary-GE2 (sim: netns gre1 / dev gre11 / port 7006)
  ip address 172.21.12.153/30
  tunnel-source-interface ge0/1
  tunnel-destination 192.168.1.240
  mtu 1476
  tcp-mss-adjust 1360
  keepalive 5 3
  tracker ZS-TRACK-PRI-GE2
  no shutdown
 !
 interface gre12
  description ZS-SIG-Secondary-GE2 (sim: netns gre2 / dev gre12 / port 7007)
  ip address 172.21.12.157/30
  tunnel-source-interface ge0/1
  tunnel-destination 192.168.1.241
  mtu 1476
  tcp-mss-adjust 1360
  keepalive 5 3
  tracker ZS-TRACK-SEC-GE2
  no shutdown
 !
 ! --- Bind GRE Tunnels into VPN 0 SIG Service HA-Pairs ---
 service sig
  ha-pairs
   interface-pair gre1 active-interface-weight 1 gre2 backup-interface-weight 1
   interface-pair gre11 active-interface-weight 1 gre12 backup-interface-weight 1
  !
 !
 ip route 0.0.0.0/0 192.168.1.254
!
vpn 10
 name Service-VPN-10-Trusted
 interface ge0/2.950
  description LAN-Trusted-VPN10
  ip address 10.23.0.1/24
  no shutdown
 !
 ip service-route 0.0.0.0/0 vpn 0 service sig
!
vpn 20
 name Service-VPN-20-Guest
 interface ge0/2.952
  description LAN-Guest-VPN20
  ip address 172.16.0.1/24
  no shutdown
 !
 ip service-route 0.0.0.0/0 vpn 0 service sig
!
commit
```

---

## 2. `vEdge` Option 2: Dual-Cloud 8-Tunnel GRE with Per-VPN `ip gre-route` (100% VeloCloud 8-Tunnel Equivalent!)

Use **`vEdge` Option 2** to terminate all 8 GRE tunnels across **both Zscaler Clouds** (`vpn 10` $\rightarrow$ `zscaler.net` `.240/.241` via `gre1, gre2, gre11, gre12` and `vpn 20` $\rightarrow$ `zscalerbeta.net` `.242/.243` via `gre21, gre22, gre31, gre32`):

```cisco
! ===========================================================================
! vEDGE OPTION 2: 8-TUNNEL DUAL-CLOUD ZSCALER GRE VIA "ip gre-route"
! Mode: Viptela transactional CLI ("config" -> "commit")
! ===========================================================================

! 1. All 8 Layer-7 HTTP (/vpntest) Trackers under "system"
system
 ! --- Cloud 1 (zscaler.net) Trackers for VPN 10 ---
 tracker ZS-TRACK-TUN1
  endpoint-api-url http://172.21.12.162/vpntest
  threshold        3000
  interval         20
  multiplier       3
  tracker-type     interface
 !
 tracker ZS-TRACK-TUN2
  endpoint-api-url http://172.21.12.166/vpntest
  threshold        3000
  interval         20
  multiplier       3
  tracker-type     interface
 !
 tracker ZS-TRACK-TUN11
  endpoint-api-url http://172.21.12.154/vpntest
  threshold        3000
  interval         20
  multiplier       3
  tracker-type     interface
 !
 tracker ZS-TRACK-TUN12
  endpoint-api-url http://172.21.12.158/vpntest
  threshold        3000
  interval         20
  multiplier       3
  tracker-type     interface
 !
 ! --- Cloud 2 (zscalerbeta.net) Trackers for VPN 20 ---
 tracker ZS-TRACK-TUN21
  endpoint-api-url http://172.20.67.74/vpntest
  threshold        3000
  interval         20
  multiplier       3
  tracker-type     interface
 !
 tracker ZS-TRACK-TUN22
  endpoint-api-url http://172.20.67.78/vpntest
  threshold        3000
  interval         20
  multiplier       3
  tracker-type     interface
 !
 tracker ZS-TRACK-TUN31
  endpoint-api-url http://172.20.67.66/vpntest
  threshold        3000
  interval         20
  multiplier       3
  tracker-type     interface
 !
 tracker ZS-TRACK-TUN32
  endpoint-api-url http://172.20.67.70/vpntest
  threshold        3000
  interval         20
  multiplier       3
  tracker-type     interface
 !
!

! 2. Transport VPN 0: WAN Underlay (ge0/0, ge0/1) & All 8 GRE Tunnels
vpn 0
 name Transport-VPN0
 interface ge0/0
  description WAN1-GE1-Underlay
  ip address 192.168.1.64/24
  tunnel-interface
   encapsulation ipsec
   color biz-internet
  !
  no shutdown
 !
 interface ge0/1
  description WAN2-GE2-Underlay
  ip address 192.168.1.65/24
  tunnel-interface
   encapsulation ipsec
   color public-internet
  !
  no shutdown
 !
 ! --- 4 GRE Tunnels for VPN 10 (Trusted -> Cloud 1: zscaler.net .240/.241) ---
 interface gre1
  description VPN10-Prod-Primary-GE1 (sim: netns gre1 / dev gre1 / port 7002)
  ip address 172.21.12.161/30
  tunnel-source-interface ge0/0
  tunnel-destination 192.168.1.240
  mtu 1476
  tcp-mss-adjust 1360
  keepalive 5 3
  tracker ZS-TRACK-TUN1
  no shutdown
 !
 interface gre2
  description VPN10-Prod-Secondary-GE1 (sim: netns gre2 / dev gre2 / port 7003)
  ip address 172.21.12.165/30
  tunnel-source-interface ge0/0
  tunnel-destination 192.168.1.241
  mtu 1476
  tcp-mss-adjust 1360
  keepalive 5 3
  tracker ZS-TRACK-TUN2
  no shutdown
 !
 interface gre11
  description VPN10-Prod-Primary-GE2 (sim: netns gre1 / dev gre11 / port 7006)
  ip address 172.21.12.153/30
  tunnel-source-interface ge0/1
  tunnel-destination 192.168.1.240
  mtu 1476
  tcp-mss-adjust 1360
  keepalive 5 3
  tracker ZS-TRACK-TUN11
  no shutdown
 !
 interface gre12
  description VPN10-Prod-Secondary-GE2 (sim: netns gre2 / dev gre12 / port 7007)
  ip address 172.21.12.157/30
  tunnel-source-interface ge0/1
  tunnel-destination 192.168.1.241
  mtu 1476
  tcp-mss-adjust 1360
  keepalive 5 3
  tracker ZS-TRACK-TUN12
  no shutdown
 !
 ! --- 4 GRE Tunnels for VPN 20 (Guest -> Cloud 2: zscalerbeta.net .242/.243) ---
 interface gre21
  description VPN20-Guest-Primary-GE1 (sim: netns gre1 / dev gre21 / port 7000)
  ip address 172.20.67.73/30
  tunnel-source-interface ge0/0
  tunnel-destination 192.168.1.242
  mtu 1476
  tcp-mss-adjust 1360
  keepalive 5 3
  tracker ZS-TRACK-TUN21
  no shutdown
 !
 interface gre22
  description VPN20-Guest-Secondary-GE1 (sim: netns gre2 / dev gre22 / port 7001)
  ip address 172.20.67.77/30
  tunnel-source-interface ge0/0
  tunnel-destination 192.168.1.243
  mtu 1476
  tcp-mss-adjust 1360
  keepalive 5 3
  tracker ZS-TRACK-TUN22
  no shutdown
 !
 interface gre31
  description VPN20-Guest-Primary-GE2 (sim: netns gre1 / dev gre31 / port 7004)
  ip address 172.20.67.65/30
  tunnel-source-interface ge0/1
  tunnel-destination 192.168.1.242
  mtu 1476
  tcp-mss-adjust 1360
  keepalive 5 3
  tracker ZS-TRACK-TUN31
  no shutdown
 !
 interface gre32
  description VPN20-Guest-Secondary-GE2 (sim: netns gre2 / dev gre32 / port 7005)
  ip address 172.20.67.69/30
  tunnel-source-interface ge0/1
  tunnel-destination 192.168.1.243
  mtu 1476
  tcp-mss-adjust 1360
  keepalive 5 3
  tracker ZS-TRACK-TUN32
  no shutdown
 !
 ip route 0.0.0.0/0 192.168.1.254
!

! 3. Service VPN 10 (Trusted -> Cloud 1: zscaler.net via gre1, gre2, gre11, gre12)
vpn 10
 name Service-VPN-10-Trusted
 interface ge0/2.950
  description LAN-Trusted-VPN10
  ip address 10.23.0.1/24
  no shutdown
 !
 ip gre-route 0.0.0.0/0 vpn 0 interface gre1 gre2 gre11 gre12
!

! 4. Service VPN 20 (Guest -> Cloud 2: zscalerbeta.net via gre21, gre22, gre31, gre32)
vpn 20
 name Service-VPN-20-Guest
 interface ge0/2.952
  description LAN-Guest-VPN20
  ip address 172.16.0.1/24
  no shutdown
 !
 ip gre-route 0.0.0.0/0 vpn 0 interface gre21 gre22 gre31 gre32
!
commit
```

---

## 3. `vEdge` (Viptela OS) Verification & Failover Testing Commands

*(Ensure the Ubuntu simulator `CONNMARK` and port `80` `DNAT` rules from [`examples/README.md`](README.md#4-common-ubuntu-simulator-preparation-for-cisco-testing) are active before testing).*

```cisco
! 1. Verify all GRE tunnel interfaces and L3/L7 tracker states in VPN 0
show interface vpn 0 | include gre
show interface detail vpn 0 gre1
show interface detail vpn 0 gre21

! 2. Verify L7 Endpoint Trackers and SIG HA-Pairs (Option 1)
show endpoint-tracker
show service sig

! 3. Verify active default routes (0.0.0.0/0) per Service VPN over BOTH Zscaler clouds
!    - VPN 10 should show 0.0.0.0/0 via gre1 (zscaler.net)
!    - VPN 20 should show 0.0.0.0/0 via gre21 (zscalerbeta.net)
show ip routes vpn 10 0.0.0.0/0
show ip routes vpn 20 0.0.0.0/0
show ip fib vpn 10 0.0.0.0/0
show ip fib vpn 20 0.0.0.0/0

! 4. Test end-to-end DEFAULT ROUTE (0.0.0.0/0) internet breakout across BOTH Zscaler clouds
ping vpn 10 8.8.8.8 source 10.23.0.1
ping vpn 20 8.8.8.8 source 172.16.0.1
traceroute vpn 10 1.1.1.1 source 10.23.0.1
traceroute vpn 20 1.1.1.1 source 172.16.0.1
```

