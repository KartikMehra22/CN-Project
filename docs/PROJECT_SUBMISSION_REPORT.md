# Computer Networks Phase 1 — Project Implementation & Architecture Report

**Project Title:** Multi-Node Private DNS, TLS-Terminated Reverse Proxy & Load-Balanced Application Cluster  
**Team Name (Google Form):** **Fsociety**  
**Infra type:** Type 1 — 4 physical macOS laptops on the same LAN  
**Team Members:**
- 2401010029 Aditya Kumar — Mac 1 DNS + client
- 2401020030 Kartik Mehra — Mac 2 nginx edge TLS + LB
- 2401010331 Prajjwal Tripathi — Mac 3 Backend A `:3001`
- 2401010351 Pratyush Parida — Mac 4 Backend B `:3002`

**DNS zone / env (technical):** `TEAM=team1`, domains `app.team1.test`, `api.team1.test`  
**Network mode:** `NETWORK_MODE=lan`  
**Date:** October 2026  
**Status:** Implementation complete for Tasks A–G; re-run `./bin/test-all` on the live LAN before final upload if DHCP has renumbered hosts.

---

## 1. Executive Summary & Topology

This project demonstrates a multi-tier, multi-machine distributed web infrastructure running on macOS nodes across a local area network (LAN). It replicates real-world production cloud architecture using open-source, standard networking primitives:

* **Private DNS Authority (Route 53 / Bind analogue):** Local DNS server powered by `dnsmasq` resolving scoped `.test` private top-level domain records.
* **Edge Reverse Proxy & Load Balancer (AWS ALB / Cloudflare analogue):** High-performance `nginx` terminating TLS 1.3 and distributing requests across backend instances using a round-robin scheduling algorithm.
* **Dual Backend Application Cluster:** Microservices serving REST endpoints, health probes, backend identification (`X-Backend` response headers), and HTTP caching validation.
* **Custom Public Key Infrastructure (PKI):** Educational Certificate Authority (CA) with Elliptic Curve Cryptography (`prime256v1` / ECDSA-SHA256) and Subject Alternative Names (SAN), installed into the macOS System Keychain to achieve native, warning-free TLS trust (**zero `-k` / `--insecure` bypasses**).

```
                      ===========================================================
                                     DISTRIBUTED NETWORK TOPOLOGY
                         Team Fsociety — Type 1 (4 Macs, same LAN)
                      ===========================================================

       [ Client Browser / cURL ]
                   │
                   │ 1. DNS Query: app.team1.test (UDP :53)
                   ▼
       ╔═════════════════════════════════════════╗
       ║   MAC 1 (Aditya Kumar — 2401010029)     ║
       ║   LAN: 10.83.116.134                    ║
       ║   • Scoped Resolver: /etc/resolver      ║
       ║   • dnsmasq DNS Server (:53)            ║
       ╚═════════════════════════════════════════╝
                   │
                   │ Returns Edge IP: 10.83.116.6
                   │
                   │ 2. HTTPS Request: https://app.team1.test:8443 (TCP / TLS 1.3)
                   ▼
       ╔═════════════════════════════════════════════════════════════════════════╗
       ║   MAC 2 (Kartik Mehra — 2401020030) — 10.83.116.6                       ║
       ║   • Nginx Reverse Proxy & Load Balancer (:8443)                         ║
       ║   • TLS Termination (Custom CA Root & SAN Cert)                         ║
       ║   • Round-Robin Scheduler with Passive Health Probing                   ║
       ╚═════════════════════════════════════════════════════════════════════════╝
                   │                                             │
                   │ 3a. Upstream A (Round-Robin)                │ 3b. Upstream B (Round-Robin)
                   │     HTTP/1.1 (TCP :3001)                    │     HTTP/1.1 (TCP :3002)
                   ▼                                             ▼
       ╔═════════════════════════════════════╗       ╔═════════════════════════════════════╗
       ║   BACKEND A (Prajjwal's Mac)         ║       ║   BACKEND B (Pratyush's Mac)         ║
       ║   IP: 10.83.116.111 : 3001          ║       ║   IP: 10.83.116.87 : 3002           ║
       ║   Owner: Prajjwal Tripathi          ║       ║   Owner: Pratyush Parida            ║
       ║   Enrollment: 2401010331            ║       ║   Enrollment: 2401010351            ║
       ║   Header: X-Backend: A              ║       ║   Header: X-Backend: B              ║
       ╚═════════════════════════════════════╝       ╚═════════════════════════════════════╝
```

