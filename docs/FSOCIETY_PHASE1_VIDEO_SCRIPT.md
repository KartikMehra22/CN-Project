# Fsociety — Phase 1 Demo Video Script (Speak-Aloud)

> **Canonical recording script.** Older `docs/PHASE1_VIDEO_DEMO_SCRIPT.md` is superseded (AEIN / stale IPs).

**Team name:** Fsociety  
**Infra type:** Type 1 — 4 physical macOS laptops on the same LAN  
**Suggested Drive filename:** `CN_Phase1_Fsociety_Type1.mp4`  
**Max duration:** 5:00 (target finish by ~4:50)  
**Primary Mac for screen share:** Aditya (Mac 1) — DNS + client  
**Live env (reference IPs only; access always by domain name):**

| Role | Person | Enrollment | LAN IP | Ports |
|---|---|---|---|---|
| Mac 1 — DNS + client | Aditya Kumar | 2401010029 | 10.83.116.134 | 53 |
| Mac 2 — nginx edge TLS + LB | Kartik Mehra | 2401020030 | 10.83.116.6 | 8443 |
| Mac 3 — Backend A | Prajjwal Tripathi | 2401010331 | 10.83.116.111 | 3001 |
| Mac 4 — Backend B | Pratyush Parida | 2401010351 | 10.83.116.87 | 3002 |

**Domains (use these in every demo command):**
- `https://app.team1.test:8443`
- `https://api.team1.test:8443`

**Mode:** `TEAM=team1`, `NETWORK_MODE=lan`  
**Rules:** No `curl -k`. Never open the app by IP. Show real terminal output.

---

## Google Form field helper (names / enrollment)

Paste exactly:

```
2401010029 Aditya Kumar
2401020030 Kartik Mehra
2401010331 Prajjwal Tripathi
2401010351 Pratyush Parida
```

---

## What is D3? (form requirement)

Per `docs/FAILURE_DEMOS.md` and `bin/failure-demo`, the project’s numbered failure table is:

| # | Scenario |
|---|---|
| 1 | Wrong DNS server on a client (`wrong-resolver`) |
| 2 | DNS record points to wrong IP (`wrong-dns-record`) |
| **3 = D3** | **Backend A stopped — nginx passive failover to Backend B** |
| 4 | Both backends stopped → 502 |
| 5 | Wrong destination port (`wrong-port`) |

**D3 (this video’s required failure demo):** stop Backend A on Prajjwal’s Mac; show that HTTPS by name still works and every `/api/status` response comes from Backend **B**; then restart Backend A.  
**Concept proved:** reverse-proxy passive health checks / `proxy_next_upstream` failover — DNS, TCP, and TLS to the edge stay healthy; only the upstream path changes.

---

## Master timeline (strict 5 minutes)

| Clock | Segment | Focus |
|---|---|---|
| **0:00 – 2:00** | **1. Team intro + setup flow** | Names/roles, LAN topology, `./bin/status` all green |
| **2:00 – 4:00** | **2. How configuration is working** | DNS `dig`, TLS/HTTP/2 `curl -v` (no `-k`), LB A/B, brief OSI/request flow |
| **4:00 – 5:00** | **3. Section 5 failure — D3** | Stop Backend A → observe all-B → explain → rollback |

---

## Pre-recording checklist (do before you hit Record)

1. All four Macs on the **same Wi-Fi/LAN**; `NETWORK_MODE=lan` saved in `~/.config/cn-phase1/project.env`.
2. Start order already done; services up:
   - Prajjwal / Pratyush: backends running  
   - Kartik: nginx on `:8443`  
   - Aditya: dnsmasq + scoped resolver  
3. On **Aditya (Mac 1)** — recording machine:
   ```bash
   cd /Users/adityainnovates/Downloads/cn_project-main   # or your clone path
   sudo -v          # cache sudo so prompts don’t interrupt
   ./bin/status     # DNS OK, TLS OK, nginx OK, Backend A/B OK, LB alternating
   ```
