# Cisco Catalyst SD-WAN (`cEdge` — IOS-XE Controller Mode) Configurations for the Zscaler 8-Tunnel GRE Lab Simulator

> **Target Platform & Applicability**
> - **Operating System:** Cisco IOS-XE in **Catalyst SD-WAN Controller Mode (`cEdge`)**, Release **17.9.x / 17.12.x+**
> - **Supported Hardware & Virtual Appliances:**
>   - Cisco Catalyst 8200 / 8300 / 8500 Series Edge Platforms (`C8200`, `C8300`, `C8500`)
>   - Cisco Catalyst 8000V Edge Software (`C8000V` / `CSR1000v` in Controller Mode)
>   - Cisco ISR 1100 / ISR 4000 / ASR 1000 Series running IOS-XE SD-WAN Controller Mode
> - **Management & CLI Mode:** Managed via **Cisco Catalyst SD-WAN Manager (`vManage`)** (Feature Templates / Configuration Groups / CLI Add-On Templates) or directly via the transactional CLI (`config-transaction` $\rightarrow$ `commit`).
> - **Looking for another Cisco platform?** See [`examples/README.md`](README.md) for [Autonomous IOS-XE](cisco_autonomous_ios_xe_zscaler_gre.md), [Cisco IOS-XR](cisco_ios_xr_zscaler_gre.md), or [Cisco SD-WAN `vEdge` (Viptela OS)](cisco_sdwan_vedge_zscaler_gre.md).

---

## 0. Core Architectural Principles & Verified `cEdge` Design Constraints

### 0.1 Three Non-Negotiable Security & Routing Principles
1. **Zero Manual Route-Leaking (`route-target import/export`, `global` static routes, or VRF-to-VRF leaks):**
   Separation between the **Underlay (Transport VPN `0`)** and the **Overlay (Service VPNs `10` & `20`)** is handled 100% natively using Cisco's **Front-Door VRF (`fVRF`) / Inside VRF (`iVRF`)** tunnel architecture (`vrf forwarding` + `tunnel route-via ... mandatory`) or Cisco SD-WAN's native `service sig` abstraction.
2. **Strict Security Isolation Between `Trusted` (Production) and `Guest` Segments:**
   - **Service VPN `10` (`10.23.0.0/24`, VLAN 950)** and **Service VPN `20` (`172.16.0.0/24`, VLAN 952)** are completely isolated on the `cEdge` and can never communicate with one another.
3. **1-to-1 Mapping to the 8-Tunnel Ubuntu Simulator (`192.168.1.57`):**

| Tunnel # | Service VPN (`0.0.0.0/0`) | Zscaler Cloud & Role | `cEdge` WAN Source $\rightarrow$ Zscaler VIP | Simulator NetNS / Dev | Inner `/30` (`cEdge` $\leftrightarrow$ Sim) | Orchestrator L7 Port | Default Route AD |
| :-: | :--- | :--- | :--- | :--- | :--- | :-: | :-: |
| **1** | **Service VPN 10** (`10.23.0.0/24`) | `zscaler.net` **Primary** | `GE1 .64 -> 192.168.1.240` | `gre1` / `gre1` | `172.21.12.161 <-> 172.21.12.162` | `.240:7002` | **AD 10** (Active) |
| **2** | **Service VPN 10** (`10.23.0.0/24`) | `zscaler.net` **Secondary** | `GE1 .64 -> 192.168.1.241` | `gre2` / `gre2` | `172.21.12.165 <-> 172.21.12.166` | `.241:7003` | **AD 20** (Standby 1) |
| **3** | **Service VPN 10** (`10.23.0.0/24`) | `zscaler.net` **Primary** | `GE2 .65 -> 192.168.1.240` | `gre1` / `gre11` | `172.21.12.153 <-> 172.21.12.154` | `.240:7006` | **AD 30** (Standby 2) |
| **4** | **Service VPN 10** (`10.23.0.0/24`) | `zscaler.net` **Secondary** | `GE2 .65 -> 192.168.1.241` | `gre2` / `gre12` | `172.21.12.157 <-> 172.21.12.158` | `.241:7007` | **AD 40** (Standby 3) |
| **5** | **Service VPN 20** (`172.16.0.0/24`) | `zscalerbeta.net` **Primary** | `GE1 .64 -> 192.168.1.242` | `gre1` / `gre21` | `172.20.67.73 <-> 172.20.67.74` | `.242:7000` | **AD 10** (Active) |
| **6** | **Service VPN 20** (`172.16.0.0/24`) | `zscalerbeta.net` **Secondary** | `GE1 .64 -> 192.168.1.243` | `gre2` / `gre22` | `172.20.67.77 <-> 172.20.67.78` | `.243:7001` | **AD 20** (Standby 1) |
| **7** | **Service VPN 20** (`172.16.0.0/24`) | `zscalerbeta.net` **Primary** | `GE2 .65 -> 192.168.1.242` | `gre1` / `gre31` | `172.20.67.65 <-> 172.20.67.66` | `.242:7004` | **AD 30** (Standby 2) |
| **8** | **Service VPN 20** (`172.16.0.0/24`) | `zscalerbeta.net` **Secondary** | `GE2 .65 -> 192.168.1.243` | `gre2` / `gre32` | `172.20.67.69 <-> 172.20.67.70` | `.243:7005` | **AD 40** (Standby 3) |

---

### 0.2 Verified Cisco `cEdge` Platform Constraints vs. Lab Assumptions

1. **Why Two `cEdge` Options Are Presented (Single-Cloud `service sig` vs. Dual-Cloud Service-Side GRE):**
   - **Verified Cisco SD-WAN Constraint:** On a `cEdge` in Controller Mode, the native **SIG Feature Template** (`sdwan -> service sig vrf global -> ha-pairs`) creates a **single global SIG tunnel pool** in Transport VPN `0` (up to 4 HA pairs / 8 tunnels max) and allows **only one SIG Feature Template / Zscaler account per `cEdge` device template**. Furthermore, neither `ip sdwan route vrf <id> 0.0.0.0/0 service sig` nor a `vSmart` Centralized Data Policy (`set service sig`) can pin `Service VPN 10` to one SIG tunnel pair (`.240/.241`) and `Service VPN 20` to a *different* SIG tunnel pair (`.242/.243`) inside `service sig vrf global`.
   - **Architectural Consequence:**
     - **cEdge Option 1 (`service sig vrf global` in VPN 0):** Ideal when both `VPN 10` (`10.23.0.0/24`) and `VPN 20` (`172.16.0.0/24`) terminate on the **same Zscaler Cloud** (`zscaler.net`, `.240/.241`) and Zscaler enforces per-VRF policy via **Zscaler Sub-Locations** (matching the un-NATted inner client subnet `10.23.0.0/24` vs. `172.16.0.0/24`).
     - **cEdge Option 2 (Per-Service-VPN Dedicated GRE Tunnels via `vrf forwarding 10` & `vrf forwarding 20`):** **Required** if `VPN 10` (`0.0.0.0/0` $\rightarrow$ `zscaler.net` `.240/.241`) and `VPN 20` (`0.0.0.0/0` $\rightarrow$ `zscalerbeta.net` `.242/.243`) must terminate on **two separate Zscaler Clouds** (or physically separate per-VRF GRE tunnels) on a single `cEdge` router—100% matching the VeloCloud 8-tunnel lab topology.