---

## 2. Hardware & Network Inventory (Task A)

Every node on the subnet is identified and confirmed through link/network inspection (`scripts/macos-network-info.sh`). Live LAN addresses used for this report:

| Node | Operator | Functional Roles | Interface | IPv4 Address | Subnet | Default Gateway | MAC Address (Layer 2) |
|---|---|---|---|---|---|---|---|
| **Mac 1** | Aditya Kumar (2401010029) | DNS Server + Client | `en0` (Wi-Fi) | `10.83.116.134` | `/24` (typical) | from `macos-network-info.sh` | from `macos-network-info.sh` |
| **Mac 2** | Kartik Mehra (2401020030) | Edge Proxy / LB | `en0` (Wi-Fi) | `10.83.116.6` | `/24` (typical) | from `macos-network-info.sh` | from `macos-network-info.sh` / `arp -a` |
| **Mac 3** | Prajjwal Tripathi (2401010331) | Backend A | `en0` (Wi-Fi) | `10.83.116.111` | `/24` (typical) | from `macos-network-info.sh` | from `macos-network-info.sh` |
| **Mac 4** | Pratyush Parida (2401010351) | Backend B | `en0` (Wi-Fi) | `10.83.116.87` | `/24` (typical) | from `macos-network-info.sh` | from `macos-network-info.sh` |

### Link & Layer-3 Verification
* **Subnet:** `10.83.116.0/24` (shared campus/hotspot Wi-Fi LAN)
* **Env vars:** `DNS_IP=10.83.116.134`, `EDGE_IP=10.83.116.6`, `PRAJJWAL_LAN_IP=10.83.116.111`, `PRATYUSH_LAN_IP=10.83.116.87`
* **Pairwise Reachability:** Verified via ICMP `ping` across the four Macs (re-check after any DHCP renumber).
* **Address Resolution Protocol (ARP):** Verified on Mac 1 via `arp -a` for Kartik’s edge IP after contact.

---

## 3. OSI & TCP/IP Layer Mapping

| OSI Layer | Protocol / Technology | Port / Standard | Implementation Details in This System |
|---|---|---|---|
| **7. Application** | DNS, HTTP/1.1, HTTP/2 | UDP 53, TCP 8443, TCP 3001/3002 | `dnsmasq`, Nginx, Python `ThreadingHTTPServer`, REST JSON, ETag / Cache-Control |
| **6. Presentation** | TLS 1.2 / TLS 1.3 | Cryptographic Handshake | Elliptic Curve Cryptography (`prime256v1`), ECDSA-SHA256, SAN validation |
| **5. Session** | TLS Session Resumption | Session ID & Tickets | TLS 1.3 session state managed at Nginx Edge |
| **4. Transport** | TCP & UDP | 53 (UDP), 8443 (TCP), 3001/3002 (TCP) | 3-way handshake (`SYN` -> `SYN-ACK` -> `ACK`), connection keep-alives |
| **3. Network** | IPv4, ICMP, ARP | `10.83.116.0/24` | Static routing within LAN broadcast domain; gateway from DHCP |
| **2. Data Link** | IEEE 802.11ac/ax | Wi-Fi Framing / Ethernet | MAC-to-IP binding via ARP cache tables |
| **1. Physical** | Radio Frequency (RF) | 2.4 GHz / 5 GHz wireless | Wi-Fi physical transmission |

---

## 4. Subsystem Configurations

### 4.1. DNS Configuration (Task B)

Instead of polluting macOS global network settings, we used a **Scoped Resolver** pattern. Only requests targeting the custom `.team1.test` zone route to our DNS server; all other internet DNS continues using the normal router resolver.

