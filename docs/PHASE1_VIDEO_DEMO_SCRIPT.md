# Phase 1 Video Demo Script — superseded

**Status:** Superseded. Do **not** use this file for recording.

| Field | Value |
|---|---|
| **Team name (Google Form)** | **Fsociety** |
| **Infra type** | Type 1 — 4 physical macOS on the same LAN |
| **Canonical speak-aloud script** | **[`docs/FSOCIETY_PHASE1_VIDEO_SCRIPT.md`](FSOCIETY_PHASE1_VIDEO_SCRIPT.md)** |
| **Suggested Drive filename** | `CN_Phase1_Fsociety_Type1.mp4` |

## Why this file exists

An earlier draft used the old display name **AEIN**, stale `10.80.3.x` LAN addresses, and a long multi-failure timeline that does not match the 5-minute Fsociety recording plan (single **D3** demo: Backend A stopped → failover to B).

## Members & roles (truth)

| Mac | Person | Enrollment | Role | Live LAN IP | Ports |
|---|---|---|---|---|---|
| 1 | Aditya Kumar | 2401010029 | DNS (dnsmasq) + client | `10.83.116.134` | 53 |
| 2 | Kartik Mehra | 2401020030 | nginx edge TLS + LB | `10.83.116.6` | 8443 |
| 3 | Prajjwal Tripathi | 2401010331 | Backend A | `10.83.116.111` | 3001 |
| 4 | Pratyush Parida | 2401010351 | Backend B | `10.83.116.87` | 3002 |

**Technical domain config (unchanged):** `TEAM=team1`, zones `app.team1.test` / `api.team1.test`.

**Open the canonical script:** [FSOCIETY_PHASE1_VIDEO_SCRIPT.md](FSOCIETY_PHASE1_VIDEO_SCRIPT.md)
