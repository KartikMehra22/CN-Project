# Phase 2 - Harden, Recover, Troubleshoot

Brief, Section 7: Extensions A-F. Same network as Phase 1 (nothing rebuilt); one new command, `bin/phase2`.
**LAN mode only** - the brief requires one shared LAN, and firewall rules by source IP mean nothing through the Cloudflare tunnel.

## Setup: one command per Mac

Every Mac runs the **same** command. It reads the IP table and works out *by its own IP* what it is responsible for, so it works with 4 Macs or with combined roles on 2-3 Macs. It is idempotent.

| Order | Who | Command | What it does |
|---|---|---|---|
| 1 | Vaibhav (edge, Mac 2) | `git pull && ./bin/phase2 setup` | starts the **backup DNS**; writes `~/cn-edge-bundle.enc` and prints its passphrase |
| 2 | Akshat (Mac 4) | AirDrop the bundle, then `./bin/phase2 setup` | starts the **standby nginx** (bundle is found in `~/Downloads`, asks the passphrase); arms the backend firewall |
| 3 | Mitul (Mac 1) | `./bin/phase2 setup` | resolver now lists primary + backup; prints a copy-paste line for the others |
| 4 | Hardik (Mac 3) | paste the line Mitul's Mac printed | arms the backend firewall |
| 5 | anyone | `./bin/phase2 test` | PASS/FAIL for A-E, non-destructive |

The Phase 1 commands (`./macs/<mac>/setup.sh`) now call this at the end too, so people who already know that command do not need to remember a second one.
After a reboot: `./bin/start` (it restarts the Phase 2 services as well). Undo everything: `./bin/phase2 rollback`.

**With fewer Macs** (e.g. Mitul = DNS + Backend B, Hardik = edge + Backend A): the defaults still hold - backup DNS goes to the edge Mac (Hardik), the standby edge to the Backend-B Mac (Mitul). Override with `DNS2_IP=` / `STANDBY_EDGE_IP=` in `~/.config/cn-phase1/project.env`.

## What to run for each extension

| Ext | Brief asks for | Command (where) | You will see |
|---|---|---|---|
| A | backup DNS; stop primary; clients keep resolving | `bin/phase2 dns-failover` (Mitul) | primary `dig` times out, backup answers, `curl` still works |
| B | short TTL; change record; stale cache; flush | `bin/phase2 ttl` (Mitul) | server answers new IP at once, client keeps old one until TTL ends, flush is instant |
| C | only the edge reaches 3001/3002; rollback | `bin/phase2 isolate on` (each backend Mac), `isolate test` (edge, then a client), `isolate off` | edge: open; client: blocked; original firewall restored |
| D | stop A, B serves, restart A, LB resumes; name the SPOF | `bin/phase2 failover` (anywhere) | only `B`, all HTTP 200; both back within ~6 s |
| E | standby nginx; DNS cutover; TTL effects | `bin/phase2 cutover` (Mitul); `bin/phase2 watch` on a client | old edge answers until TTL expiry, then the standby (`X-Edge` header) |
| F | fault injected by faculty; diagnose layer by layer | `bin/doctor`; rehearse with `bin/phase2 drill` | first failing layer + the commands to confirm it |

Every demo saves a colour-free transcript to `evidence/phase2/` (Evidence Folder deliverable) and **puts the system back** when it ends or on Ctrl-C.

## Why it is built this way

**A - Backup DNS.** A second `dnsmasq` from the *same template* on the edge Mac, so the records are identical by construction (two lines; there is nothing to replicate). The edge Mac is the default because it already has Homebrew and admin rights (the brief requires both for the DNS and edge machines) and it is not Mac 1, as required. Clients use the scoped `/etc/resolver/team1.test` with two `nameserver` lines: ordered, reversible, and no System Settings edits. *Explain:* a **DNS failure** stops name resolution (here masked by the backup); an **application failure** resolves fine and then returns 502/refuses. Expect a short delay on the first lookup after the outage (the resolver waits out the first server before trying the second); after that the answer is cached for its TTL.