4. Browser once: open `https://app.team1.test:8443/` — padlock / trusted (CA in System keychain). **No IP URLs.**
5. Terminal: font **16–18 pt**, window maximized or large; `clear` right before recording.
6. Prajjwal stays near Mac 3 (or shares a second terminal window) ready to run stop/start for D3.
7. Optional safety: `./bin/failure-demo backend-a explain` once so everyone knows the words (do **not** leave a broken state).

---

# 🎬 Speak-aloud script

Camera tip for the whole video: **one continuous screen share of Aditya’s terminal** (large font). Switch to browser only once (~10 s) if you want a visual padlock; otherwise stay in terminal. Zoom so `OK` / `A` / `B` / HTTP status lines are readable.

---

## SEGMENT 1 — Team intro + setup flow (0:00 – 2:00)

### [0:00 – 0:50] Team & architecture intro

**Show on screen:** Aditya Mac 1 — repo root in Terminal (optional: small slide/notes with team name; not required).

**🎙️ Say:**

> “Hi — this is our Computer Networks Phase 1 demo. We are team **Fsociety**.  
> Infra type one: **four physical MacBooks on the same LAN**.  
> I’m **Aditya Kumar**, enrollment **2401010029**, on Mac one — private DNS with dnsmasq, plus the test client.  
> **Kartik Mehra**, **2401020030**, is Mac two — nginx edge: TLS termination, reverse proxy, and round-robin load balancing on port eighty-four forty-three.  
> **Prajjwal Tripathi**, **2401010331**, is Mac three — Backend A on port three thousand one.  
> **Pratyush Parida**, **2401010351**, is Mac four — Backend B on port three thousand two.  
> Clients never talk to backends by IP. They use domain names: **app.team1.test** and **api.team1.test**, over HTTPS on port eighty-four forty-three.”

**Expected cues:** Presenter faces camera or voice-over; no commands yet.

---

### [0:50 – 1:20] LAN addressing (Task A)

**Show on screen:** Aditya Mac 1 terminal.

**Run:**

```bash
./scripts/macos-network-info.sh
```

**🎙️ Say:**

> “First, Task A — LAN addressing. This script prints our interface, IP, prefix, gateway, and MAC.  
> We’re on the shared Wi-Fi LAN. Aditya’s DNS Mac is at ten-dot-eighty-three-dot-one-sixteen-dot-one-thirty-four; Kartik’s edge is ten-dot-eighty-three-dot-one-sixteen-dot-six; Prajjwal and Pratyush are also on that same subnet.  
> Pairwise reachability was verified earlier with ping. For the rest of the demo, we access services **only by domain name**, never by typing those IPs into curl or the browser.”

**Expected output cues:** Interface (e.g. `en0`), IPv4, `/24` (or similar), gateway, MAC address lines visible.

**Tip:** Leave this output on screen ~5 seconds so IPs are readable, then clear.

```bash
clear
```

---

### [1:20 – 2:00] Whole-system status (setup flow proof)

**Show on screen:** Aditya Mac 1 terminal.

**Run:**

```bash
./bin/status
```

**🎙️ Say:**

> “This is our post-setup health check — `./bin/status`. It makes real requests, not just process greps.  
> You should see: DNS server OK, client DNS resolution OK, edge TCP on eighty-four forty-three OK, **TLS OK without dash-k**, nginx OK, Backend A OK, Backend B OK, application OK, and load balancing alternating — for example B A B A B A.  
> That means the full path is live: scoped DNS to Aditya, TLS to Kartik’s edge, and HTTP upstreams to both backends.”

**Expected output cues:** Rows show `OK` for DNS, TLS, nginx, Backend A/B; Load balancing line shows a mix of `A` and `B` (e.g. `B A B A B A`).

