# LAN mode (`NETWORK_MODE=lan`) - the mode the brief describes

1. Put all four Macs on one Wi-Fi/LAN. Run `scripts/macos-network-info.sh` on each and record the values (Task A). Ping every pair.
2. Give each person their command from the README. When asked, answer with LAN IPs:
   `DNS_IP`=Aditya, `EDGE_IP`=Kartik, `PRAJJWAL_LAN_IP`, `PRATYUSH_LAN_IP`.
   Current live example (Fsociety Type 1): `DNS_IP=10.83.116.134`, `EDGE_IP=10.83.116.6`,
   `PRAJJWAL_LAN_IP=10.83.116.111`, `PRATYUSH_LAN_IP=10.83.116.87`.
3. nginx upstreams become `PRAJJWAL_LAN_IP:3001` and `PRATYUSH_LAN_IP:3002`. Nothing else differs.
4. macOS application firewall may ask to allow incoming connections for `python3` / `nginx` / `dnsmasq` - click **Allow** (or disable the firewall for the demo, and restore it afterwards).
5. Use a hotspot or a router that does not enable "client isolation"; otherwise Macs cannot reach each other.

Changing IPs (DHCP renumbering): re-run the setup script or edit `~/.config/cn-phase1/project.env`, then `./bin/start`.
Tip: give the four Macs DHCP reservations, or a hotspot, to keep addresses stable during the demo.