**B - TTL.** `local-ttl` stamps both records; Phase 1 uses 300 s, the demo drops to 30 s (`DEMO_TTL`) and restores. `dig` always asks the server, so it can never show caching; the demo therefore also queries through the **OS resolver** (`dscacheutil`), which is what browsers and `curl` use. The script prints what it *measured* - if the OS did not cache, it says so rather than claiming it did. *Explain:* for a migration lower the TTL **first**, change the record, wait one old TTL, then raise it; the TTL is the worst-case time users keep hitting the old server.

**C - Isolation.** Rules live in a pf **anchor** (`cn-phase2`); `/etc/pf.conf` is never edited. Turning it on loads the system ruleset plus one anchor line; turning it off flushes the anchor and reloads the original, and a reboot clears it anyway. `pfctl -E`/`-X` tokens mean we never disable a firewall someone else had enabled. The allow-list is **edge + standby edge**: after an Extension E cutover the standby is the machine talking to the backends, so allowing only the primary would break the very failover we built. `pass on lo0` keeps same-Mac traffic working (nginx and a backend on one Mac). Disallowed packets are **dropped** (timeout), not refused, as a real firewall does. The rules are validated with `pfctl -n` before anything is touched, and a copy of the live rules is saved to `~/.config/cn-phase1/backups/`.

**D - HA failover.** Already in the nginx config: `max_fails=1 fail_timeout=5s`, `proxy_next_upstream error timeout 502-504`, 2 s connect timeout. nginx open source has only *passive* checks; that is enough because a failed attempt is retried on the other backend inside the same request, so the user sees no error. A recovered backend rejoins after `fail_timeout`. **Single point of failure: the edge nginx on Mac 2** (DNS is no longer one, thanks to A). Removing it needs automatic takeover - a floating IP shared by two edges (VRRP/keepalived) or DNS health checks that move the record by themselves. Extension E is the manual version of that.

**E - Edge migration.** The standby runs the same rendered nginx config and the **same certificate** (a certificate binds *names*, not IPs, so it is valid on any host). Only `server.crt`+`server.key` travel, in a passphrase-encrypted bundle; the **CA private key never leaves the edge**. The standby refuses to install anything not signed by `pki/ca.crt`, lacking the SAN, or whose key does not match. Each edge stamps an `X-Edge` header so the demo can show *which* edge answered. The cutover changes the DNS record only; clients holding the old answer keep using the old edge until the TTL expires, new lookups go to the standby at once. After a real cutover run `bin/phase2 point standby` on **both** DNS Macs so primary and backup agree.

**F - Troubleshooting.** Method = the brief's order: name resolution -> TCP -> TLS -> application. `bin/doctor` runs exactly that chain and prints the first failing layer, why it breaks, and the commands to confirm. Phase 2 adds two redundancy layers (backup DNS, standby edge) *after* the live path so the first failure shown is still the one a user would feel. Likely faculty faults:

| Fault | Layer | First command |
|---|---|---|
| wrong/old DNS record, dnsmasq stopped, wrong resolver | DNS | `dig @<DNS_IP> app.team1.test`, `cat /etc/resolver/team1.test` |
| nginx stopped, wrong port, firewall rule | TCP | `nc -vz <EDGE_IP> 8443`, `sudo pfctl -a cn-phase2 -sr` |
| certificate swapped/expired/wrong SAN, CA not trusted | TLS | `openssl s_client -connect <EDGE_IP>:8443 -servername app.team1.test -CAfile pki/ca.crt` |
| backend stopped / returning errors / wrong upstream | application | `curl -i https://app.team1.test:8443/api/status`, `tail ~/Library/Logs/cn-phase1/nginx-error.log` |

Rehearse without a teacher: `bin/phase2 drill` injects one random, reversible fault on your Mac without saying which; diagnose with `bin/doctor`; `drill reveal` / `drill fix`.

## Limits (say them before you are asked)
* Backup DNS is not auto-synced: a record change must be applied on both DNS Macs (`bin/phase2 point ...`). Real systems use zone transfer or a managed DNS service.
* Cutover is manual and bounded by the TTL; true HA needs a floating IP or health-checked DNS (see D).
* pf and the OS DNS cache are macOS behaviours; run the demos once on the real Macs before the evaluation and keep the transcripts in `evidence/phase2/`.