**Tip:** Pause ~8 seconds with the green OK rows visible. Do **not** scroll past the load-balancing line before you finish speaking.

```bash
clear
```

---

## SEGMENT 2 — How configuration is working (2:00 – 4:00)

### [2:00 – 2:35] Scoped DNS by domain name

**Show on screen:** Aditya Mac 1 terminal.

**Run (one block, or line-by-line):**

```bash
cat /etc/resolver/team1.test
```

```bash
dig @127.0.0.1 +noall +answer app.team1.test
```

```bash
dig @127.0.0.1 +noall +answer api.team1.test
```

**🎙️ Say:**

> “Configuration layer one — DNS.  
> macOS scoped resolver file `/etc/resolver/team1.test` sends only the `team1.test` zone to our private DNS — here, loopback to Aditya’s dnsmasq. We are **not** hijacking all system DNS.  
> `dig` for **app.team1.test** and **api.team1.test** returns A records pointing at Kartik’s edge IP.  
> Important: DNS only answers ‘which IP.’ Nothing is connected yet — that’s OSI application naming before transport.”

**Expected output cues:**
- Resolver file shows nameserver (e.g. `127.0.0.1` or DNS IP).
- `dig` ANSWER section shows A record → `10.83.116.6` (Kartik).

**Tip:** Keep `dig` answer lines fully visible; do not use IP in the spoken URL.

---

### [2:35 – 3:15] TLS 1.3 + HTTP/2 by domain (no `-k`)

**Show on screen:** Aditya Mac 1 terminal. Optional ~8 s browser cutaway to `https://app.team1.test:8443/` showing trusted lock.

**Run:**

```bash
curl -v https://app.team1.test:8443/__edge/health 2>&1 | grep -E '(ALPN|SSL connection|HTTP/2|subject:|issuer:)'
```

**🎙️ Say:**

> “Layer two — transport security.  
> We curl **https://app.team1.test:8443** — domain name only, **no curl dash-k**.  
> Because our private Root CA is trusted in the macOS System keychain, the handshake succeeds.  
> Watch for TLS one-point-three, ALPN negotiating HTTP/two, and a successful HTTP/two response from the edge health endpoint.  
> Following the request flow: after DNS, the client does TCP to Kartik on eighty-four forty-three, then TLS with SNI `app.team1.test`, certificate SAN check, then HTTP inside the encrypted channel.”

**Expected output cues:** Lines mentioning `TLSv1.3` / `SSL connection`, `ALPN: h2` (or HTTP/2), and an HTTP/2 response (e.g. `HTTP/2 200`).

**If grep is too quiet, fallback (still no `-k`):**

```bash
curl -v https://app.team1.test:8443/__edge/health
```

Scroll to highlight TLS / ALPN / HTTP/2 lines, then Ctrl+C is not needed — command ends on its own.

---

### [3:15 – 3:45] Load balancing `/api/status` (A / B)

**Show on screen:** Aditya Mac 1 terminal.

**Run:**

```bash
for i in 1 2 3 4 5 6; do curl -sS https://app.team1.test:8443/api/status; echo; done
```

**🎙️ Say:**

> “Layer three — reverse proxy and load balancing.  
> Six requests to **https://app.team1.test:8443/api/status**.  
> nginx on Kartik terminates TLS, then opens a new plain HTTP hop to Backend A or Backend B in round robin. The client never sees Prajjwal’s or Pratyush’s IPs.  
> You should see JSON alternating backends — A and B — via the backend identity in the response.”

**Expected output cues:** Alternating `"backend":"A"` / `"backend":"B"` (or `X-Backend` / letter fields as your JSON prints). Pattern like B, A, B, A, B, A is fine.

**Optional one-liner if time is tight instead of the loop:**

```bash
./tests/test_load_balancing.sh
```

**🎙️ (if using test script):**

> “Our automated load-balancing test confirms both A and B served at least one request.”

---