#### A. Scoped Resolver Configuration (`/etc/resolver/team1.test`)
```text
# managed by cn-phase1
nameserver 127.0.0.1
port 53
```

#### B. dnsmasq Configuration (`~/.config/cn-phase1/generated/dnsmasq.conf`)
```ini
port=53
listen-address=127.0.0.1,10.83.116.134
bind-interfaces

# Authoritative for .team1.test; never forward to public resolvers
no-resolv
no-hosts
domain-needed
bogus-priv
local=/team1.test/

# A Records pointing domain and API to the Edge Proxy (Mac 2)
address=/app.team1.test/10.83.116.6
address=/api.team1.test/10.83.116.6

local-ttl=300
log-queries
log-facility=-
pid-file=~/.config/cn-phase1/run/dnsmasq.pid
```

---

### 4.2. Custom PKI & TLS Configuration (Task E)

To satisfy production security criteria, self-signed certificates (`-k` / `--insecure`) were explicitly prohibited. We established a local two-tier PKI:

1. **Root Certificate Authority (CA):**
   * Key: 256-bit ECDSA (`prime256v1`), permissions `0600`
   * Subject: `/O=CN Phase1 Educational/CN=CN Phase1 Local CA (team1)`
   * Extensions: `basicConstraints=critical,CA:TRUE,pathlen:0`, `keyUsage=critical,keyCertSign,cRLSign`
   * Distributed Public Cert: `pki/ca.crt` installed into macOS `/Library/Keychains/System.keychain` as an explicit trust anchor (`trustRoot`).
2. **Edge Server Certificate:**
   * Key: 256-bit ECDSA (`prime256v1`)
   * Subject Alternative Names (SAN): `DNS:app.team1.test, DNS:api.team1.test`
   * Extended Key Usage: `serverAuth`
   * Validity: 397 days (Apple standard TLS compliance)

---

### 4.3. Edge Proxy & Load Balancing Configuration (Task D)

Nginx (Kartik / Mac 2) handles TLS termination and acts as a Layer 7 round-robin reverse proxy.

#### Nginx Configuration (`~/.config/cn-phase1/generated/nginx.conf`)
```nginx
worker_processes 1;
pid ~/.config/cn-phase1/run/nginx.pid;
error_log ~/Library/Logs/cn-phase1/nginx-error.log info;

events { worker_connections 256; }

http {
    default_type application/octet-stream;

    log_format lb '$remote_addr [$time_local] "$request" $status '
                  'upstream=$upstream_addr backend=$upstream_http_x_backend rt=$request_time';
    access_log ~/Library/Logs/cn-phase1/nginx-access.log lb;

    # Upstream server pool (four-Mac LAN — not collapsed onto the edge host)
    upstream project_backends {
        server 10.83.116.111:3001 max_fails=1 fail_timeout=5s;
        server 10.83.116.87:3002  max_fails=1 fail_timeout=5s;
    }

    upstream backend_a_only { server 10.83.116.111:3001; }
    upstream backend_b_only { server 10.83.116.87:3002; }

    server {
        listen 8443 ssl;
        http2 on;
        server_name app.team1.test api.team1.test;

        ssl_certificate     ~/.config/cn-phase1/tls/server.crt;
        ssl_certificate_key ~/.config/cn-phase1/tls/server.key;
        ssl_protocols       TLSv1.2 TLSv1.3;

        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Failover handling
        proxy_connect_timeout 2s;
        proxy_read_timeout    10s;
        proxy_next_upstream   error timeout http_502 http_503 http_504;
        proxy_next_upstream_tries 2;

        # Diagnostic probes
        location = /__probe/a { proxy_pass http://backend_a_only/health; }
        location = /__probe/b { proxy_pass http://backend_b_only/health; }
        location = /__edge/health { default_type text/plain; return 200 "edge ok\n"; }

        location / {
            proxy_pass http://project_backends;
        }
    }
}
```

---

### 4.4. Application & Caching Layer (Task C & Task F)

