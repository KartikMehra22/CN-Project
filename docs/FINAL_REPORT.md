# CN Private Network Service Platform: Final Report (Phase 1 + Phase 2)

**Team:** FSOCIETY  |  **Zone:** `team1.test`  |  **Mode:** LAN (all four Macs on one private network)  |  **Evidence collected:** 24 Nov 2026

Every claim below cites the evidence file it comes from, with the path relative to the repository root.
Anything not yet backed by a file is marked **PENDING** (see section 7). Nothing is claimed without proof.

---

## 1. Summary

| Area | Result | Evidence |
|---|---|---|
| Phase 1: DNS, TCP, TLS, load balancing, caching | All layers healthy | `evidence/2026-11-24-011204/doctor.txt` |
| Ext. A: backup DNS | Demonstrated | `evidence/phase2/20261124-010052-dns-failover.txt` |
| Ext. B: TTL and cache | Demonstrated | `evidence/phase2/20261124-010304-ttl.txt` |
| Ext. C: backend isolation | **PENDING**: only a "not isolated" baseline exists | `evidence/phase2/20261124-010027-test.txt` |
| Ext. D: HA failover | Demonstrated | `evidence/phase2/20261124-010556-failover.txt` |
| Ext. E: edge cutover | Demonstrated | `evidence/phase2/20261124-010924-cutover.txt` |
| Ext. F: troubleshooting | Doctor run recorded; random drill **PENDING** | `evidence/2026-11-24-011204/doctor.txt` |
| Phase 1 Task G: packet capture | **PENDING** | none |

## 2. Topology and roles

| Mac | Person | Role | Address | Port |
|---|---|---|---|---|
| 1 | Aditya Kumar | Primary DNS (dnsmasq) + controller + test client | 10.100.147.63 | 53/udp+tcp |
| 2 | Kartik Mehra | Edge: nginx, TLS termination, round-robin load balancer. Also **backup DNS** (Phase 2) | 10.100.147.77 | 8443/tcp |
| 3 | Prajwal | Backend A (Python REST) | 10.100.147.229 | 3001/tcp |
| 4 | Pratush | Backend B (same code, other config). Also **standby nginx** (Phase 2) | 10.100.147.95 | 3002/tcp |

Request path: client asks DNS for `app.team1.test`, gets the edge IP, opens TCP and TLS to the edge on 8443, and nginx forwards the HTTP request alternately to Backend A or B.

Source for the addresses: `evidence/2026-11-24-011204/network-info.txt` (Mac 1), `dnsmasq.conf.generated` (records), `evidence/phase2/20261124-010027-test.txt` (all four IPs).

## 3. Evidence index

| File | What it proves |
|---|---|
| `evidence/2026-11-24-011204/network-info.txt` | Mac 1 interface `en0`, IPv4 10.100.147.63, /24, gateway 10.100.147.169, MAC 8a:bb:9d:37:23:03 |
| `.../resolver.txt` | Scoped resolver for `team1.test` lists two nameservers (127.0.0.1 and 10.100.147.77) |
| `.../dns.txt` | `dig` and `nslookup` for `app` and `api` return 10.100.147.77, TTL 300 |
| `.../dnsmasq.conf.generated` | The exact dnsmasq config in use (authoritative-only zone, two A records, `local-ttl=300`) |
| `.../dnsmasq-log-tail.txt` | Query log (100 lines): clients actually querying our server |
| `.../tls.txt` | Certificate chain, SAN names, TLS 1.3, `Verify return code: 0 (ok)` |
| `.../curl-verbose.txt` | HTTPS request by name, HTTP/2 200, `x-backend` and `x-edge` headers, no `-k` |
| `.../headers.txt` | `cache-control: max-age=60` and `etag` on `/api/cacheable` |
| `.../cache.txt` | Headers plus `conditional request status: 304` |
| `.../load-balancing.txt` | `A B A B A B A B A B` across ten requests |
| `.../service-status.txt` | Every system-view check `OK` |
| `.../doctor.txt` | 11 layers `PASS` |
| `evidence/phase2/20261124-010027-test.txt` | `phase2 test`: checks A to F, including the Ext. C baseline |
| `evidence/phase2/20261124-010052-dns-failover.txt` | Ext. A transcript |
| `evidence/phase2/20261124-010304-ttl.txt` | Ext. B transcript |
| `evidence/phase2/20261124-010556-failover.txt` | Ext. D transcript |
| `evidence/phase2/20261124-010924-cutover.txt` | Ext. E transcript |

The three earlier folders `evidence/2026-11-24-011049`, `-011134` and `-011143` are partial runs (network, resolver and DNS only) and are superseded by `-011204`.

---

## 4. Phase 1

### Task A: LAN and addressing
Mac 1 shows `en0`, 10.100.147.63/24, gateway 10.100.147.169 (`network-info.txt`). **PENDING:** the same output from Macs 2 to 4, a pairwise ping matrix and the topology screenshot.