### [3:45 – 4:00] Quick system confirmation + flow wrap

**Show on screen:** Aditya Mac 1 terminal.

**Run (pick one; prefer `status` if the loop already showed LB):**

```bash
./bin/status
```

**🎙️ Say:**

> “Quick recap of the happy path: DNS name to edge IP, TCP and TLS to Kartik, HTTP to `/api/status`, nginx round-robins to A and B.  
> Next we break one upstream on purpose — Section five failure demo **D3**.”

**Expected cues:** Still all OK / mixed A and B before the failure segment.

```bash
clear
```

---

## SEGMENT 3 — Section 5 failure demonstration **(D3)** (4:00 – 5:00)

> **D3 = Backend A stopped → passive failover to Backend B.**  
> Break on **Prajjwal Mac 3**; observe on **Aditya Mac 1**.

### [4:00 – 4:15] Break Backend A

**Show on screen:** Prefer split: Prajjwal’s terminal running stop (or Aditya narrating while Prajjwal runs it). If only one screen: Aditya runs the remote-instructed command via spoken cue, then Aditya observes.

**On Prajjwal (Mac 3) — exact commands:**

```bash
cd ~/cn_project-main   # or your clone path
./macs/mac3-prajjwal/stop.sh
```

**Equivalent (only if ROLE=prajjwal on that Mac):**

```bash
./bin/failure-demo backend-a break
```

**🎙️ Say (Aditya, while Prajjwal stops A):**

> “Failure demo **D3** — one backend stopped.  
> Prajjwal is stopping Backend A on Mac three with the project stop script.  
> We are **not** touching DNS or the edge. Only upstream A goes away.”

**Expected cues:** Stop script exits cleanly; Backend A process down on Mac 3.

---

### [4:15 – 4:40] Observe failover (domain name, no `-k`)

**Show on screen:** Aditya Mac 1 terminal — **zoom in**.

**Run:**

```bash
curl -sS https://app.team1.test:8443/api/status && echo
curl -sS https://app.team1.test:8443/api/status && echo
curl -sS https://app.team1.test:8443/api/status && echo
```

**Optional stronger proof:**

```bash
for i in 1 2 3 4; do curl -sS https://app.team1.test:8443/api/status; echo; done
```

**🎙️ Say:**

> “Observing from the client by **domain name**: `https://app.team1.test:8443/api/status`.  
> The first request may take about two seconds while nginx notices A is dead. After that, every request still returns success — and every response is from Backend **B** only.  
> So DNS still works, TCP and TLS to Kartik still work, and the edge keeps serving.  
> **Concept:** nginx passive health checks — `max_fails`, `fail_timeout`, and `proxy_next_upstream` — fail over to the surviving upstream. Users do not see a hard outage when one backend dies.”

**Expected output cues:** HTTP success (200 / JSON body); backend identity **B** on successive lines. First call may be slower; that is OK.

**Do not** use `curl -k`. **Do not** curl by IP.

---

### [4:40 – 4:55] Rollback + prove recovery

**On Prajjwal (Mac 3):**

```bash
./macs/mac3-prajjwal/start.sh
```

**Equivalent:**

```bash
./bin/failure-demo backend-a rollback
```

**On Aditya (Mac 1), after ~2–3 seconds:**

```bash
for i in 1 2 3 4 5 6; do curl -sS https://app.team1.test:8443/api/status; echo; done
```

**🎙️ Say:**

> “Rollback: Prajjwal restarts Backend A.  
> We send six more requests by domain name — A and B should both appear again under round robin.  
> That closes D3: break, observe failover, explain the layer, restore service.”

**Expected output cues:** Mix of A and B again (not B-only).

---

### [4:55 – 5:00] Outro

**Show on screen:** Final successful curl / status output, or team still on camera.

**🎙️ Say:**

> “That’s Fsociety — Phase one on four Macs: private DNS, TLS edge, load balancing, and D3 backend failover. Thank you.”