2. **Verified Cisco `endpoint-tracker` vs. `ip sla http raw` L7 Probing Constraint in Service VPNs:**
   - On `cEdge` Transport VPN `0` (`cEdge Option 1`), `endpoint-tracker` with `tracker-type interface` natively supports HTTP URLs (`endpoint-api-url http://.../vpntest`), with a minimum Cisco-enforced probe interval of **20 seconds** (`interval 20`, range `20..600`).
   - However, for **Service VPN static routes** (`cEdge Option 2`), Cisco's native `endpoint-tracker` with `tracker-type static-route` **does not support HTTP URLs (`endpoint-api-url`)**—it only supports ICMP or TCP/UDP port probes. Therefore, to run true HTTP Layer-7 `GET /vpntest` probes with a **5-second interval** inside Service VPNs `10` and `20`, **cEdge Option 2** uses standard IOS-XE VRF-aware `ip sla <id> -> http raw` + `track <id> ip sla <id> state` (pushed via a vManage **CLI Add-On Template**, or configured directly in `config-transaction`). We also document the alternative 100% GUI Feature-Template `tracker-type static-route` TCP port `80` tracker under Option 2.
3. **Verified Cisco IOS-XE VRF-Aware GRE `keepalive` Constraint (`iVRF != fVRF`):**
   - In **cEdge Option 1 (`service sig vrf global`)**, both the inner tunnel interface (`iVRF`) and the outer transport header (`fVRF`) reside in **Transport VPN `0` (`global`)** (`iVRF == fVRF`). Therefore, standard L3 GRE `keepalive 5 3` is 100% supported and active on `Tunnel100001..100012` alongside the 20-second L7 `endpoint-tracker`.
   - In **cEdge Option 2**, the inner tunnel payload is placed inside **Service VPN `10` or `20` (`vrf forwarding 10/20`, `iVRF`)**, while the outer GRE transport header resides in **Transport VPN `0` (`fVRF`)** (`iVRF != fVRF`).
   - Per the official **Cisco IOS-XE IPv4 GRE Configuration Guide** (*"Keepalive is not supported on VRF-aware GRE tunnels"* when `iVRF != fVRF`), Cisco's L3 GRE keepalive mechanism encapsulates a pre-built inner return GRE packet (`src=Zscaler_VIP, dst=Cisco_WAN_IP, protocol=47`) inside the outgoing GRE packet. When `iVRF != fVRF`, the return lookup for the outer WAN IP (`192.168.1.64/.65`) occurs inside the inner VRF (`VRF 10/20`), where the underlay WAN subnet does not exist (and must never be leaked!), causing the tunnel line-protocol to drop if `keepalive` is configured.
   - Therefore, in **cEdge Option 2**, `keepalive` is **intentionally omitted** on `Tunnel1..Tunnel32`. Instead, Option 2 uses:
     1. **`tunnel route-via GigabitEthernet1/2 mandatory`** (which immediately brings the tunnel line-protocol `DOWN` if the underlay WAN interface or route fails), and
     2. **VRF-aware L7 `ip sla http raw` (`/vpntest` every 5 seconds with `track 1..32` `delay down 15 up 30`)**, which tests **both** the L3 GRE data-plane path and the L7 Zscaler `/vpntest` responder end-to-end inside `VRF 10` and `VRF 20` every 5 seconds.
4. **Explicit Lab Assumptions:**
   - **Interface Naming:** Examples use `GigabitEthernet1` (`192.168.1.64`), `GigabitEthernet2` (`192.168.1.65`), and LAN sub-interfaces `GigabitEthernet3.950` / `GigabitEthernet3.952` (matching Catalyst 8000V virtual routers). On physical Catalyst 8200/8300 or ISR 4000 hardware, substitute `GigabitEthernet0/0/0`, `GigabitEthernet0/0/1`, and `GigabitEthernet0/0/2.950`.
   - **Inside-the-Tunnel L7 Probes:** Because each probe targets the **connected `/30` Zscaler ZEN IP** (`172.21.12.162:80`, etc.), the probe is guaranteed by the connected `/30` route to egress strictly out its own GRE tunnel even when that tunnel's tracked `0.0.0.0/0` route is `DOWN`. On the Ubuntu simulator, the 8 `iptables` `DNAT` rules (see [`examples/README.md`](README.md#step-b-enable-the-8-iptables-tcp-port-80-dnat-rules-for-inside-the-tunnel-http-vpntest-probes)) redirect those inside-the-tunnel TCP port `80` probes to the simulator's `7000..7007` listeners.

---

### 0.3 Cisco IOS-XE YANG Data Model & Transactional (`config-transaction`) Compliance

On a Cisco Catalyst SD-WAN `cEdge` router in Controller Mode (IOS-XE 17.9+ / 17.12+), all configuration changes—whether pushed from **Catalyst SD-WAN Manager (`vManage`)** via NETCONF or entered locally via `config-transaction`—are validated by the onboard **ConfD / Data Model Interface (DMI)** transactional engine against Cisco's native YANG data models (`Cisco-IOS-XE-native.yang` and its included submodules in [`YangModels/yang/vendor/cisco/xe/17121`](https://github.com/YangModels/yang/tree/main/vendor/cisco/xe/17121)).

Every configuration block in this document has been directly verified against the official Cisco IOS-XE `17.12.1` `.yang` source schemas—no out-of-band shell scripts, no manual cross-VRF route-leaks, and no unmodeled legacy CLI workarounds are used:

