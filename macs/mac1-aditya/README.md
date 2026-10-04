# Mac 1 - Aditya Kumar (2401010029) - DNS server, controller, test client

**Setup (once, idempotent):** `./macs/mac1-aditya/setup.sh`   |   **Start:** `./macs/mac1-aditya/start.sh` (or `./bin/start`)   |   **Stop:** `./macs/mac1-aditya/stop.sh`   |   **Status:** `./macs/mac1-aditya/status.sh` (or `./bin/status`)

**Software installed:** Homebrew, dnsmasq, dig (bind tools if missing); public CA in System keychain
**Ports:** 53 udp/tcp (dnsmasq)
**Logs:** `~/Library/Logs/cn-phase1/` (dnsmasq.log)
**Settings:** `~/.config/cn-phase1/project.env` (created by setup)

## Role in the request flow
First hop: the client asks Aditya's dnsmasq for `app.team1.test` and gets Kartik's IP. Aditya also runs `./bin/test-all`, `doctor`, `collect-evidence`. A scoped resolver file `/etc/resolver/team1.test` makes macOS use it for `.test` only.

## Common errors
* `address already in use` on :53 -> another DNS service (`sudo lsof -nP -iUDP:53`).
* Certificate errors -> `git pull` then `scripts/install-ca.sh`.
* DHCP changed your IP -> update `DNS_IP`, re-run setup.
* Undo everything: `./bin/teardown`.

## Explain in the viva
Resolver vs record, UDP/53, TTL and caching, why `dig` differs from what curl uses, DNS != IP connectivity, DNS service failure vs application failure.
