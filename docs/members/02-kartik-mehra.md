# Mac 2: Kartik Mehra (edge: TLS, reverse proxy, load balancer, backup DNS)

**Address:** 10.100.147.77  |  **Port:** 8443/tcp (also 53 for the backup DNS)  |  **Software:** nginx, openssl, dnsmasq

## 1. Your job in one paragraph

You run the **front door**. Every client connects to you. You terminate TLS with a certificate signed by our own CA, then forward each HTTP request to Backend A or B in turn, and retry on the other if one fails. In Phase 2 you also host the **backup DNS** (Extension A) and you create the encrypted certificate bundle for Pratush's standby edge (Extension E). You are also the only Mac holding the **CA private key**, and it never leaves your Mac.

## 2. Your files

| File | What it does |
|---|---|
| `macs/mac2-kartik/setup.sh` | Installs nginx, creates the CA and server certificate, starts the edge |
| `config/nginx/nginx.conf.template` | The nginx config (rendered to `~/.config/cn-phase1/generated/nginx.conf`) |
| `scripts/create-local-ca.sh` | Creates the local CA and the `app.team1.test` certificate with SANs |
| `scripts/install-ca.sh` | What every client runs to trust the CA (`pki/ca.crt`, public) |
| `scripts/phase2.sh` (`p2_bundle_export`) | Packs `server.crt` + `server.key` into `~/cn-edge-bundle.enc` (passphrase-encrypted) |
| `~/.config/cn-phase1/tls/` | **Private** keys. Never commit, never send |

Read the nginx template. The lines you must be able to explain:
- `upstream project_backends { server A max_fails=1 fail_timeout=5s; server B ...; }` is the backend group. Default policy is **round robin**.
- `listen 8443 ssl; http2 on; ssl_protocols TLSv1.2 TLSv1.3;` is TLS termination.
- `proxy_next_upstream error timeout http_502 http_503 http_504; proxy_next_upstream_tries 2;` is passive failover (Extension D).
- `add_header X-Edge "<label>"` shows which edge answered (proves primary vs standby in Extension E).
- `location / { proxy_pass http://project_backends; }` is the reverse proxy.
- `/__probe/a`, `/__probe/b`, `/__edge/health` are diagnostic probes that let a remote client test each backend through the edge.

## 3. Commands you run

```bash
./macs/mac2-kartik/setup.sh                 # Phase 1: nginx + CA + cert (once)
git add pki/ca.crt && git commit && git push   # publish the PUBLIC CA only (to staging)
./bin/phase2 setup                          # Phase 2: starts backup DNS, writes ~/cn-edge-bundle.enc, prints its passphrase
./bin/status                                # whole-system view
./bin/phase2 isolate test                   # Extension C, run from the edge: expect "reachable"
./bin/collect-evidence                      # run on YOUR Mac too (see section 7)
```

Hand the bundle to Pratush by AirDrop and give him the passphrase separately.

## 4. Your evidence

| File | Proves |
|---|---|
| `evidence/2026-11-24-011204/tls.txt` | Chain: leaf `CN=app.team1.test` issued by `CN Phase1 Local CA (team1)`, EC P-256, valid to 25 Dec 2027, SANs `app` + `api`, TLS 1.3, `Verify return code: 0 (ok)` |
| `.../curl-verbose.txt` | HTTPS by name, HTTP/2 200, **no `-k`**, `x-backend`, `x-edge: Kartik-ka-MacBook-Pro` |
| `.../load-balancing.txt` | `A B A B A B A B A B` |
| `.../headers.txt`, `cache.txt` | `cache-control: max-age=60`, `etag`, then a **304** on the repeat |
| `evidence/phase2/20261124-010052-dns-failover.txt` | Your backup DNS (10.100.147.77) answered while the primary was stopped |
| `evidence/phase2/20261124-010556-failover.txt` | nginx routed around Backend A: only B, all 200, then A B A B again |
| `evidence/phase2/20261124-010924-cutover.txt` | Primary edge identified as `Kartik-ka-MacBook-Pro` |

## 5. What you must understand (likely questions)

- **TCP vs TLS handshake?** TCP: SYN, SYN-ACK, ACK (a connection). Then TLS: ClientHello, ServerHello + certificate, key exchange, encrypted data.
- **What does the certificate prove?** That the server owns the name. It is valid only if a CA the client trusts signed it, the name matches a **SAN**, and it has not expired.
- **Why our own CA?** `.test` names cannot get a public certificate. We create a CA, and clients install only the public `ca.crt`. We never use `curl -k`.
- **Why is the CA private key never copied?** Whoever has it can issue certificates for any name. Only `server.crt` and `server.key` travel to the standby.
- **Reverse proxy vs forward proxy?** A reverse proxy sits in front of servers on behalf of the servers (clients never see backend IPs). A forward proxy sits in front of clients.
- **What is TLS termination?** TLS ends at nginx; nginx talks plain HTTP to the backends inside the LAN.
- **Round robin?** Requests go A, B, A, B in order.
- **How does failover work?** `max_fails=1 fail_timeout=5s` marks a failed backend down for 5 s. `proxy_next_upstream` retries the same request on the other one, so the user sees no error. It is **passive**: nginx open source has no active health checks, and that is enough here.
- **What if both backends fail?** The edge is up but returns `502 Bad Gateway`.
- **What is still a single point of failure?** **You**: the edge nginx. Fix: a floating IP shared by two edges (VRRP/keepalived) or health-checked DNS. Extension E is the manual version.
- **Why does the standby certificate work on another IP?** A certificate binds **names**, not IPs.
- **Certificate dates:** the server cert is valid until Dec 2027; the CA until 2029. After that, regenerate.

## 6. When things go wrong

| Symptom | Likely cause | First command |
|---|---|---|
| `bind() failed` | Port 8443 in use | `lsof -nP -iTCP:8443` |
| 502 for every request | Both backends down or unreachable | `curl -i https://app.team1.test:8443/__probe/a` and `/__probe/b` |
| Clients say certificate untrusted | CA not installed, or CA regenerated | `scripts/install-ca.sh`, check `pki/ca.crt` was pushed |
| Wrong SAN / expired | Cert replaced | `openssl s_client -connect 10.100.147.77:8443 -servername app.team1.test -CAfile pki/ca.crt` |
| Config error | Bad template value | `nginx -t` (run automatically), `tail ~/Library/Logs/cn-phase1/nginx-error.log` |

## 7. Your remaining evidence tasks

- [ ] Run `./bin/collect-evidence` **on your Mac**. It adds `nginx-t.txt`, `nginx.conf.generated` and `nginx-access-tail.txt`, which prove the edge side and show the chosen backend per request.
- [ ] Save a screenshot of `tail ~/Library/Logs/cn-phase1/nginx-access.log` during the failover demo (shows `upstream=` and `backend=`).
- [ ] Extension C: run `./bin/phase2 isolate test` on your Mac after Prajwal and Pratush turn isolation on. Expected: both backends reachable.
- [ ] Make sure the latest `pki/ca.crt` is on `staging` and every client trusts it.
