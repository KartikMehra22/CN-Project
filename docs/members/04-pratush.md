# Mac 4: Pratush (Backend B, standby edge, second client)

**Address:** 10.100.147.95  |  **Ports:** 3002/tcp (Backend B) and 8443/tcp (standby nginx)  |  **Software:** Python 3, nginx

## 1. Your job in one paragraph

You do three things. You run **Backend B**, identical to Prajwal's with a different identity. In Phase 2 you also run the **standby nginx** (Extension E): a second copy of the edge, with the same certificate, ready to take over if Kartik's Mac dies. And you are the **second test client**, proving that more than one machine can use Aditya's DNS.

## 2. Your files

| File | What it does |
|---|---|
| `macs/mac4-pratush/setup.sh` / `start.sh` / `stop.sh` / `status.sh` | Set up, start, stop and check your roles |
| `backends/server.py` | Backend code, run with `BACKEND_ID=B BACKEND_OWNER=Pratush PORT=3002` |
| `scripts/phase2.sh` (`p2_bundle_import`) | Installs the standby: decrypts the bundle, verifies it, starts nginx on 8443 |
| `scripts/phase2.sh` (`p2_iso_on`, `p2_iso_off`) | Firewall for Extension C |
| `scripts/configure-client-dns.sh` | Makes your Mac a DNS client of Aditya's server |

## 3. Commands you run

```bash
./macs/mac4-pratush/setup.sh                # Backend B (once)
scripts/configure-client-dns.sh             # use Aditya's DNS as a client
scripts/install-ca.sh                       # trust the project CA
# AirDrop Kartik's ~/cn-edge-bundle.enc to ~/Downloads, get the passphrase from him
./bin/phase2 setup                          # imports the bundle, starts the STANDBY nginx, arms the firewall
./bin/phase2 test                           # A to F checks (expect E to pass for the standby)
./bin/phase2 isolate on | off               # Extension C on your backend
./bin/phase2 watch                          # run on your Mac as a client during the cutover
curl -sI https://10.100.147.95:8443/ --cacert pki/ca.crt --resolve app.team1.test:8443:10.100.147.95   # try the standby directly
```

## 4. Your evidence

| File | Proves |
|---|---|
| `evidence/2026-11-24-011204/load-balancing.txt` | You are the `B` in `A B A B A B A B A B` |
| `evidence/phase2/20261124-010027-test.txt` | `STANDBY edge 10.100.147.95 healthy (same site, same certificate)` and the two edges are distinguishable (`X-Edge: Kartik-ka-MacBook-Pro` / `Pratyushs-MacBook-Pro-3`) |
| `evidence/phase2/20261124-010924-cutover.txt` | **E:** record moved to your IP; at t+41 s the client was answered by `Pratyushs-MacBook-Pro-3` |
| `evidence/phase2/20261124-010304-ttl.txt` | During B the record temporarily pointed at your IP (10.100.147.95) to show the client's cache |

## 5. What you must understand (likely questions)

- **What is the standby edge?** A second nginx with the same rendered config and the **same certificate**, running on your Mac. It is idle until DNS points at it.
- **Why can the certificate be reused on another IP?** A certificate binds **names** (the SANs `app.team1.test`, `api.team1.test`), not IP addresses.
- **What travels in the bundle?** Only `server.crt` and `server.key`, passphrase-encrypted. The **CA private key never leaves Kartik's Mac**.
- **What does your setup refuse to install?** Anything not signed by `pki/ca.crt`, lacking the SAN, or whose key does not match the certificate.
- **How do we know which edge answered?** Each edge adds an `X-Edge` header with its own label.
- **What does a DNS cutover do?** Changes the A record from the old edge to yours. New lookups go to you immediately; clients holding a cached answer keep going to the old edge until the TTL expires. In our run: 30 s TTL, switched at ~41 s.
- **Why is the cutover not instant or automatic?** It is bounded by the TTL and manual. True high availability needs a floating IP shared by two edges (VRRP/keepalived) or DNS health checks that move the record by themselves.
- **Why do you appear in two roles at once?** Backend B (3002) and standby nginx (8443) listen on different ports on the same Mac. The firewall has `pass on lo0` so same-Mac traffic still works.
- **Why is your Mac on the firewall allow list as an edge?** After a cutover you are the machine talking to both backends, so you must be allowed to reach ports 3001 and 3002.
- **Client vs server?** A client only asks (DNS lookups, HTTPS requests). Servers listen on a port and answer. You are both a server (B, standby) and a client (resolver).

## 6. When things go wrong

| Symptom | Likely cause | First command |
|---|---|---|
| Standby setup says bundle not found | AirDrop file not in `~/Downloads` | check `ls ~/Downloads/cn-edge-bundle.enc` |
| Bundle refused | Wrong passphrase, or cert not signed by `pki/ca.crt` | re-export on Kartik's Mac, `git pull` for the latest `pki/ca.crt` |
| Port 8443 or 3002 in use | Another process | `lsof -nP -iTCP:8443`, `lsof -nP -iTCP:3002` |
| `cutover` pre-check fails on the standby | Standby not running | `./bin/phase2 start` or `./bin/phase2 setup` on your Mac |
| Cannot reach backends after cutover | Firewall allow list missing your IP | `sudo pfctl -a cn-phase2 -sr` |

## 7. Your remaining evidence tasks

- [ ] **Extension E, client view:** run `./bin/phase2 watch 2>&1 | tee evidence/phase2/$(date +%Y%m%d-%H%M%S)-watch.txt` on your Mac while Aditya runs `./bin/phase2 cutover`. Send the file to Aditya.
- [ ] **Task B, second client:** run `scripts/configure-client-dns.sh`, then save `dig app.team1.test` and `curl -sS https://app.team1.test:8443/api/status` (no `-k`).
- [ ] **Extension C:** with Prajwal, run `./bin/phase2 isolate on` on your Mac and save `sudo pfctl -a cn-phase2 -sr`, then `isolate off`.
- [ ] Run `./bin/collect-evidence` on your Mac and keep `listening-ports.txt` (`:3002` and `:8443` both listening).