**Stop recording.** Target total ≤ 5:00.

---

## Quick copy-paste cheatsheet (Aditya Mac 1 + Prajjwal for D3)

```bash
# === PRE-RECORD (Aditya) ===
sudo -v
./bin/status
clear

# === SEG 1 ===
./scripts/macos-network-info.sh
./bin/status

# === SEG 2 ===
cat /etc/resolver/team1.test
dig @127.0.0.1 +noall +answer app.team1.test
dig @127.0.0.1 +noall +answer api.team1.test
curl -v https://app.team1.test:8443/__edge/health 2>&1 | grep -E '(ALPN|SSL connection|HTTP/2|subject:|issuer:)'
for i in 1 2 3 4 5 6; do curl -sS https://app.team1.test:8443/api/status; echo; done
./bin/status

# === SEG 3 — D3 (Prajjwal break) ===
./macs/mac3-prajjwal/stop.sh
# (Aditya observe)
curl -sS https://app.team1.test:8443/api/status && echo
curl -sS https://app.team1.test:8443/api/status && echo
curl -sS https://app.team1.test:8443/api/status && echo
# (Prajjwal rollback)
./macs/mac3-prajjwal/start.sh
# (Aditya prove)
for i in 1 2 3 4 5 6; do curl -sS https://app.team1.test:8443/api/status; echo; done
```

---

## Optional extras / viva prep (NOT required in the 5-minute video)

These are the **other** failure cases supported by `bin/failure-demo` and `docs/FAILURE_DEMOS.md`. Know them for viva; do not squeeze all into the timed video.

| # | Scenario | Break | Expect | Concept |
|---|---|---|---|---|
| 1 | Wrong DNS server on client | `./bin/failure-demo wrong-resolver break` | Cannot resolve; `ping <EDGE_IP>` still works | DNS ≠ IP connectivity |
| 2 | DNS record → wrong IP | `./bin/failure-demo wrong-dns-record break` (Aditya) | `dig` returns `192.0.2.99`; curl cannot connect | DNS is a directory, not a connection |
| **3 = D3** | **Backend A stopped** | **`./macs/mac3-prajjwal/stop.sh`** | **Requests succeed, all B** | **Passive failover** |
| 4 | Both backends stopped | both owners `stop.sh` | DNS/TCP/TLS OK; `502 Bad Gateway` | Edge alive, no upstream |
| 5 | Wrong port | `./bin/failure-demo wrong-port break` | Resolves, then connection refused on `:9999` | Port ≠ host reachability |

**Always rollback** after practice (`wrong-resolver` / `wrong-dns-record` / backend start scripts), then `./bin/test-all`.

**Explain helpers (prints names/IPs from your env):**

```bash
./bin/failure-demo wrong-resolver explain
./bin/failure-demo wrong-dns-record explain
./bin/failure-demo backend-a explain
./bin/failure-demo both-backends explain
./bin/failure-demo wrong-port explain
```

**Other high-value viva demos if faculty asks outside the video:**
- Caching: `./tests/test_cache.sh` or `curl -I https://app.team1.test:8443/api/cacheable`
- Full suite: `./bin/test-all`
- Diagnosis: `./bin/doctor`
- Packets: `scripts/capture-packets.sh 60` + Wireshark (`dns`, `tls.handshake`)

---

## Recording / editing tips

1. Prefer **one take** on Aditya’s terminal; Prajjwal can be heard saying “stopped” / “started” off-mic or on a second mic.
2. If D3’s first curl hangs ~2 s, **leave it** — that delay is part of the teaching point.
3. If load balancing shows only one letter before D3, fix with `./bin/status` / restart the quiet backend — do not record a broken happy path.
4. Export 1080p MP4; keep file under any Drive size limit; share as **Anyone with the link can view**.
5. Filename for upload: **`CN_Phase1_Fsociety_Type1.mp4`**.
