# Viva guide

Each block: **What / Why / Where / Protocol+port / Packet flow / If it fails / Proof.**

## DNS server (dnsmasq)
* **What**: a name->IP directory. **Why**: clients use names, not IPs; one record change re-points traffic. **Where**: Mac 1. **Protocol**: DNS over UDP (TCP for large answers) port 53.
* **Flow**: client (ephemeral src port) -> Mac 1:53 "A app.team1.test?" -> answer with Mac 2's IP and a TTL.
* **Fails**: lookups fail, but `ping <ip>` and `curl --resolve` still work - DNS is independent of IP connectivity. **Proof**: `dig @<DNS_IP> app.team1.test`, `tests/test_dns.sh`, `tcpdump`/Wireshark filter `dns`.

## Nginx edge (reverse proxy + TLS termination + load balancer)
* **What**: one public entry point that terminates TLS and forwards requests. **Why**: clients need only one name; backends stay private and interchangeable. **Where**: Mac 2, TCP 8443.
* **Flow**: accepts TCP+TLS from the client, opens a *separate* HTTP connection to A or B, relays the response.
* **Fails**: everything behind it is unreachable even if backends are healthy (single point of failure). **Proof**: `curl -v`, `./bin/status`, nginx access log (`upstream=` and `backend=`).

## Backends
* **What**: identical Python REST servers. **Why**: give the LB two targets; `X-Backend` makes distribution visible. **Where**: Mac 3 (3001), Mac 4 (3002). **Port**: bound to `0.0.0.0` (reachable off-machine); `127.0.0.1` would be reachable only locally.
* **Fails**: with one down, nginx marks it failed (`max_fails=1`, `fail_timeout=5s`) and retries on the other; both down -> `502`. **Proof**: stop one and run `./bin/test-all`.

## TLS / CA
* **Certificate** binds a public key to a name; the **CA** is the trusted signer. Our local CA's certificate is installed in each client's trust store; the server certificate carries SANs `app.team1.test`, `api.team1.test`. **Termination**: TLS ends at nginx; nginx->backend is plain HTTP.
* **Handshake** (TLS 1.3): ClientHello (SNI, key share) -> ServerHello + Certificate + Finished -> client Finished -> encrypted HTTP. (TLS 1.2 adds explicit ServerKeyExchange/ChangeCipherSpec.)
* **Fails**: untrusted CA/wrong SAN/expired -> curl exit 60, browser warning. **Proof**: `openssl s_client`, `curl -v` (no `-k`).

## Concept Q&A
* **Resolver vs record**: the resolver is the machine/software that asks and caches (macOS, `/etc/resolver`); a record is the stored answer (`app.team1.test A <ip>`) on the DNS server.
* **IP vs port**: IP picks the host; port picks the process on it. `ping` proves the IP; `nc -vz ip port` proves the port.
* **TCP handshake**: SYN, SYN-ACK, ACK - establishes sequence numbers; reliability comes from sequence/ack numbers, retransmission, flow control.
* **Ephemeral ports**: the OS picks a high random source port (49152-65535) per connection; the socket pair (src ip, src port, dst ip, dst port) identifies it.
* **HTTP vs HTTPS**: HTTPS is HTTP inside TLS: confidentiality, integrity, server authentication. That is why Wireshark shows "Application Data".
* **Reverse vs forward proxy**: reverse proxy sits in front of servers on behalf of *servers* (nginx here); forward proxy sits in front of clients.
* **Load balancing / round robin**: requests alternate A,B,A,B; alternatives: `least_conn`, `ip_hash`. **Upstream**: nginx's named group of backend servers.
* **localhost vs 0.0.0.0**: 127.0.0.1 = loopback only; 0.0.0.0 = all interfaces, so other Macs can connect.
* **Cache-Control / ETag / 304**: `max-age=60` lets clients reuse a response for 60 s without asking (fresh hit); after that, `If-None-Match: <etag>` revalidates and the server answers `304` with no body; otherwise a full `200`.
* **DNS TTL**: how long resolvers may cache an answer; changes propagate only after TTL expiry (Extension B).
* **Cloudflare tunnel**: `cloudflared` opens *outbound* connections to Cloudflare; WARP on the edge sends traffic for `10.250.0.x` into Cloudflare, which delivers it through the tunnel to the backend Mac. It is an **overlay**: virtual IPs on top of the internet.
* **LAN vs overlay tunnel**: LAN = one broadcast domain, direct frames/ARP, no third party; overlay = encapsulated over other networks, extra latency, extra trust in the provider, virtual addressing. Hence tunnel mode changes the topology and is only for remote demo.
* **Why can the client not see backend IPs**: nginx terminates the client connection and makes its own upstream connection; only nginx knows the upstream list.

## Phase 2 Q&A
* **DNS failure vs application failure**: DNS failure = names stop resolving (a backup resolver hides it); application failure = the name resolves and the TCP/TLS path works, then the service answers 502 or refuses. `dig` works in both; `curl` tells them apart.
* **Why does the client keep the old IP after a record change?** The resolver cache may keep an answer for its TTL. `dig` always asks the server, so it shows the new value at once; the OS resolver (what browsers/curl use) does not until the TTL ends or the cache is flushed.
* **How do you migrate traffic safely with DNS?** Lower the TTL, wait one old TTL, change the record, watch both servers, then raise the TTL. The TTL bounds how long users reach the old server.
* **Why pf rules by source IP, and why the standby in the allow-list?** The backend cannot trust a client's claims, only its source address; the edge is the only legitimate caller. After a cutover the standby is the caller, so it must be allowed too.
* **Passive vs active health checks**: passive (nginx OSS) learns from real failed requests and retries on the other upstream in the same request; active probes in the background (nginx Plus, HAProxy). Passive is enough here, at the cost of one retried request.
* **Remaining single point of failure and the fix**: the edge nginx. Fix: two edges sharing a floating IP (VRRP/keepalived), or health-checked DNS failover; Extension E is the manual, TTL-bounded version.
* **Why can the standby use the same certificate?** A certificate binds a public key to *names*; the standby serves the same names. The CA key stays on the edge; only the server certificate and key move, encrypted.
* **How do you diagnose a fault you did not cause?** Layer by layer: name resolution -> TCP -> TLS -> application; first failing layer wins; `bin/doctor` automates it.