### Task B: Private DNS
- dnsmasq on Mac 1 is authoritative for `team1.test` only (`local=/team1.test/`, `no-resolv`), so it never forwards to the internet (`dnsmasq.conf.generated`).
- `app.team1.test` and `api.team1.test` both answer **10.100.147.77**, the edge, never a backend, with `aa` (authoritative) and TTL 300 (`dns.txt`).
- Clients use a scoped resolver file `/etc/resolver/team1.test`, so only our zone goes to our server (`resolver.txt`).
- The query log shows the edge itself querying our DNS (`dnsmasq-log-tail.txt`).
- Note: a second client Mac using Mac 1 for DNS is not separately evidenced (**PENDING**).

### Task C: Backends
Both backends answer through the edge and label themselves with `x-backend: A` or `B` (`curl-verbose.txt`, `headers.txt`). Direct reachability of ports 3001 and 3002 from the LAN is shown in the Ext. C baseline: `direct connect: yes` for both (`evidence/phase2/20261124-010027-test.txt`).

### Task D: Edge and load balancing
Ten consecutive requests returned `A B A B A B A B A B` (`load-balancing.txt`). The same alternation appears in `service-status.txt` and in the Phase 2 transcripts. This is nginx round robin over `10.100.147.229:3001` and `10.100.147.95:3002`.

### Task E: TLS with our own CA
- Chain: leaf `CN=app.team1.test`, issued by `CN=CN Phase1 Local CA (team1)` (`tls.txt`).
- Leaf key is EC prime256v1, signed with ECDSA-SHA256, valid 23 Nov 2026 to 25 Dec 2027, with SANs `app.team1.test` and `api.team1.test`.
- Result: `TLSv1.3`, cipher `TLS_AES_256_GCM_SHA384`, `Verification: OK`, `Verify return code: 0 (ok)`.
- The HTTPS request in `curl-verbose.txt` succeeded without `-k`, because the CA was installed in the trust store.

### Task F: HTTP caching
`/api/cacheable` returns `cache-control: max-age=60` and an `etag` (`headers.txt`). A repeat request with that ETag returns **304** (`cache.txt`). `/api/status` returns `cache-control: no-store` (`curl-verbose.txt`), which shows the two endpoints are cached differently on purpose.

### Task G: Packet capture
**PENDING.** Run `scripts/capture-packets.sh 60` and add the Wireshark screenshots. Filters to use: `dns`, `tcp.flags.syn==1`, `tls.handshake.type==1`, `tcp.port==8443`.

### Overall health check
`doctor.txt` reports `PASS` for local network, DNS, TCP edge, TLS, nginx/edge, Backend A, Backend B, Cloudflare (WARP), backup DNS, standby edge and HTTP/application, then "All layers healthy".

---

## 5. Phase 2: Harden, Recover, Troubleshoot

Setup is one command on every Mac, `./bin/phase2 setup`. It adds a backup DNS on Mac 2, a standby nginx on Mac 4 and a pf firewall on the backend Macs. Phase 1 is unchanged underneath. `phase2 test` run result (`evidence/phase2/20261124-010027-test.txt`): PASS for A (3 checks), B, D, E (3 checks) and F; WARN for C (isolation not yet turned on).

### Extension A: Backup DNS
**Idea.** DNS is a single point of failure, so a second dnsmasq on Mac 2 serves identical records.
**Evidence** (`20261124-010052-dns-failover.txt`):
1. Resolver lists both servers; both answer `app.team1.test A 10.100.147.77`.
2. With the primary up: `dns=0.002445s http=200`.
3. Primary stopped: `dig` to 10.100.147.63 gives `connection timed out; no servers could be reached`; the backup still answers 10.100.147.77.
4. Client still resolves and HTTPS still answers `http=200` (`dns=0.002271s`).
5. Primary restored and answering again.

**Takeaway.** A DNS failure stops name resolution; an application failure resolves and then returns 502 or refuses. The backup hid the DNS failure from users.

### Extension B: TTL and cache
**Idea.** TTL is how long a client may keep a DNS answer without asking again.
**Evidence** (`20261124-010304-ttl.txt`):
1. TTL lowered from 300 to 30 s.
2. Record changed 10.100.147.77 to 10.100.147.95. The server (`dig`, never cached) answered the new IP at once; the client (OS resolver) kept 10.100.147.77.
3. The client polled every 3 s and stayed on the old IP until `t+40s`, then switched to 10.100.147.95 ("~40 s, TTL 30 s").
4. A manual flush (`dscacheutil -flushcache; killall -HUP mDNSResponder`) changed it immediately.
5. Record restored to 10.100.147.77, TTL 300.

**Takeaway.** For a migration: lower the TTL first, change the record, wait one old TTL, then raise it.

### Extension C: Backend isolation (firewall)
**Idea.** Only the edge (and the standby edge) should reach ports 3001 and 3002. Rules live in a pf anchor `cn-phase2`, `/etc/pf.conf` is untouched, and blocked packets are dropped.
**Evidence so far:** the baseline before isolation, from Mac 1 (`20261124-010027-test.txt`): Backend A `direct connect: yes, allowed to: no -> NOT ISOLATED`; Backend B likewise; "Through the edge (the intended path): works".
**PENDING:** the actual demo. Run `./bin/phase2 isolate on` on Macs 3 and 4, `./bin/phase2 isolate test` on the edge and then on a client, then `./bin/phase2 isolate off`. Expected: edge open, client blocked, original firewall restored. This section must be updated with that transcript.

