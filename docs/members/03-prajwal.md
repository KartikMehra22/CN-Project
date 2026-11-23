# Mac 3: Prajwal (Backend A, and the firewall demo)

**Address:** 10.100.147.229  |  **Port:** 3001/tcp  |  **Software:** Python 3 (standard library only)

## 1. Your job in one paragraph

You run **Backend A**, the last hop. nginx sends you plain HTTP; you answer with JSON and a header `X-Backend: A` that proves which server handled the request. Your Mac also takes part in two Phase 2 demos: **Extension D** (the demo stops and restarts you to prove the service survives) and **Extension C** (you turn on a firewall so only the edge can reach port 3001).

## 2. Your files

| File | What it does |
|---|---|
| `macs/mac3-prajwal/setup.sh` / `start.sh` / `stop.sh` / `status.sh` | Set up, start, stop and check your backend |
| `backends/server.py` | The whole application (identical to Backend B, only the environment differs) |
| `scripts/role.sh` | Starts the backend with `BACKEND_ID=A BACKEND_OWNER=Prajwal PORT=3001 BIND=0.0.0.0` |
| `scripts/phase2.sh` (`p2_iso_on`, `p2_iso_off`) | The pf firewall rules for Extension C |

What `server.py` serves (read it, it is short):

| Path | Response | Why it exists |
|---|---|---|
| `/` | small HTML page | human check |
| `/api/status` | `{"backend":"A","owner":"Prajwal","status":"ok"}`, `Cache-Control: no-store` | proves which backend answered |
| `/health` | `200 ok` | health probes |
| `/api/cacheable` | `Cache-Control: max-age=60` + `ETag`; **304** when `If-None-Match` matches | the caching task |

Every response carries `X-Backend: A`. The `/api/cacheable` body is **identical on A and B**, so the ETag matches on both and a conditional request still gets 304 even if nginx picks the other backend.

## 3. Commands you run

```bash
./macs/mac3-prajwal/setup.sh                # Phase 1 setup (once)
./macs/mac3-prajwal/start.sh                # start (also: ./bin/start)
./macs/mac3-prajwal/stop.sh                 # stop (Extension D asks you to do this)
./bin/phase2 setup                          # arms the backend firewall (paste the line Aditya's Mac prints)
./bin/phase2 isolate on                     # Extension C: only edges may connect
./bin/phase2 isolate off                    # undo; original firewall restored
./bin/status
curl -i http://10.100.147.229:3001/api/status          # from your own Mac
```

## 4. Your evidence

| File | Proves |
|---|---|
| `evidence/2026-11-24-011204/curl-verbose.txt`, `headers.txt` | `x-backend: A` through the edge |
| `evidence/2026-11-24-011204/cache.txt` | `cache-control: max-age=60`, `etag`, conditional request **304** |
| `evidence/phase2/20261124-010556-failover.txt` | Step 2: you stopped A, service continued on B only (`B B B B B B B B B B`, all HTTP 200). Step 4: you restarted A and `A B A B A B A B` returned |
| `evidence/phase2/20261124-010027-test.txt` | Before isolation: `Backend A 10.100.147.229:3001 direct connect: yes, allowed to: no -> NOT ISOLATED` |

**Timing note.** The "27 s" and "11 s" in the failover transcript include the time it took you to run stop and start. Do not quote them as failover speed. Say: "requests kept returning 200 the whole time".

## 5. What you must understand (likely questions)

- **`0.0.0.0` vs `127.0.0.1`?** `127.0.0.1` accepts only connections from the same Mac. `0.0.0.0` listens on every interface, so nginx on another Mac can reach you. That is why we bind `0.0.0.0` (`BIND` in `server.py`).
- **Why a different port from Backend B?** Both are in one project; 3001 for A and 3002 for B keeps them distinct when roles share a Mac.
- **What is `X-Backend` for?** A label so we can *see* the load balancing without reading logs.
- **Cache-Control vs ETag vs 304?** `max-age=60` says "reuse for 60 s without asking". After that the client sends `If-None-Match: <etag>`; if unchanged, the server answers **304 Not Modified** with no body.
- **Why is `/api/status` `no-store`?** It is live status, so it must never be cached.
- **What happens when you stop?** nginx gets a connection error, marks A failed for 5 s, retries on B in the same request. Users see no error. When you return, A rejoins after `fail_timeout`.
- **What does the firewall do (Extension C)?** A pf rule set in a separate **anchor** `cn-phase2` allows only the edge and the standby edge to reach 3001; all others are **dropped** (they time out, not refused). `/etc/pf.conf` is never edited; `isolate off` flushes the anchor and reloads the original, and a reboot clears it too.
- **Why is the standby edge on the allow list?** After a cutover (Extension E) the standby is the machine talking to the backends. Allowing only the primary would break the failover we built.
- **Why the rules are checked first:** they are validated with `pfctl -n` before anything is touched, and a copy of the live rules is saved to `~/.config/cn-phase1/backups/`.

## 6. When things go wrong

| Symptom | Likely cause | First command |
|---|---|---|
| Port 3001 in use | Another process | `lsof -nP -iTCP:3001` |
| Edge shows Backend A "down" | Not started, wrong IP, or firewall prompt blocked python3 | `./bin/status`, allow python3 in the macOS firewall prompt |
| Nothing reaches you after `isolate on` | Edge IP not on the allow list | `sudo pfctl -a cn-phase2 -sr`, then `./bin/phase2 isolate off` |
| Left in a strange state | A demo was interrupted | `./bin/phase2 rollback` |

## 7. Your remaining evidence tasks (this is the biggest gap in the project)

- [ ] **Extension C is not yet demonstrated.** Run `./bin/phase2 isolate on`, then show `sudo pfctl -a cn-phase2 -sr` (screenshot). Ask Kartik to run `isolate test` from the edge (expect reachable) and Aditya from a client (expect blocked/timeout). Then `./bin/phase2 isolate off` and `isolate test` again (expect not isolated).
- [ ] Save `./bin/phase2 status` output while isolation is on.
- [ ] Run `./bin/collect-evidence` on your Mac and keep `listening-ports.txt` (shows `:3001` listening on `*`).