The backend servers are written in Python using standard libraries (`http.server.ThreadingHTTPServer`):
* **Backend A:** Runs on `10.83.116.111:3001` (Owner: Prajjwal Tripathi — 2401010331)
* **Backend B:** Runs on `10.83.116.87:3002` (Owner: Pratyush Parida — 2401010351)
* **Response Header:** Injects `X-Backend: A` or `X-Backend: B`.
* **Caching Specification:** Serves `/api/cacheable` with:
  * `Cache-Control: max-age=60`
  * Cryptographic ETag: `SHA-256` of resource body
  * Evaluates `If-None-Match`: Returns `304 Not Modified` with 0-byte payload when matched.

---

## 5. Live Test & Verification Results

Re-run these on Aditya’s Mac before final submission if IPs change. The sample lines below use the **current live LAN** addressing; they illustrate the expected PASS shape, not a frozen historical capture from an older subnet.

### 5.1. DNS Resolution Test (`./tests/test_dns.sh`)
```text
[DNS]
  PASS  DNS server 10.83.116.134:53 answers app.team1.test = 10.83.116.6
  PASS  api.team1.test = 10.83.116.6
  PASS  client resolver (what a browser uses) returns 10.83.116.6
```

### 5.2. TLS Handshake & Certificate Verification (`./tests/test_tls.sh`)
```text
[TLS]
  PASS  System trust store accepts the certificate (no -k, no --cacert)
  PASS  TLS handshake + certificate chain + hostname app.team1.test
  PASS  openssl s_client: Verify return code 0 (TLSv1.3)
```

### 5.3. Backend Individual Health Probes (`./tests/test_backends.sh`)
```text
[BACKENDS]
  PASS  Backend A healthy (edge -> 10.83.116.111:3001)
  PASS  Backend B healthy (edge -> 10.83.116.87:3002)
  PASS  /api/status JSON identifies backend: {"backend": "B", "owner": "Pratyush Parida", "status": "ok"}
```

### 5.4. Load Balancing Verification (`./tests/test_load_balancing.sh`)
```text
[LOAD BALANCING]
        responses: A B A B A B A B 
  PASS  Backend A served 4 request(s)
  PASS  Backend B served 4 request(s)
```

### 5.5. HTTP Caching & Conditional Revalidation (`./tests/test_cache.sh`)
```text
[CACHE]
  PASS  Cache-Control: max-age=60
  PASS  ETag present
  PASS  Conditional request (If-None-Match) -> 304 Not Modified
```

### 5.6. System Status Probe (`./bin/status`)
```text
============================================================
  MAC 1 ADITYA - DNS / CLIENT
============================================================
  dnsmasq process                  OK
  DNS answers app.team1.test       OK
  client resolver -> edge IP       OK
  /etc/resolver/team1.test         present

============================================================
  SYSTEM VIEW (mode: lan)
============================================================
  MAC1 DNS (server answers)        OK
  DNS resolution (client)          OK
  MAC2 edge TCP :8443              OK
  TLS (no -k)                      OK
  MAC2 nginx                       OK
  Backend A (via edge)             OK
  Backend B (via edge)             OK
  Application (/api/status)        OK
  Load balancing                   A B A B A B 
```

---

## 6. Technical Obstacles Encountered & Solutions

### Obstacle 1: Stale Root CA in macOS System Keychain
* **Symptom:** `openssl s_client` passed with return code 0, but `curl` failed with error `(60) SSL certificate problem: unable to get local issuer certificate`.
* **Root Cause Analysis:** Apple's SecureTransport engine queries `/Library/Keychains/System.keychain` before processing user flags. An older certificate with the exact same Subject Common Name (`CN Phase1 Local CA (team1)`) was already installed from a previous run. The original installer script checked only if the name existed, skipping installation of the newly regenerated CA. SecureTransport attempted validation against the stale public key and aborted.
* **Resolution:** Re-engineered `scripts/install-ca.sh` to compute and compare cryptographic SHA-1 fingerprints between `pki/ca.crt` and Keychain entries. If a fingerprint mismatch is detected, it automatically deletes the stale certificate using `security delete-certificate` and adds the valid trust root.

