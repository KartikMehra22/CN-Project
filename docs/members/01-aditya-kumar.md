# Mac 1: Aditya Kumar (DNS server, test client, controller)

**Address:** 10.100.147.63 (en0, /24, gateway 10.100.147.169)  |  **Port:** 53/udp+tcp  |  **Software:** dnsmasq, dig

## 1. Your job in one paragraph

You are the **first hop**. Before anything else happens, the client asks your dnsmasq "where is `app.team1.test`?" and you answer with Kartik's edge IP, never a backend IP. You are also the **controller**: you run the test suite, the doctor, the evidence collection and most of the Phase 2 demos (A, B, E, F) from your Mac.

## 2. Your files (know what each does)

| File | What it does |
|---|---|
| `macs/mac1-aditya/setup.sh` | One command: installs dnsmasq, builds the config, starts DNS, installs the scoped resolver |
| `config/dns/dnsmasq.conf.template` | Template for the dnsmasq config (rendered to `~/.config/cn-phase1/generated/dnsmasq.conf`) |
| `scripts/roles.sh` (`dns_*`, `resolver_install`) | Start/stop dnsmasq, write `/etc/resolver/team1.test` |
| `scripts/configure-client-dns.sh` | What the other Macs run to use your DNS |
| `scripts/phase2.sh`, `bin/phase2` | Phase 2 demos: `dns-failover`, `ttl`, `cutover`, `point`, `watch`, `drill` |
| `bin/test-all`, `bin/doctor`, `bin/collect-evidence` | Layered tests, first-failing-layer diagnosis, evidence snapshot |

The generated config (`evidence/2026-11-24-011204/dnsmasq.conf.generated`) is worth reading line by line:
- `local=/team1.test/` + `no-resolv`: we answer for our zone only and never forward to the internet.
- `address=/app.team1.test/10.100.147.77` and the same for `api`: both names point at the **edge**.
- `local-ttl=300`: clients may cache the answer for 5 minutes.
- `log-queries`: every query is logged (`dnsmasq-log-tail.txt`).

## 3. Commands you run

```bash
./macs/mac1-aditya/setup.sh                 # Phase 1 setup (then calls phase2 setup)
./bin/phase2 setup                          # Phase 2: resolver lists primary + backup DNS
./bin/test-all                              # PASS/FAIL per layer
./bin/doctor                                # first failing layer
./bin/phase2 test | tee evidence/phase2/$(date +%Y%m%d-%H%M%S)-test.txt
./bin/phase2 dns-failover                   # Extension A
./bin/phase2 ttl                            # Extension B
./bin/phase2 cutover                        # Extension E (other Mac: ./bin/phase2 watch)
./bin/phase2 drill   ->  ./bin/doctor  ->  ./bin/phase2 drill reveal / fix     # Extension F
./bin/collect-evidence                      # snapshot into evidence/<timestamp>/
```

## 4. Your evidence (what each file proves)

| File | Proves |
|---|---|
| `evidence/2026-11-24-011204/network-info.txt` | Your interface, IP/prefix, gateway, MAC |
| `.../dns.txt` | Both names answer 10.100.147.77, `aa` flag, TTL 300 |
| `.../resolver.txt` | Scoped resolver with two nameservers |
| `.../dnsmasq.conf.generated`, `dnsmasq-log-tail.txt` | The config and real queries |
| `evidence/phase2/20261124-010052-dns-failover.txt` | **A:** primary stopped, `dig` timed out, backup answered, HTTPS still 200 |
| `evidence/phase2/20261124-010304-ttl.txt` | **B:** TTL 30 s, client kept old IP ~40 s, flush was instant |
| `evidence/phase2/20261124-010924-cutover.txt` | **E:** client moved to the standby edge at t+41 s |
| `evidence/phase2/20261124-010027-test.txt` | `phase2 test`: A to F summary |

## 5. What you must understand (likely questions)

- **What does DNS do, and which port/protocol?** Turns a name into an IP. UDP port 53 (TCP for large answers).
- **Resolver vs record?** The resolver is the client-side setting that says *who to ask* (`/etc/resolver/team1.test`). The record is the answer (`app.team1.test A 10.100.147.77`).
- **Why a scoped resolver file?** Only `*.team1.test` goes to us; the Mac's normal internet DNS is untouched and no System Settings edit is needed.
- **Why does `dig` differ from what `curl` sees?** `dig` always asks the server; `curl` uses the OS resolver, which caches. That is exactly what Extension B shows.
- **What is TTL?** How long a client may reuse an answer without asking again. Ours is 300 s, 30 s in the demo.
- **DNS failure vs application failure?** DNS failure: the name does not resolve. Application failure: the name resolves fine, then the service answers 502 or refuses.
- **Why is the backup DNS on Kartik's Mac?** The brief says the backup must not be Mac 1, and that Mac already has Homebrew and admin rights. Both servers render from the **same template**, so records match by construction.
- **Why did the client keep the old IP in Extension B/E?** It cached the answer; the TTL is the worst-case time users keep hitting the old server.
- **Safe migration order?** Lower the TTL first, change the record, wait one old TTL, raise it again.
- **After a real cutover?** Run `./bin/phase2 point standby` on both DNS Macs so the primary and backup agree.

## 6. When things go wrong

| Symptom | Likely cause | First command |
|---|---|---|
| `address already in use` on :53 | Another DNS service | `sudo lsof -nP -iUDP:53` |
| Client cannot resolve | dnsmasq stopped or resolver file missing | `dig @10.100.147.63 app.team1.test`, `cat /etc/resolver/team1.test` |
| Certificate error | CA not trusted | `git pull`, then `scripts/install-ca.sh` |
| DHCP changed your IP | DNS_IP in settings is stale | update `DNS_IP`, re-run setup |
| `collect-evidence` crash on empty array | fixed in this repo (bash 3.2) | `git pull` |

## 7. Your remaining evidence tasks

- [ ] Task A: ping matrix to Macs 2, 3, 4 and a topology screenshot
- [ ] Task B: a second client Mac using your DNS (ask Pratush)
- [ ] Task G: `scripts/capture-packets.sh 60` while running `curl`, then Wireshark screenshots (`dns`, `tcp.flags.syn==1`, `tls.handshake.type==1`)
- [ ] Extension C: run `./bin/phase2 isolate test` from your Mac as the **client** (expected: blocked)
- [ ] Extension E: coordinate with a teammate to save `./bin/phase2 watch` output during `cutover`
- [ ] Extension F: record one `drill` with the `doctor` output