| Architectural Component | Official Cisco IOS-XE `17.12.1` YANG Module | Verified YANG Data Node / XPath (`Cisco-IOS-XE-native`) | vManage / Catalyst SD-WAN Manager Representation |
| :--- | :--- | :--- | :--- |
| **Service VPN (VRF) Isolation (`10` & `20`)** | `Cisco-IOS-XE-native.yang` (line 2458, via submodule `Cisco-IOS-XE-ip.yang` line 1344)<br>`Cisco-IOS-XE-interfaces.yang` (line 4496) | `/native/vrf/definition[name='10'\|'20']/address-family/ipv4`<br>`/native/interface/GigabitEthernet/vrf-choice/vrf/vrf/forwarding` | **Service VPN Feature Template** (`VPN 10`, `VPN 20`) + **VPN Interface Ethernet** |
| **GRE Tunnel Encapsulation (`tunnel mode gre ip`) & Underlay Pinning (`route-via mandatory`)** | `Cisco-IOS-XE-tunnel.yang` (lines 280, 288, 649, 1242)<br>`Cisco-IOS-XE-interfaces.yang` (lines 1600, 2332) | `/native/interface/Tunnel/tunnel/source`<br>`/native/interface/Tunnel/tunnel/destination-config/ipv4`<br>`/native/interface/Tunnel/tunnel/mode/gre-config/ip`<br>`/native/interface/Tunnel/tunnel/route-via/interface` + `mandatory`<br>`/native/interface/Tunnel/keepalive-choice/keepalive-settings/keepalive`<br>`/native/interface/Tunnel/ip/tcp/adjust-mss` | **SIG Feature Template** (Option 1) or **Service VPN Interface GRE Template** (Option 2) |
| **SD-WAN Service Routing (`ip sdwan route vrf`)** | `Cisco-IOS-XE-ip.yang` (lines 4114–4166) | `/native/ip/sdwan/route/vrf[vrf='10'\|'20']/route[ipaddr='0.0.0.0/0']/service/sig` *(case `service-based`, line 4153)*<br>`/native/ip/sdwan/route/vrf[vrf='10'\|'20']/route[ipaddr='0.0.0.0/0']/tunnel/active` + `backup` *(case `tunnel-based`, line 4131)* | **Service VPN Route (`service sig` or `tunnel active/backup`)** |
| **SD-WAN Underlay & SIG HA-Pairs (`sdwan` block, `Option 1`)** | On-box ConfD daemon module `Cisco-IOS-XE-sdwan` (RPCs in `Cisco-IOS-XE-sdwan-rpc.yang`) | `/native/sdwan/interface/Tunnel/tunnel-options`<br>`/native/sdwan/service/sig/vrf[name='global']/ha-pairs` | **SIG Feature Template** |
| **Native Endpoint Tracker (`Option 1` HTTP & `Option 2` Static-Route TCP)** | `Cisco-IOS-XE-native.yang` (line 4747) + `Cisco-IOS-XE-track.yang` (line 323) + on-box `Cisco-IOS-XE-endpoint-tracker` (`-oper.yang` in public repo) | `/native/endpoint-tracker`<br>`/native/track/tracked-object[object-number]/endpoint-tracker` | **System / VPN Endpoint Tracker Feature Template** (or Configuration Group Policy Object) |
| **VRF-Aware L7 HTTP `/vpntest` Probes (`Option 2`)** | `Cisco-IOS-XE-sla.yang` (lines 3753, 3826, 3918, 3951) | `/native/ip/sla/entry[number]/http/raw/url`, `source-ip`, `cache`<br>`/native/ip/sla/entry[number]/http/vrf`<br>`/native/ip/sla/entry[number]/http/http-raw-request/raw-request-string`<br>`/native/ip/sla/schedule[entry-number]/life` + `start-time` | **CLI Add-On Feature Template** (or YANG/NETCONF payload in Configuration Groups) |
| **Object Tracking & Delay Timers (`Option 2`)** | `Cisco-IOS-XE-track.yang` (lines 128, 395–412) | `/native/track/tracked-object[object-number]/ip/sla/number` + `state-sla`<br>`/native/track/tracked-object[object-number]/delay/down` + `up` | **CLI Add-On Feature Template** |
| **Tracked Floating Default Routes (`0.0.0.0/0` per VRF, `Option 2`)** | `Cisco-IOS-XE-ip.yang` (lines 1800–2135, 3546) | `/native/ip/route/vrf[name]/ip-route-interface-forwarding-list[prefix][mask]/fwd-list[fwd]/interface-next-hop[ip-address]` (`metric`, `track-id-name/id`, `name`) | **Service VPN Feature Template (IPv4 Static Route)** or **CLI Add-On Feature Template** |

