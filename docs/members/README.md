# Team FSOCIETY: member guides

One guide per person. Read **yours** fully, then skim the others, because the examiner can ask anyone about any part.

| Mac | Guide | Role in one line |
|---|---|---|
| 1 | [Aditya Kumar](01-aditya-kumar.md) | DNS server, test client, runs the demos and the evidence |
| 2 | [Kartik Mehra](02-kartik-mehra.md) | Front door: TLS, nginx load balancer, local CA, backup DNS |
| 3 | [Prajwal](03-prajwal.md) | Backend A, and the firewall demo (Extension C) |
| 4 | [Pratush](04-pratush.md) | Backend B, standby edge (Extension E), second client |

Full results with evidence paths: [../FINAL_REPORT.md](../FINAL_REPORT.md). Slides: [../CN_Team_FSOCIETY_Presentation.pptx](../CN_Team_FSOCIETY_Presentation.pptx).

## The 60-second story everyone must be able to tell

1. A client types `https://app.team1.test:8443`.
2. **Aditya's DNS** answers with the edge IP (10.100.147.77). If it is down, **Kartik's backup DNS** answers (Extension A).
3. The client opens TCP, then TLS, to the **edge nginx on Kartik's Mac**. The certificate is signed by our own CA.
4. nginx forwards each request alternately to **Backend A (Prajwal)** or **Backend B (Pratush)**. If one dies, the other serves (Extension D).
5. The backends only accept connections from the edges (firewall, Extension C).
6. If the edge itself dies, DNS is switched to **Pratush's standby edge** (Extension E).
7. If something breaks, `./bin/doctor` names the first failing layer (Extension F).

## Rules for the evaluation day

- Run `./bin/test-all` and `./bin/doctor` before anyone arrives. Do not start unless everything is green.
- Every demo restores the system when it ends. If one is interrupted, run `./bin/phase2 rollback` on that Mac.
- Never use `curl -k`. Never commit keys, tokens or the CA private key.
- Say the limits yourselves (FINAL_REPORT section 6) before you are asked.