### Extension D: High-availability failover
**Idea.** If one backend dies, nginx (`max_fails=1 fail_timeout=5s`, `proxy_next_upstream`) retries on the other inside the same request.
**Evidence** (`20261124-010556-failover.txt`):
1. Healthy: `B A B A B A B A`.
2. Backend A stopped on Mac 3.
3. Service continues on B only: `B B B B B B B B B B`, three `GET /api/status -> HTTP 200`.
4. Backend A restarted: load balancing resumed, `A B A B A B A B`.

**Timing note.** The "27 s" and "11 s" printed by the demo are the waits for the person on Mac 3 to stop or start the backend and for nginx to notice, so they include operator time. They are not a pure failover time. What the transcript proves is that requests kept returning 200 throughout.
**Single point of failure:** the edge nginx on Mac 2. Removing it needs a floating IP shared by two edges (VRRP/keepalived) or health-checked DNS.

### Extension E: Edge migration (DNS cutover)
**Idea.** A standby nginx on Mac 4 carries the same certificate (a certificate binds names, not IPs). Only the DNS record moves. The CA private key never leaves Mac 2.
**Evidence** (`20261124-010924-cutover.txt`):
1. Pre-check: primary edge 10.100.147.77 answers `X-Edge: Kartik-ka-MacBook-Pro`; standby 10.100.147.95 answers `X-Edge: Pratyushs-MacBook-Pro-3`.
2. Record switched to the standby with TTL 30 s. The server (`dig`) showed 10.100.147.95 immediately, but the client and the answering edge stayed on the old one until `t+41s`.
3. At `t+41s`: client 10.100.147.95, answered by `Pratyushs-MacBook-Pro-3`. Result `PASS: traffic moved to the standby edge`.
4. Switched back to the primary edge at the end.

**Takeaway.** Cached clients keep using the old edge until their TTL expires; new lookups go to the standby at once. After a permanent cutover, run `./bin/phase2 point standby` on both DNS Macs so they agree.

### Extension F: Troubleshooting
**Method.** Test in order: name resolution, TCP, TLS, application. `./bin/doctor` runs that chain and prints the first failing layer, why it fails, and the commands to confirm.
**Evidence:** `doctor.txt` with all 11 layers `PASS`. **PENDING:** a recorded random drill (`./bin/phase2 drill`, diagnose with `./bin/doctor`, then `drill reveal` and `drill fix`).

| Fault | Layer | First command |
|---|---|---|
| Wrong or old DNS record, dnsmasq stopped | DNS | `dig @10.100.147.63 app.team1.test` |
| nginx stopped, wrong port, firewall rule | TCP | `nc -vz 10.100.147.77 8443` |
| Certificate swapped, expired or wrong SAN | TLS | `openssl s_client -connect 10.100.147.77:8443 -servername app.team1.test -CAfile pki/ca.crt` |
| Backend stopped or wrong upstream | Application | `curl -i https://app.team1.test:8443/api/status` |

---

## 6. Limits we state ourselves

1. The edge nginx on Mac 2 is still a single point of failure (DNS no longer is).
2. Backup DNS is not auto-synced: a record change must be applied on both DNS Macs.
3. Cutover is manual and bounded by the TTL; true HA needs a floating IP or health-checked DNS.
4. Phase 2 is LAN mode only, because firewall rules by source IP mean nothing through a Cloudflare tunnel.

## 7. Outstanding evidence (to finish before submission)

- [ ] Task A: network info from Macs 2 to 4, pairwise ping matrix, topology screenshot
- [ ] Task B: a second client Mac resolving through Mac 1
- [ ] Task G: `scripts/capture-packets.sh 60` plus Wireshark screenshots (DNS, TCP handshake, TLS handshake)
- [ ] Ext. C: `isolate on`, `isolate test` (edge, then client), `isolate off` transcripts
- [ ] Ext. E: `./bin/phase2 watch` output from a client Mac during the cutover
- [ ] Ext. F: one recorded `drill` with `doctor` output, then `drill reveal` and `drill fix`

## 8. How to reproduce

```bash
./bin/test-all                       # Phase 1, layer by layer
./bin/doctor                         # first failing layer, or all healthy
./bin/phase2 test                    # checks A to F, non-destructive
./bin/phase2 dns-failover            # A  (Mac 1)
./bin/phase2 ttl                     # B  (Mac 1)
./bin/phase2 isolate on|test|off     # C  (backend Macs / edge / client)
./bin/phase2 failover                # D  (anywhere)
./bin/phase2 cutover                 # E  (Mac 1); ./bin/phase2 watch on a client
./bin/phase2 drill                   # F  (rehearsal)
./bin/collect-evidence               # Phase 1 snapshot into evidence/<timestamp>/
```

Demo transcripts are written automatically to `evidence/phase2/` and each demo restores the system when it ends.