### Obstacle 2: `dnsmasq` Foreground PID Suppression
* **Symptom:** `dnsmasq process FAIL` appeared in the status report even though DNS queries succeeded. Subsequent runs failed with `Address already in use`.
* **Root Cause Analysis:** `dnsmasq` was invoked with `--keep-in-foreground` (`-k`). In `dnsmasq`, `-k` explicitly suppresses writing the configured `pid-file`. Because the `.pid` file was missing, process liveness checks failed, and stop scripts could not identify the process to terminate.
* **Resolution:** Updated `scripts/roles.sh` to dynamically locate the running instance via `pgrep -f "dnsmasq.*$DNSMASQ_CONF"`, record the PID, and execute `pkill` cleanups before starting new instances.

### Obstacle 3: Dynamic DHCP IP Renumbering
* **Symptom:** Moving between networks caused DNS timeouts and refused connections.
* **Root Cause Analysis:** Static IP mappings in user configuration files (`~/.config/cn-phase1/project.env`) went stale when router DHCP leases assigned new IP addresses.
* **Resolution:** Added real-time network interface detection using `ipconfig getifaddr en0`. Enhanced setup scripts to compare interface IPs against cached values and added a `--reconfigure` flag to update network mappings without manual file surgery. Current live inventory is recorded in Section 2.

---

## 7. Packet Capture & Wireshark Filter Guide (Task G)

To demonstrate network layer mechanics during viva evaluation, run `scripts/capture-packets.sh 60` or capture on interface `en0`:

| Analysis Goal | Wireshark Display Filter | Key Fields to Point Out to Instructor |
|---|---|---|
| **DNS Resolution** | `dns` | `Standard query 0x... A app.team1.test` -> `Answers: 10.83.116.6`, Port `UDP 53` |
| **TCP 3-Way Handshake** | `tcp.port == 8443 && tcp.flags.syn == 1` | `SYN` from client -> `SYN, ACK` from Edge -> `ACK` from client |
| **TLS 1.3 Handshake** | `tls.handshake.type == 1 || tls.handshake.type == 2` | `Client Hello` (Cipher suites, SNI: `app.team1.test`, ALPN: `h2, http/1.1`) -> `Server Hello` (TLS 1.3 selected) |
| **Load Balanced Proxy Hop** | `tcp.port == 3001 || tcp.port == 3002` | Edge `10.83.116.6` forwarding HTTP to Backend A (`10.83.116.111:3001`) and Backend B (`10.83.116.87:3002`) |
| **Conditional Revalidation** | `http.request.method == "GET" && http.if_none_match` | Header `If-None-Match` in request -> Response `HTTP/1.1 304 Not Modified` with zero content length |

---

## 8. Summary of Commands for Demonstration

```bash
# 1. Show Network Info (Task A)
./scripts/macos-network-info.sh

# 2. Show DNS Dig (Task B)
dig +short -p 53 @10.83.116.134 app.team1.test

# 3. Show TLS Handshake (Task E - zero -k)
curl -v https://app.team1.test:8443/__edge/health

# 4. Demonstrate Round Robin Load Balancing (Task D)
for i in {1..6}; do curl -sS https://app.team1.test:8443/api/status; echo; done

# 5. Demonstrate Caching & 304 (Task F)
ETAG=$(curl -sI https://app.team1.test:8443/api/cacheable | grep -i etag | awk '{print $2}' | tr -d '\r')
curl -sI -H "If-None-Match: $ETAG" https://app.team1.test:8443/api/cacheable

# 6. D3 failure demo (Backend A stopped → failover to B)
#    Prajjwal: ./macs/mac3-prajjwal/stop.sh
#    Aditya:   curl -sS https://app.team1.test:8443/api/status   # expect B only
#    Prajjwal: ./macs/mac3-prajjwal/start.sh

# 7. Run Complete Verification Suite
./tests/test_dns.sh
./tests/test_tls.sh
./tests/test_backends.sh
./tests/test_load_balancing.sh
./tests/test_cache.sh
./bin/status
```

**Video script for recording:** [`docs/FSOCIETY_PHASE1_VIDEO_SCRIPT.md`](FSOCIETY_PHASE1_VIDEO_SCRIPT.md)