> **Public `YangModels/yang` Tree vs. On-Box `cEdge` ConfD Daemon Schemas:**
> - In the public [`YangModels/yang/vendor/cisco/xe/17121`](https://github.com/YangModels/yang/tree/main/vendor/cisco/xe/17121) repository, `vrf definition` is modeled inside submodule `Cisco-IOS-XE-ip.yang` (line 1344, included by `Cisco-IOS-XE-native.yang` line 2458)—there is no separate `Cisco-IOS-XE-vrf.yang` config file (only `Cisco-IOS-XE-vrf-oper.yang`).
> - Similarly, `/native/endpoint-tracker` is declared in `Cisco-IOS-XE-native.yang` (line 4747), `/native/track/tracked-object/endpoint-tracker` is in `Cisco-IOS-XE-track.yang` (line 323), and `/native/ip/sdwan/route/vrf` is in `Cisco-IOS-XE-ip.yang` (line 4114), while the Controller-Mode-specific `sdwan` and `endpoint-tracker` sub-containers are exported by the on-box `cEdge` ConfD daemon (`show yang schema` / NETCONF `<get-schema>`).

> **Verifying Transactional & YANG Compliance on the `cEdge`:**
> When pasting either **cEdge Option 1** or **cEdge Option 2** into `config-transaction` on a Catalyst 8000V / `cEdge`, you can validate the complete candidate datastore against the YANG schema before committing by running:
> ```cisco
> cEdge# config-transaction
> cEdge(config)# ! (paste Option 1 or Option 2 configuration)
> cEdge(config)# validate
> Validation complete
> cEdge(config)# commit
> ```

---

## 1. Architectural Comparison of the Two `cEdge` Options

```text
+===================================================================================+
|         COMPARISON OF THE 2 cEDGE OPTIONS (CONTROLLER MODE IOS-XE 17.9+)          |
+===================================================================================+
|                                                                                   |
|  cEDGE OPTION 1: Native Cisco SD-WAN "service sig" (Tunnels in Transport VPN 0)   |
|  ------------------------------------------------------------------------------   |
|   [Service VPN 10: 10.23.0.0/24]      [Service VPN 20: 172.16.0.0/24]             |
|          |                                          |                             |
|          | ip sdwan route vrf 10 0.0.0.0/0          | ip sdwan route vrf 20 ...   |
|          |   service sig (or vSmart "set service    |   service sig               |
|          |   sig")                                  |                             |
|          +--------------------+---------------------+                             |
|                               | (cEdge internal SIG state table keeps VRFs apart; |
|                               |  Zscaler Sub-Locations distinguish .23.0 vs .16.0)|
|                               v                                                   |
|   [Transport VPN 0 (Global Underlay: "sdwan -> service sig vrf global")]          |
|    * Tunnel100001..100012 (pinned via "tunnel route-via Gi1/Gi2 mandatory")       |
|    * endpoint-tracker (L7 http://<inner_ip>/vpntest) + L3 GRE keepalive           |
|    * Limitation: 1 global SIG pool / 1 Zscaler Cloud per cEdge device template    |
|                                                                                   |
|  -------------------------------------------------------------------------------  |
|                                                                                   |
|  cEDGE OPTION 2: Per-Service-VPN Dedicated GRE Tunnels (VeloCloud 8-Tunnel Model) |
|  -------------------------------------------------------------------------------- |
|   [Service VPN 10: 10.23.0.0/24]      [Service VPN 20: 172.16.0.0/24]             |
|    * vrf forwarding 10                 * vrf forwarding 20                        |
|    * Tunnel1, Tunnel2,                 * Tunnel21, Tunnel22,                      |
|      Tunnel11, Tunnel12                  Tunnel31, Tunnel32                       |
|    * 0.0.0.0/0 tracked floating        * 0.0.0.0/0 tracked floating               |
|      routes (AD 10, 20, 30, 40)          routes (AD 10, 20, 30, 40)               |
|    * To Cloud 1: zscaler.net           * To Cloud 2: zscalerbeta.net              |
|      (.240 Primary / .241 Secondary)     (.242 Primary / .243 Secondary)          |
|          |                                          |                             |
|          +--------------------+---------------------+                             |
|                               | (Only outer GRE header uses VPN 0 via             |
|                               v  "tunnel route-via Gi1/Gi2 mandatory")            |
|   [Transport VPN 0 (Global Underlay: Gi1 .64 / Gi2 .65)]                          |
+===================================================================================+
```

| Feature / Dimension | **cEdge Option 1: Native `service sig` (Tunnels in VPN 0)** | **cEdge Option 2: Per-Service-VPN GRE (`vrf forwarding 10/20`)** |
| :--- | :--- | :--- |
| **Where do the GRE tunnels reside?** | Inside **Transport VPN 0** (Global Routing Table). | Inner payload in **Service VPN 10 / 20** (`iVRF`); outer header in **VPN 0** (`fVRF`). |
| **Support for 2 Separate Zscaler Clouds (`zscaler.net` + `zscalerbeta.net`)?** | **No (Single Global SIG Pool):** All Service VPNs pointing to `service sig` share the same `service sig vrf global` HA tunnel pool (1 Zscaler Cloud per `cEdge`). Zscaler distinguishes `VPN 10` (`10.23.0.0/24`) vs. `VPN 20` (`172.16.0.0/24`) via **Zscaler Sub-Locations**. | **Yes (100% VeloCloud 8-Tunnel Equivalent):**<br>- `VPN 10` (`0.0.0.0/0`) uses 4 dedicated tunnels (`Tunnel1/2/11/12`) to **`zscaler.net`** (`.240/.241`).<br>- `VPN 20` (`0.0.0.0/0`) uses 4 dedicated tunnels (`Tunnel21/22/31/32`) to **`zscalerbeta.net`** (`.242/.243`). |
| **How are VPN 10 and VPN 20 isolated?** | `cEdge` maintains a stateful VRF session table so return traffic from Zscaler is placed back into the originating Service VPN. | **Physically separate GRE tunnels and separate VRF routing tables** (`vrf forwarding 10` vs. `vrf forwarding 20`). |
| **L7 / L3 Health Check Mechanism** | Native `endpoint-tracker` (`tracker-type interface`, min `interval 20`s) + L3 GRE `keepalive 5 3` (`iVRF == fVRF == VPN 0`). | VRF-aware `ip sla http raw` (`/vpntest`, `frequency 5`s) + `track` + `tunnel route-via mandatory` (L3 GRE `keepalive` omitted because `iVRF != fVRF`; see Section 0.2 #3). |
| **vManage Deployment Method** | **SIG Feature Template** + Service VPN `Service Route` (`service sig`). | **Service VPN Feature Template (`VPN Interface GRE`)** + **CLI Add-On Template** for VRF `ip sla http raw` and tracked default routes. |

---

## 2. `cEdge` Option 1: Native Cisco SD-WAN `service sig` (Transport VPN 0 SIG Tunnels)

In the standard Cisco/Zscaler SD-WAN SIG workflow, the **Cisco SIG Feature Template** creates the GRE tunnels inside **Transport VPN 0** and binds them into `sdwan -> service sig vrf global -> ha-pairs`.
- **Default Route Steering (`0.0.0.0/0`):** Configured per Service VPN via `ip sdwan route vrf 10 0.0.0.0/0 service sig` and `ip sdwan route vrf 20 0.0.0.0/0 service sig` (or selectively via a `vSmart` Centralized Data Policy using `set service sig`).
- **How `VPN 10` and `VPN 20` Are Distinguished in Zscaler:** Because `service sig vrf global` places all SIG tunnels into a single global HA pool on the `cEdge`, both `VPN 10` (`10.23.0.0/24`) and `VPN 20` (`172.16.0.0/24`) traverse the active `zscaler.net` tunnels (`Tunnel100001..100012`). Because the `cEdge` does not NAT inner client IPs on GRE SIG tunnels, Zscaler receives the original source IPs (`10.23.0.0/24` vs. `172.16.0.0/24`) and applies separate `Trusted` vs. `Guest` security policies via **Zscaler Sub-Locations**.

Below is the verified `cEdge` Controller-Mode configuration (`config-transaction`) for **cEdge Option 1**:

```cisco
! ===========================================================================
! cEDGE OPTION 1: NATIVE CISCO SD-WAN SIG GRE (TUNNELS IN TRANSPORT VPN 0)
! Applied via vManage SIG Feature Template or "config-transaction" on cEdge
! ===========================================================================

! 1. Service VPNs (VRFs) — Strictly isolated; no route-targets shared between 10 and 20!
vrf definition 10
 description Service-VPN-10-Trusted (10.23.0.0/24)
 rd 1:10
 address-family ipv4
  route-target export 1:10
  route-target import 1:10
 exit-address-family
!
vrf definition 20
 description Service-VPN-20-Guest (172.16.0.0/24)
 rd 1:20
 address-family ipv4
  route-target export 1:20
  route-target import 1:20
 exit-address-family
!

! 2. Transport Interfaces in VPN 0 (Global Routing Table on cEdge)
interface GigabitEthernet1
 description WAN1-GE1-Underlay (VPN 0)
 no shutdown
 ip address 192.168.1.64 255.255.255.0
!
interface GigabitEthernet2
 description WAN2-GE2-Underlay (VPN 0)
 no shutdown
 ip address 192.168.1.65 255.255.255.0
!
! Underlay default routes in VPN 0
ip route 0.0.0.0 0.0.0.0 GigabitEthernet1 192.168.1.254
ip route 0.0.0.0 0.0.0.0 GigabitEthernet2 192.168.1.254

! 3. Service-Side LAN Sub-interfaces in VPN 10 and VPN 20
interface GigabitEthernet3.950
 description LAN-Trusted-VPN10
 no shutdown
 encapsulation dot1Q 950
 vrf forwarding 10
 ip address 10.23.0.1 255.255.255.0
!
interface GigabitEthernet3.952
 description LAN-Guest-VPN20
 no shutdown
 encapsulation dot1Q 952
 vrf forwarding 20
 ip address 172.16.0.1 255.255.255.0
!

! 4. Manual/Static SIG GRE Tunnels in Transport VPN 0
!    - "tunnel route-via <Interface> mandatory" strictly pins each tunnel's
!      outer GRE packets to its dedicated WAN interface (Gi1 .64 or Gi2 .65).
!    - "ip mtu 1476" (1500 - 24B IP+GRE); "ip tcp adjust-mss 1360" (Zscaler
!      conservative default; 1436 is also valid for 1500B Ethernet).
!    - "keepalive 5 3" is supported here because iVRF == fVRF == VPN 0 (global).
interface Tunnel100001
 description ZS-SIG-Primary-GE1 (sim: netns gre1 / dev gre1 / port 7002)
 no shutdown
 ip address 172.21.12.161 255.255.255.252
 ip tcp adjust-mss 1360
 ip mtu 1476
 keepalive 5 3
 tunnel source GigabitEthernet1
 tunnel destination 192.168.1.240
 tunnel mode gre ip
 tunnel route-via GigabitEthernet1 mandatory
!
interface Tunnel100002
 description ZS-SIG-Secondary-GE1 (sim: netns gre2 / dev gre2 / port 7003)
 no shutdown
 ip address 172.21.12.165 255.255.255.252
 ip tcp adjust-mss 1360
 ip mtu 1476
 keepalive 5 3
 tunnel source GigabitEthernet1
 tunnel destination 192.168.1.241
 tunnel mode gre ip
 tunnel route-via GigabitEthernet1 mandatory
!
interface Tunnel100011
 description ZS-SIG-Primary-GE2 (sim: netns gre1 / dev gre11 / port 7006)
 no shutdown
 ip address 172.21.12.153 255.255.255.252
 ip tcp adjust-mss 1360
 ip mtu 1476
 keepalive 5 3
 tunnel source GigabitEthernet2
 tunnel destination 192.168.1.240
 tunnel mode gre ip
 tunnel route-via GigabitEthernet2 mandatory
!
interface Tunnel100012
 description ZS-SIG-Secondary-GE2 (sim: netns gre2 / dev gre12 / port 7007)
 no shutdown
 ip address 172.21.12.157 255.255.255.252
 ip tcp adjust-mss 1360
 ip mtu 1476
 keepalive 5 3
 tunnel source GigabitEthernet2
 tunnel destination 192.168.1.241
 tunnel mode gre ip
 tunnel route-via GigabitEthernet2 mandatory
!

! 5. Native cEdge L7 Endpoint Trackers (inside-the-tunnel HTTP /vpntest on port 80)
!    Note: On Cisco IOS-XE cEdge, "tracker-type interface" enforces a minimum
!    "interval" of 20 seconds (range 20..600).
endpoint-tracker ZS-TRACK-PRI-GE1
 endpoint-api-url http://172.21.12.162/vpntest
 interval 20
 threshold 3000
 multiplier 3
 tracker-type interface
!
endpoint-tracker ZS-TRACK-SEC-GE1
 endpoint-api-url http://172.21.12.166/vpntest
 interval 20
 threshold 3000
 multiplier 3
 tracker-type interface
!
endpoint-tracker ZS-TRACK-PRI-GE2
 endpoint-api-url http://172.21.12.154/vpntest
 interval 20
 threshold 3000
 multiplier 3
 tracker-type interface
!
endpoint-tracker ZS-TRACK-SEC-GE2
 endpoint-api-url http://172.21.12.158/vpntest
 interval 20
 threshold 3000
 multiplier 3
 tracker-type interface
!

! 6. SD-WAN Block, SIG HA-Pairs & Service Routes per Service VPN
!    Note on "tunnel-set":
!    - For Manual/Static GRE SIG tunnels (with static /30 IP & static destination,
!      as used against this lab simulator), cEdge uses:
!        "tunnel-set secure-internet-gateway-other"
!    - For Automated Zscaler Cloud API tunnels (with "ip unnumbered Gi1",
!      "tunnel destination dynamic", and a SIG Credentials template), cEdge uses:
!        "tunnel-set secure-internet-gateway-zscaler"
!        "tunnel-dc-preference primary-dc" (or "secondary-dc")
sdwan
 interface GigabitEthernet1
  tunnel-interface
   encapsulation ipsec
   color biz-internet
  exit
 exit
 interface GigabitEthernet2
  tunnel-interface
   encapsulation ipsec
   color public-internet
  exit
 exit
 interface Tunnel100001
  tunnel-options
   tunnel-set secure-internet-gateway-other
   source-interface GigabitEthernet1
  exit
  endpoint-tracker ZS-TRACK-PRI-GE1
 exit
 interface Tunnel100002
  tunnel-options
   tunnel-set secure-internet-gateway-other
   source-interface GigabitEthernet1
  exit
  endpoint-tracker ZS-TRACK-SEC-GE1
 exit
 interface Tunnel100011
  tunnel-options
   tunnel-set secure-internet-gateway-other
   source-interface GigabitEthernet2
  exit
  endpoint-tracker ZS-TRACK-PRI-GE2
 exit
 interface Tunnel100012
  tunnel-options
   tunnel-set secure-internet-gateway-other
   source-interface GigabitEthernet2
  exit
  endpoint-tracker ZS-TRACK-SEC-GE2
 exit
 !
 ! Global SIG Service HA-Pairs (Active/Backup pairing per WAN transport):
 service sig vrf global
  ha-pairs
   interface-pair Tunnel100001 active-interface-weight 1 Tunnel100002 backup-interface-weight 1
   interface-pair Tunnel100011 active-interface-weight 1 Tunnel100012 backup-interface-weight 1
  !
 !
exit
!
! 7. Native Default Routes (0.0.0.0/0) in Service VPN 10 and Service VPN 20 (ZERO route-leaks!)
!    - Verified in Cisco-IOS-XE-ip.yang (lines 4114-4166):
!      * Case "service-based" (lines 4153-4166): steers VRF traffic to the global SIG HA-Pairs pool:
ip sdwan route vrf 10 0.0.0.0/0 service sig
ip sdwan route vrf 20 0.0.0.0/0 service sig
!      * Alternative Case "tunnel-based" (lines 4131-4152): Cisco-IOS-XE-ip.yang also models explicit
!        per-VRF active/backup SIG tunnel pinning:
!        ip sdwan route vrf 10 0.0.0.0/0 tunnel active Tunnel100001 backup Tunnel100002
!        ip sdwan route vrf 20 0.0.0.0/0 tunnel active Tunnel100011 backup Tunnel100012
```

### Optional for Option 1: Controller (`vSmart`) Centralized Data Policy to Bypass RFC1918 Traffic
If `VPN 10` or `VPN 20` also routes internal RFC1918 destinations over the SD-WAN OMP overlay, you can optionally attach a Centralized Data Policy on `vSmart` so RFC1918 traffic uses normal routing (`default-action accept`) while `0.0.0.0/0` internet traffic is steered to `service sig`:

```cisco
! On the vSmart Controller:
policy
 lists
  vpn-list VPN-TRUSTED-AND-GUEST
   vpn 10
   vpn 20
  !
  data-prefix-list RFC1918-INTERNAL
   ip-prefix 10.0.0.0/8
   ip-prefix 172.16.0.0/12
   ip-prefix 192.168.0.0/16
  !
 !
 data-policy DP-ZSCALER-SIG
  vpn-list VPN-TRUSTED-AND-GUEST
   sequence 10
    match
     destination-data-prefix-list RFC1918-INTERNAL
    !
    action accept
    !
   !
   sequence 20
    match
     destination-ip 0.0.0.0/0
    !
    action accept
     set service sig
     ! Optional (IOS-XE 17.8+ / vManage 20.8+): fall back to overlay/DIA if all SIG tunnels fail
     ! sig-action fallback-to-routing
    !
   !
   default-action accept
  !
 !
!
```

> **Simulator Note for `cEdge` Option 1:**
> Because `cEdge Option 1` sends both `VPN 10` (`10.23.0.0/24`) and `VPN 20` (`172.16.0.0/24`) through the `zscaler.net` SIG tunnels (`Tunnel100001`/`gre1` and `Tunnel100002`/`gre2`), if you test Option 1 against the Ubuntu simulator (`doit.sh`), update the `172.16.0.0/24` return route inside `gre1`/`gre2` to point to `gre1`/`gre2`:
> `sudo ip -n gre1 route replace 172.16.0.0/24 dev gre1` and `sudo ip -n gre2 route replace 172.16.0.0/24 dev gre2`.
> To use **all 8 tunnels across both Zscaler clouds (`zscaler.net` `.240/.241` AND `zscalerbeta.net` `.242/.243`)** with hard per-VRF separation out of the box—identical to VeloCloud—use **`cEdge` Option 2** below.

---

## 3. `cEdge` Option 2: Per-Service-VPN Dedicated GRE Tunnels on `cEdge` (100% VeloCloud Dual-Cloud 8-Tunnel Equivalent)

When testing against the 8-tunnel Ubuntu simulator—or when an enterprise requires **strict physical tunnel, VRF routing table, and dual Zscaler Cloud separation (`zscaler.net` for `VPN 10` and `zscalerbeta.net` for `VPN 20`)**—**`cEdge` Option 2** is the exact architectural equivalent of the VeloCloud 8-tunnel deployment:
- **Service-Side GRE Interfaces (`vrf forwarding 10` & `vrf forwarding 20`):**
  Configured in vManage using **Service VPN Feature Template $\rightarrow$ Additional VPN Templates $\rightarrow$ VPN Interface GRE** (or via a **CLI Add-On Template**).
  - The **inside (overlay/payload)** of each GRE tunnel is placed directly inside its own Service VPN (`vrf forwarding 10` for `Tunnel1, 2, 11, 12` and `vrf forwarding 20` for `Tunnel21, 22, 31, 32`).
  - The **outside (underlay/transport)** of each GRE tunnel uses Transport VPN 0 (`tunnel source GigabitEthernet1/2`, `tunnel destination 192.168.1.240..243`, and `tunnel route-via GigabitEthernet1/2 mandatory`).
- **Dual-Cloud Default Routing (`0.0.0.0/0`) and Health-Check Tracking:**
  - **Service VPN `10` (`10.23.0.0/24`)** has 4 tracked floating static default routes (`0.0.0.0/0`) pointing exclusively to **`zscaler.net`** (`Tunnel1` AD 10, `Tunnel2` AD 20, `Tunnel11` AD 30, `Tunnel12` AD 40).
  - **Service VPN `20` (`172.16.0.0/24`)** has 4 tracked floating static default routes (`0.0.0.0/0`) pointing exclusively to **`zscalerbeta.net`** (`Tunnel21` AD 10, `Tunnel22` AD 20, `Tunnel31` AD 30, `Tunnel32` AD 40).
  - **Why Targeting the Connected `/30` Zscaler Peer IP (`172.21.12.162`, etc.) Is Crucial:**
     Because `172.21.12.162/30` is directly connected on `Tunnel1` inside `vrf 10`, the IP SLA probe (`source-ip 172.21.12.161` $\rightarrow$ `172.21.12.162:80`) always matches the connected `/30` interface route for `Tunnel1`—even when `track 1` is `DOWN` and `0.0.0.0/0` has failed over to `Tunnel2`! This guarantees that each tunnel's health probe never leaks onto another tunnel and automatically detects when the primary tunnel recovers (`delay up 30`).
  - **Why `track <n> ip sla <n> state` Is Used Instead of `reachability`:**
    In Cisco IOS-XE, if an HTTP probe completes but exceeds the configured `threshold` (`OverThreshold`), `track ... reachability` still considers the probe `UP`, whereas `track ... state` transitions to `DOWN`. Using `track <n> ip sla <n> state` with `timeout 3000` and `threshold 3000` accurately reproduces VeloCloud's `rttThresholdMs: 3000` failover behavior when testing `DEGRADED` latency in `zscaler_orchestrator_pyroute2.py`.

Below is the complete, verified `cEdge` Controller-Mode CLI configuration (`config-transaction` / CLI Add-On Template) for **`cEdge` Option 2**:

```cisco
! ===========================================================================
! cEDGE OPTION 2: PER-SERVICE-VPN DEDICATED 8-TUNNEL GRE (DUAL ZSCALER CLOUD)
! ===========================================================================

! 1. Service VPNs (VRFs) — Completely isolated
vrf definition 10
 description Service-VPN-10-Trusted (10.23.0.0/24 -> zscaler.net)
 rd 1:10
 address-family ipv4
  route-target export 1:10
  route-target import 1:10
 exit-address-family
!
vrf definition 20
 description Service-VPN-20-Guest (172.16.0.0/24 -> zscalerbeta.net)
 rd 1:20
 address-family ipv4
  route-target export 1:20
  route-target import 1:20
 exit-address-family
!

! 2. Transport Interfaces in VPN 0 (Global Underlay)
interface GigabitEthernet1
 description WAN1-GE1-Underlay (VPN 0)
 no shutdown
 ip address 192.168.1.64 255.255.255.0
!
interface GigabitEthernet2
 description WAN2-GE2-Underlay (VPN 0)
 no shutdown
 ip address 192.168.1.65 255.255.255.0
!
ip route 0.0.0.0 0.0.0.0 GigabitEthernet1 192.168.1.254
ip route 0.0.0.0 0.0.0.0 GigabitEthernet2 192.168.1.254
!
sdwan
 interface GigabitEthernet1
  tunnel-interface
   encapsulation ipsec
   color biz-internet
  exit
 exit
 interface GigabitEthernet2
  tunnel-interface
   encapsulation ipsec
   color public-internet
  exit
 exit
exit

! 3. Service-Side LAN Interfaces
interface GigabitEthernet3.950
 description LAN-Trusted-VPN10
 no shutdown
 encapsulation dot1Q 950
 vrf forwarding 10
 ip address 10.23.0.1 255.255.255.0
!
interface GigabitEthernet3.952
 description LAN-Guest-VPN20
 no shutdown
 encapsulation dot1Q 952
 vrf forwarding 20
 ip address 172.16.0.1 255.255.255.0
!

! ===========================================================================
! 4A. 4 GRE TUNNELS IN SERVICE VPN 10 (TRUSTED -> Cloud 1: zscaler.net .240/.241)
!     Inner Payload: vrf forwarding 10 (iVRF)
!     Outer Header:  VPN 0 (fVRF) pinned via "tunnel route-via Gi1/Gi2 mandatory"
!     Note: L3 GRE "keepalive" is intentionally omitted because iVRF != fVRF
!     (see Section 0.2 #3); tunnel health is monitored every 5s by VRF-aware
!     "ip sla http raw" (/vpntest) + "tunnel route-via ... mandatory".
! ===========================================================================
interface Tunnel1
 description VPN10-Prod-Primary-GE1 (sim: netns gre1 / dev gre1 / port 7002)
 no shutdown
 vrf forwarding 10
 ip address 172.21.12.161 255.255.255.252
 ip mtu 1476
 ip tcp adjust-mss 1436
 tunnel source GigabitEthernet1
 tunnel destination 192.168.1.240
 tunnel mode gre ip
 tunnel route-via GigabitEthernet1 mandatory
!
interface Tunnel2
 description VPN10-Prod-Secondary-GE1 (sim: netns gre2 / dev gre2 / port 7003)
 no shutdown
 vrf forwarding 10
 ip address 172.21.12.165 255.255.255.252
 ip mtu 1476
 ip tcp adjust-mss 1436
 tunnel source GigabitEthernet1
 tunnel destination 192.168.1.241
 tunnel mode gre ip
 tunnel route-via GigabitEthernet1 mandatory
!
interface Tunnel11
 description VPN10-Prod-Primary-GE2 (sim: netns gre1 / dev gre11 / port 7006)
 no shutdown
 vrf forwarding 10
 ip address 172.21.12.153 255.255.255.252
 ip mtu 1476
 ip tcp adjust-mss 1436
 tunnel source GigabitEthernet2
 tunnel destination 192.168.1.240
 tunnel mode gre ip
 tunnel route-via GigabitEthernet2 mandatory
!
interface Tunnel12
 description VPN10-Prod-Secondary-GE2 (sim: netns gre2 / dev gre12 / port 7007)
 no shutdown
 vrf forwarding 10
 ip address 172.21.12.157 255.255.255.252
 ip mtu 1476
 ip tcp adjust-mss 1436
 tunnel source GigabitEthernet2
 tunnel destination 192.168.1.241
 tunnel mode gre ip
 tunnel route-via GigabitEthernet2 mandatory
!

! ===========================================================================
! 4B. 4 GRE TUNNELS IN SERVICE VPN 20 (GUEST -> Cloud 2: zscalerbeta.net .242/.243)
!     Inner Payload: vrf forwarding 20 (iVRF)
!     Outer Header:  VPN 0 (fVRF) pinned via "tunnel route-via Gi1/Gi2 mandatory"
!     Note: L3 GRE "keepalive" is intentionally omitted because iVRF != fVRF
!     (see Section 0.2 #3); tunnel health is monitored every 5s by VRF-aware
!     "ip sla http raw" (/vpntest) + "tunnel route-via ... mandatory".
! ===========================================================================
interface Tunnel21
 description VPN20-Guest-Primary-GE1 (sim: netns gre1 / dev gre21 / port 7000)
 no shutdown
 vrf forwarding 20
 ip address 172.20.67.73 255.255.255.252
 ip mtu 1476
 ip tcp adjust-mss 1436
 tunnel source GigabitEthernet1
 tunnel destination 192.168.1.242
 tunnel mode gre ip
 tunnel route-via GigabitEthernet1 mandatory
!
interface Tunnel22
 description VPN20-Guest-Secondary-GE1 (sim: netns gre2 / dev gre22 / port 7001)
 no shutdown
 vrf forwarding 20
 ip address 172.20.67.77 255.255.255.252
 ip mtu 1476
 ip tcp adjust-mss 1436
 tunnel source GigabitEthernet1
 tunnel destination 192.168.1.243
 tunnel mode gre ip
 tunnel route-via GigabitEthernet1 mandatory
!
interface Tunnel31
 description VPN20-Guest-Primary-GE2 (sim: netns gre1 / dev gre31 / port 7004)
 no shutdown
 vrf forwarding 20
 ip address 172.20.67.65 255.255.255.252
 ip mtu 1476
 ip tcp adjust-mss 1436
 tunnel source GigabitEthernet2
 tunnel destination 192.168.1.242
 tunnel mode gre ip
 tunnel route-via GigabitEthernet2 mandatory
!
interface Tunnel32
 description VPN20-Guest-Secondary-GE2 (sim: netns gre2 / dev gre32 / port 7005)
 no shutdown
 vrf forwarding 20
 ip address 172.20.67.69 255.255.255.252
 ip mtu 1476
 ip tcp adjust-mss 1436
 tunnel source GigabitEthernet2
 tunnel destination 192.168.1.243
 tunnel mode gre ip
 tunnel route-via GigabitEthernet2 mandatory
!

! ===========================================================================
! 5. ALL 8 VRF-AWARE L7 HTTP (/vpntest) IP SLA PROBES & TRACK OBJECTS
!    Syntax Notes (Verified Cisco IOS-XE 17.x):
!    - "http raw url http://<ip> source-ip <ip> cache disable" is the canonical
!      IOS-XE 17.x / config-transaction syntax (interactive CLI also accepts
!      omitting the "url" keyword).
!    - "vrf <id>" is configured under (config-ip-sla-http) before "http-raw-request".
!    - Cisco IP SLA "http raw" supports HTTP/1.0 only; lines inside
!      "http-raw-request" end with \r\n and a blank line (\r\n) before "exit".
! ===========================================================================

! --- Service VPN 10 (Trusted -> gateway.zscaler.net) ---
ip sla 1
 http raw url http://172.21.12.162 source-ip 172.21.12.161 cache disable
 vrf 10
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
 vrf 10
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
 vrf 10
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
 vrf 10
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

! --- Service VPN 20 (Guest -> gateway.zscalerbeta.net) ---
ip sla 21
 http raw url http://172.20.67.74 source-ip 172.20.67.73 cache disable
 vrf 20
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
 vrf 20
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
 vrf 20
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
 vrf 20
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
! 6. TRACKED FLOATING DEFAULT ROUTES (0.0.0.0/0) OVER BOTH ZSCALER CLOUDS
!    - Service VPN 10 (10.23.0.0/24)  -> Cloud 1: zscaler.net (.240 / .241)
!    - Service VPN 20 (172.16.0.0/24) -> Cloud 2: zscalerbeta.net (.242 / .243)
! ===========================================================================
! --- Service VPN 10 Default Routes (zscaler.net) ---
ip route vrf 10 0.0.0.0 0.0.0.0 Tunnel1  172.21.12.162 10 track 1  name ZS-PROD-PRI-GE1
ip route vrf 10 0.0.0.0 0.0.0.0 Tunnel2  172.21.12.166 20 track 2  name ZS-PROD-SEC-GE1
ip route vrf 10 0.0.0.0 0.0.0.0 Tunnel11 172.21.12.154 30 track 11 name ZS-PROD-PRI-GE2
ip route vrf 10 0.0.0.0 0.0.0.0 Tunnel12 172.21.12.158 40 track 12 name ZS-PROD-SEC-GE2

! --- Service VPN 20 Default Routes (zscalerbeta.net) ---
ip route vrf 20 0.0.0.0 0.0.0.0 Tunnel21 172.20.67.74  10 track 21 name ZS-GUEST-PRI-GE1
ip route vrf 20 0.0.0.0 0.0.0.0 Tunnel22 172.20.67.78  20 track 22 name ZS-GUEST-SEC-GE1
ip route vrf 20 0.0.0.0 0.0.0.0 Tunnel31 172.20.67.66  30 track 31 name ZS-GUEST-PRI-GE2
ip route vrf 20 0.0.0.0 0.0.0.0 Tunnel32 172.20.67.70  40 track 32 name ZS-GUEST-SEC-GE2
```

### Alternative for Option 2 (100% Native vManage Feature Template Without CLI Add-On):
If an organization prohibits **CLI Add-On Templates** in vManage and requires 100% GUI Feature Templates for **`cEdge` Option 2**, note that Cisco's native Service-VPN `endpoint-tracker` (`tracker-type static-route`) supports TCP/UDP or ICMP probes (not HTTP URLs). In that case, you can configure TCP Port `80` endpoint trackers natively in the vManage System/VPN Feature Template:
```cisco
! Native vManage GUI Feature-Template Alternative for Option 2 (TCP port 80 probe, IOS-XE 17.7+):
endpoint-tracker ZS-SR-TRACK-1
 tracker-type static-route
 endpoint-ip 172.21.12.162 tcp 80
 interval 20
 threshold 3000
 multiplier 3
exit
track ZS-SR-TRACK-1 endpoint-tracker
ip route vrf 10 0.0.0.0 0.0.0.0 172.21.12.162 10 track name ZS-SR-TRACK-1
```
*(Note: A TCP port `80` probe only verifies the TCP 3-way handshake and RTT, whereas the `ip sla http raw` configuration in Section 5 above verifies the full HTTP `200 OK` status code from `/vpntest` every 5 seconds).*

---

## 4. `cEdge` Verification & Default-Route Failover Testing Commands

*(Ensure the Ubuntu simulator `CONNMARK` and port `80` `DNAT` rules from [`examples/README.md`](README.md#4-common-ubuntu-simulator-preparation-for-cisco-testing) are active before testing).*

```cisco
! 1. Verify all GRE tunnel interfaces and line-protocol status
show ip interface brief | include Tunnel
show interface Tunnel1
show interface Tunnel21

! 2. Verify L7 Health Checks
!    - For Option 1 (native endpoint-tracker + SIG tunnels):
show endpoint-tracker interface
show endpoint-tracker records
show sdwan service sig summaries
show sdwan service sig vrf
show sdwan secure-internet-gateway zscaler tunnels
!    - For Option 2 (VRF-aware IP SLA HTTP raw + Track, or static-route tracker):
show ip sla summary
show ip sla statistics 1
show ip sla statistics 21
show track
show ip route track-table
show endpoint-tracker static-route

! 3. Verify active default routes (0.0.0.0/0) per Service VPN over BOTH Zscaler clouds
!    - VPN 10 should show 0.0.0.0/0 via Tunnel1 (172.21.12.162, AD 10 -> zscaler.net)
!    - VPN 20 should show 0.0.0.0/0 via Tunnel21 (172.20.67.74, AD 10 -> zscalerbeta.net)
show ip route vrf 10 0.0.0.0
show ip route vrf 20 0.0.0.0

! 4. Test inner /30 GRE peer reachability per VRF
ping vrf 10 172.21.12.162
ping vrf 20 172.20.67.74

! 5. Test end-to-end DEFAULT ROUTE (0.0.0.0/0) internet breakout across BOTH Zscaler clouds
ping vrf 10 8.8.8.8 source GigabitEthernet3.950
ping vrf 20 8.8.8.8 source GigabitEthernet3.952
traceroute vrf 10 1.1.1.1 source GigabitEthernet3.950 numeric
traceroute vrf 20 1.1.1.1 source GigabitEthernet3.952 numeric
```

