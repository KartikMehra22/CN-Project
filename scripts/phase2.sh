#!/usr/bin/env bash
# Phase 2 (Harden, Recover, Troubleshoot) - the whole implementation in one file.
# Source AFTER common.sh + load_config + checks.sh + roles.sh. Defines functions only.
#
# Design rule: a Mac works out what it is responsible for from ITS OWN IP
# (is_me <ip>), not from a "role" name. So the same command works whether the team
# runs 4 Macs, 3 Macs, or 2 Macs with combined roles.
# shellcheck disable=SC2034

P2_EVID="$REPO_ROOT/evidence/phase2"
P2_ANCHOR="cn-phase2"                         # pf anchor: our rules live here, /etc/pf.conf is never edited
P2_PF_RULES="$CN_GEN_DIR/pf-cn-phase2.rules"
P2_PF_CONF="$CN_GEN_DIR/pf-cn-phase2.conf"
P2_PF_TOKEN="$CN_RUN_DIR/pf.token"            # exists only while WE are holding pf enabled
P2_DRILL="$CN_RUN_DIR/drill"
P2_BUNDLE_DEFAULT="$HOME/cn-edge-bundle.enc"
P2_TEST_NET_IP=192.0.2.77                     # RFC 5737 documentation range: guaranteed unused

# ------------------------------------------------------------ who am I -----
my_ip()  { echo "${CN_MY_IP:-$(local_ip)}"; }
is_me()  { [ -n "${1:-}" ] && [ "$1" = "$(my_ip)" ]; }
p2_is_dns1()    { is_me "$DNS_IP"; }
p2_is_dns2()    { is_me "$DNS2_IP"; }
p2_is_edge()    { is_me "$EDGE_IP"; }
p2_is_standby() { is_me "$STANDBY_EDGE_IP"; }
p2_is_a()       { is_me "$VAIBHAV_LAN_IP"; }
p2_is_b()       { is_me "$AKSHAT_LAN_IP"; }
p2_is_backend() { p2_is_a || p2_is_b; }

p2_need() {  # p2_need dns1|edge|backend  -> die with a friendly message if this Mac is the wrong one
  case "$1" in
    dns1)    p2_is_dns1 || die "Run this on Mitul's Mac (primary DNS, $DNS_IP). This Mac is $(my_ip).";;
    edge)    p2_is_edge || die "Run this on the edge Mac ($EDGE_IP). This Mac is $(my_ip).";;
    backend) p2_is_backend || die "Run this on a backend Mac (A=$VAIBHAV_LAN_IP, B=$AKSHAT_LAN_IP). This Mac is $(my_ip).";;
  esac
}

# --------------------------------------------------------------- output ----
step() { printf '\n%s\n' "${C_BLD}$*${C_RST}"; }
why()  { printf '  %sWHY%s  %s\n' "$C_BLU" "$C_RST" "$*"; }
cmd()  { printf '  %s$ %s%s\n' "$C_YEL" "$*" "$C_RST"; }
show() { cmd "$*"; "$@" 2>&1 | sed 's/^/    /'; return 0; }   # run + indent; never aborts a demo

# p2_record <name> <function> [args]: run a demo, tee it, save a colour-free transcript as evidence.
p2_record() {
  local name="$1"; shift; local raw f rc
  mkdir -p "$P2_EVID"; raw="$(mktemp)"; f="$P2_EVID/$(date +%Y%m%d-%H%M%S)-$name.txt"
  { echo "# $name | $(date) | host=$(hostname -s) ip=$(my_ip)"; "$@"; } 2>&1 | tee "$raw"
  rc="${PIPESTATUS[0]}"
  sed $'s/\033\\[[0-9;]*m//g' "$raw" > "$f"; rm -f "$raw"
  echo; info "Evidence saved: ${f#"$REPO_ROOT"/}"
  return "$rc"
}

p2_wait() {  # p2_wait <timeout-s> <description> <cmd...>  -> polls every 2 s
  local t="$1" d="$2" s=$SECONDS; shift 2
  printf '  waiting for %s ' "$d"
  while ! "$@" >/dev/null 2>&1; do
    if [ $((SECONDS - s)) -ge "$t" ]; then echo " TIMEOUT after ${t}s"; return 1; fi
    printf '.'; sleep 2
  done
  echo " done after $((SECONDS - s))s"
}

# p2_guard <fn>: run <fn> when the demo ends OR is interrupted (Ctrl-C), so a demo can never leave
# the system broken. Handlers use globals (not locals) because they may fire after the demo returned.
# shellcheck disable=SC2064  # expand NOW: the handler name is known when the trap is set
p2_guard()   { trap "$1" EXIT; trap "$1; exit 130" INT TERM; }
p2_unguard() { trap - EXIT INT TERM; }

# ------------------------------------------------------------ probes -------
dig_at()   { "$DIG" +short +time=2 +tries=1 -p "$DNS_PORT" "@$1" "$APP_DOMAIN" 2>/dev/null | head -1; }
chk_dns2() { is_edge_ip "$(dig_at "$DNS2_IP")"; }
edge_health_at() { app_curl --resolve "${APP_DOMAIN}:${EDGE_PORT}:$1" "$APP_URL/__edge/health" 2>/dev/null; }
edge_label_at()  { app_curl --resolve "${APP_DOMAIN}:${EDGE_PORT}:$1" -o /dev/null -D - "$APP_URL/__edge/health" 2>/dev/null | tr -d '\r' | awk 'tolower($1)=="x-edge:"{print $2}'; }
chk_edge_primary() { [ "$(edge_health_at "$EDGE_IP")" = "edge ok" ]; }
chk_edge_standby() { [ "$(edge_health_at "$STANDBY_EDGE_IP")" = "edge ok" ]; }
edge_now()       { app_curl -o /dev/null -D - "$APP_URL/__edge/health" 2>/dev/null | tr -d '\r' | awk 'tolower($1)=="x-edge:"{print $2}'; }
resolver_has_backup() { [ -n "$DNS2_IP" ] && grep -q "nameserver $DNS2_IP" "$RESOLVER_FILE_DIR/$TEST_ZONE" 2>/dev/null; }

# ------------------------------------------------------------- setup -------
p2_topology_prompts() {
  prompt_var DNS_IP        "Mitul's (primary DNS, Mac 1) LAN IP"
  prompt_var EDGE_IP       "Hardik's (edge nginx, Mac 2) LAN IP"
  prompt_var VAIBHAV_LAN_IP "Vaibhav's (Backend A, Mac 3) LAN IP"
  prompt_var AKSHAT_LAN_IP "Akshat's (Backend B, Mac 4) LAN IP"
}

p2_validate() {
  [ "$NETWORK_MODE" = lan ] || die "Phase 2 needs NETWORK_MODE=lan (the brief's shared LAN; pf rules by source IP are meaningless through the Cloudflare tunnel)."
  [ "$DNS2_IP" != "$DNS_IP" ] || die "Backup DNS ($DNS2_IP) is the same Mac as the primary. The brief requires a different Mac: set DNS2_IP in $CN_USER_ENV."
  [ "$STANDBY_EDGE_IP" != "$EDGE_IP" ] || die "Standby edge ($STANDBY_EDGE_IP) is the same Mac as the primary edge. Set STANDBY_EDGE_IP in $CN_USER_ENV."
}

p2_plan() {
  info "This Mac is $(my_ip). Phase 2 duties derived from the IP table:"
  p2_is_dns1    && echo "    - PRIMARY DNS      : record TTL + cutover target (Extensions B, E)"
  p2_is_dns2    && echo "    - BACKUP DNS       : second dnsmasq with the same records (Extension A)"
  p2_is_edge    && echo "    - PRIMARY EDGE     : hands its certificate to the standby (Extension E)"
  p2_is_standby && echo "    - STANDBY EDGE     : second nginx, same config + same certificate (Extension E)"
  p2_is_a       && echo "    - BACKEND A HOST   : firewall rules allow only the edge(s) (Extension C)"
  p2_is_b       && echo "    - BACKEND B HOST   : firewall rules allow only the edge(s) (Extension C)"
  p2_is_dns1 || p2_is_dns2 || p2_is_edge || p2_is_standby || p2_is_backend || echo "    - client only      : resolver lists primary + backup DNS (Extension A)"
}

# Pick up an encrypted edge bundle (AirDrop lands in ~/Downloads) if this is the standby.
p2_find_bundle() {
  local f
  for f in "${CN_EDGE_BUNDLE:-}" "$HOME/Downloads/cn-edge-bundle.enc" "$P2_BUNDLE_DEFAULT"; do
    [ -n "$f" ] && [ -f "$f" ] && { echo "$f"; return 0; }
  done
  return 1
}

p2_setup() {
  banner "PHASE 2 SETUP - HARDEN, RECOVER, TROUBLESHOOT"
  require_macos; ensure_dirs
  local a k v
  for a in "$@"; do   # accept pasted KEY=VALUE pairs (see `bin/phase2 topology`)
    case "$a" in
      --edge-bundle=*) CN_EDGE_BUNDLE="${a#*=}";;
      HARDIK_LAN_IP=*) save_config_var VAIBHAV_LAN_IP "${a#*=}";;   # legacy name of the Backend A IP (old pasted lines)
      DNS_IP=*|EDGE_IP=*|VAIBHAV_LAN_IP=*|AKSHAT_LAN_IP=*|DNS2_IP=*|STANDBY_EDGE_IP=*|TEAM=*) k="${a%%=*}"; v="${a#*=}"; save_config_var "$k" "$v";;
      *) die "unknown argument: $a";;
    esac
  done
  [ "$NETWORK_MODE" = lan ] || die "Phase 2 needs NETWORK_MODE=lan (set it in $CN_USER_ENV)."
  if [ "${CN_P2_CHAIN:-0}" = 1 ] && { [ -z "${DNS_IP:-}" ] || [ -z "${EDGE_IP:-}" ] || [ -z "${VAIBHAV_LAN_IP:-}" ] || [ -z "${AKSHAT_LAN_IP:-}" ]; }; then
    # Called at the end of a Phase 1 setup on a Mac that does not know the whole IP table: do not interrogate, point at the one-liner.
    info "Phase 2 needs the team's IP table. On Mitul's Mac run  ./bin/phase2 topology  and paste the line it prints here"
    info "(or just answer the prompts: ./bin/phase2 setup)."
    return 0
  fi
  p2_topology_prompts
  save_config_var PHASE2 1; load_config
  p2_validate; p2_plan; echo
  have_cmd dig || ensure_formula bind dig

  if p2_is_dns2; then ensure_formula dnsmasq dnsmasq; p2_dns2_start; fi
  if p2_is_standby; then
    ensure_formula nginx nginx
    local b; b="$(p2_find_bundle || true)"
    if [ -n "$b" ]; then p2_bundle_import "$b" && p2_standby_start
    else warn "Standby needs the edge's certificate. On the EDGE Mac run  ./bin/phase2 setup  (it prints the file + passphrase),"
         warn "AirDrop the file here, then re-run  ./bin/phase2 setup  (it is found in ~/Downloads automatically)."; fi
  fi
  if p2_is_edge && [ -n "$STANDBY_EDGE_IP" ] && [ ! -f "$P2_BUNDLE_DEFAULT" ] && [ -f "$TLS_CERT" ]; then p2_bundle_export; fi
  if p2_is_backend; then p2_iso_render; ok "Firewall rules prepared (NOT active). Turn on for the demo: ./bin/phase2 isolate on"; fi

  # Clients that already use our scoped resolver now list primary + backup (Extension A).
  if p2_is_dns1; then resolver_install 127.0.0.1
  elif [ -f "$RESOLVER_FILE_DIR/$TEST_ZONE" ] || p2_is_dns2 || p2_is_edge; then resolver_install "$DNS_IP"; fi
  echo; p2_status
  echo; info "Next: ./bin/phase2 test      (checks A-E)   |   demos: see docs/PHASE2.md"
  p2_is_dns1 && { echo; info "Teammates: run this on each of the other Macs (copy-paste):"; p2_topology_line; }
  return 0
}

p2_topology_line() {
  printf '    ./bin/phase2 setup DNS_IP=%s EDGE_IP=%s VAIBHAV_LAN_IP=%s AKSHAT_LAN_IP=%s\n' "$DNS_IP" "$EDGE_IP" "$VAIBHAV_LAN_IP" "$AKSHAT_LAN_IP"
}

p2_start() {
  [ "${PHASE2:-0}" = 1 ] || return 0
  p2_is_dns2 && p2_dns2_start
  p2_is_standby && p2_standby_start
  return 0
}
p2_stop() {
  p2_is_dns2 && dns_stop
  p2_is_standby && edge_stop
  p2_iso_off 2>/dev/null || true
  return 0
}

# ------------------------------------------- Extension A: backup DNS --------
p2_dns2_start() { DNS_IP="$DNS2_IP" dns_start; }   # same code as the primary, listening on THIS Mac's IP

p2_restore_dns() { [ "${P2_DONE:-1}" = 1 ] && return; P2_DONE=1; echo; info "Restoring primary DNS"; dns_start >/dev/null 2>&1; flush_dns_cache; }
p2_demo_dns_failover() {
  p2_need dns1
  [ -n "$DNS2_IP" ] || die "Run ./bin/phase2 setup first."
  detect_trust; P2_DONE=0; p2_guard p2_restore_dns
  banner "EXTENSION A - BACKUP DNS RESOLVER"
  step "1. Two DNS servers, same records"
  show cat "$RESOLVER_FILE_DIR/$TEST_ZONE"
  show "$DIG" +noall +answer -p "$DNS_PORT" "@$DNS_IP"  "$APP_DOMAIN"
  show "$DIG" +noall +answer -p "$DNS_PORT" "@$DNS2_IP" "$APP_DOMAIN"
  why "clients list BOTH servers in /etc/resolver/$TEST_ZONE; the first is tried first, the second only if the first does not answer."
  step "2. Everything works while the primary is up"
  flush_dns_cache
  show app_curl -o /dev/null -w "dns=%{time_namelookup}s http=%{http_code}\n" "$APP_URL/api/status"
  step "3. STOP the primary DNS (dnsmasq on this Mac)"
  dns_stop; ok "primary dnsmasq stopped"; flush_dns_cache
  show "$DIG" +time=1 +tries=1 -p "$DNS_PORT" "@$DNS_IP" "$APP_DOMAIN"
  show "$DIG" +noall +answer -p "$DNS_PORT" "@$DNS2_IP" "$APP_DOMAIN"
  step "4. Clients keep resolving - through the backup"
  show dscacheutil -q host -a name "$APP_DOMAIN"
  show app_curl -o /dev/null -w "dns=%{time_namelookup}s http=%{http_code}\n" "$APP_URL/api/status"
  if chk_dns_client; then ok "PASS: name still resolves and the HTTPS service answers with the primary DNS down"
  else fail "FAIL: client could not resolve; is the backup running? (./bin/phase2 status on $DNS2_IP)"; fi
  why "DNS FAILURE = names stop resolving (here hidden by the backup). APPLICATION FAILURE = names resolve fine but the service answers 502/refuses."
  why "A cached answer would also hide a DNS outage until its TTL expires - that is Extension B."
  p2_restore_dns; p2_unguard
  step "5. Primary is back"
  show "$DIG" +noall +answer -p "$DNS_PORT" "@$DNS_IP" "$APP_DOMAIN"
}

# -------------------------------------------- Extension B: TTL + change -----
p2_cache_note() {  # $1=old $2=what the client resolver says now
  if [ "$2" = "$1" ]; then ok "client still answers $2 (cached; the server already says something else)"
  else warn "client already shows $2: this resolver did not cache the answer (dig always asks the server; only the OS cache honours TTL)"; fi
}
p2_restore_ttl() { [ "${P2_DONE:-1}" = 1 ] && return; P2_DONE=1; echo; info "Restoring record -> $P2_OLD (TTL ${DNS_TTL}s)"; DNS_RECORD_IP="$P2_OLD" dns_start >/dev/null 2>&1; flush_dns_cache; }
p2_demo_ttl() {
  p2_need dns1
  local old="${DNS_RECORD_IP:-$EDGE_IP}" ttl="$DEMO_TTL" new="${STANDBY_EDGE_IP:-$P2_TEST_NET_IP}" t0 got
  [ "$new" != "$old" ] || new="$P2_TEST_NET_IP"
  P2_DONE=0; P2_OLD="$old"; p2_guard p2_restore_ttl
  banner "EXTENSION B - DNS TTL AND CONTROLLED RECORD CHANGE"
  step "1. Short, visible TTL (${ttl}s instead of ${DNS_TTL}s)"
  DNS_RECORD_IP="$old" DNS_TTL="$ttl" dns_start >/dev/null
  show "$DIG" +noall +answer -p "$DNS_PORT" "@127.0.0.1" "$APP_DOMAIN"
  why "the number after the name is the TTL: how long a resolver may keep this answer without asking again."
  step "2. Client resolves $APP_DOMAIN (answer is now cached by the OS)"
  flush_dns_cache; got="$(resolve_via_system)"; echo "    client resolver: $got"
  step "3. Change the record on the DNS server: $old -> $new"
  DNS_RECORD_IP="$new" DNS_TTL="$ttl" dns_start >/dev/null; t0=$SECONDS
  echo "    server  (dig, never cached): $(dig_at 127.0.0.1)"
  got="$(resolve_via_system)"; echo "    client  (OS resolver)      : $got"; p2_cache_note "$old" "$got"
  step "4. Wait for the TTL to expire (client polls every 3 s)"
  while [ "$(resolve_via_system)" != "$new" ] && [ $((SECONDS - t0)) -lt $((ttl + 20)) ]; do
    printf '    t+%2ds  client=%s\n' $((SECONDS - t0)) "$(resolve_via_system)"; sleep 3
  done
  printf '    t+%2ds  client=%s\n' $((SECONDS - t0)) "$(resolve_via_system)"
  [ "$(resolve_via_system)" = "$new" ] && ok "client switched to $new after ~$((SECONDS - t0))s (TTL ${ttl}s)" || warn "client did not switch within $((ttl + 20))s"
  step "5. Manual cache flush gives an IMMEDIATE change"
  DNS_RECORD_IP="$old" DNS_TTL="$ttl" dns_start >/dev/null
  got="$(resolve_via_system)"; echo "    server now: $(dig_at 127.0.0.1)   client (cached): $got"
  cmd "sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder"; flush_dns_cache
  got="$(resolve_via_system)"; echo "    client after flush: $got"
  [ "$got" = "$old" ] && ok "PASS: change visible instantly after the flush" || warn "client shows $got after flush (expected $old)"
  why "production: lower the TTL BEFORE a migration, change the record, wait one TTL, then raise it again; that bounds how long users hit the old server."
  p2_restore_ttl; p2_unguard
}

# ------------------------------------- Extension C: service isolation ------
p2_iso_ports() { local p=""; p2_is_a && p="$BACKEND_A_PORT"; p2_is_b && p="$p $BACKEND_B_PORT"; echo $p; }

p2_iso_render() {   # writes the rules + a pf.conf that includes them; validates both without root
  local ports allowed port; ports="$(p2_iso_ports)"
  [ -n "$ports" ] || die "This Mac ($(my_ip)) hosts no backend; run on A=$VAIBHAV_LAN_IP or B=$AKSHAT_LAN_IP."
  allowed="${P2_ISO_ALLOW:-$EDGE_IP${STANDBY_EDGE_IP:+, $STANDBY_EDGE_IP}}"
  {
    echo "# cn-phase2 / Extension C. Generated. Backend ports are reachable ONLY from: $allowed"
    echo "pass in quick on lo0 all"
    for port in $ports; do
      echo "pass  in quick inet proto tcp from { $allowed } to any port $port"
      echo "block drop in quick inet proto tcp from any to any port $port"
    done
  } > "$P2_PF_RULES"
  { cat /etc/pf.conf; printf 'anchor "%s"\n' "$P2_ANCHOR"; } > "$P2_PF_CONF"
  /sbin/pfctl -nf "$P2_PF_CONF" >/dev/null 2>&1 || die "generated pf.conf does not parse: $P2_PF_CONF"
  /sbin/pfctl -n -a "$P2_ANCHOR" -f "$P2_PF_RULES" >/dev/null 2>&1 || die "generated rules do not parse: $P2_PF_RULES"
}

p2_iso_active() { [ -f "$P2_PF_TOKEN" ]; }

p2_iso_on() {
  p2_need backend; p2_iso_render
  p2_iso_active && { ok "isolation already ON"; return 0; }
  backup_file /etc/pf.conf
  sudo -v
  # shellcheck disable=SC2024  # the file is ours (user-owned); only pfctl needs root
  sudo /sbin/pfctl -sr 2>/dev/null > "$CN_BACKUP_DIR/pf-rules-before.$(date +%Y%m%d-%H%M%S).txt" || true   # rollback copy of the live rules
  local out tok
  out="$(sudo /sbin/pfctl -E 2>&1)"; tok="$(printf '%s\n' "$out" | awk '/Token/{print $NF}')"
  sudo /sbin/pfctl -f "$P2_PF_CONF" >/dev/null 2>&1 || { [ -n "$tok" ] && sudo /sbin/pfctl -X "$tok" >/dev/null 2>&1; die "could not load the pf ruleset (nothing was changed)"; }
  sudo /sbin/pfctl -a "$P2_ANCHOR" -f "$P2_PF_RULES" >/dev/null 2>&1 || { sudo /sbin/pfctl -f /etc/pf.conf >/dev/null 2>&1; [ -n "$tok" ] && sudo /sbin/pfctl -X "$tok" >/dev/null 2>&1; die "could not load anchor rules (rolled back)"; }
  echo "${tok:-none}" > "$P2_PF_TOKEN"
  ok "ISOLATION ON - ports $(p2_iso_ports) reachable only from the edge(s):"
  sed 's/^/    /' "$P2_PF_RULES"
  info "Rollback any time: ./bin/phase2 isolate off   (also restores /etc/pf.conf; backups in $CN_BACKUP_DIR)"
}

p2_iso_off() {
  p2_iso_active || { ok "isolation already OFF"; return 0; }
  local tok; tok="$(cat "$P2_PF_TOKEN" 2>/dev/null)"
  sudo -v
  sudo /sbin/pfctl -a "$P2_ANCHOR" -F all >/dev/null 2>&1 || true
  sudo /sbin/pfctl -f /etc/pf.conf >/dev/null 2>&1 || true            # the system's original ruleset
  [ -n "$tok" ] && [ "$tok" != none ] && sudo /sbin/pfctl -X "$tok" >/dev/null 2>&1 || true   # release our "pf enabled" hold
  rm -f "$P2_PF_TOKEN"
  ok "ISOLATION OFF - original firewall configuration restored"
}

p2_iso_test() {   # run on ANY Mac: can THIS Mac reach the backend ports directly?
  local id host port reach allowed verdict bad=0
  banner "EXTENSION C - WHO CAN REACH THE BACKENDS DIRECTLY? (this Mac: $(my_ip))"
  for id in A B; do
    if [ "$id" = A ]; then host="$BACKEND_A_HOST"; port="$BACKEND_A_PORT"; else host="$BACKEND_B_HOST"; port="$BACKEND_B_PORT"; fi
    if port_open "$host" "$port" 2; then reach=yes; else reach=no; fi
    if is_me "$EDGE_IP" || is_me "$STANDBY_EDGE_IP" || is_me "$host"; then allowed=yes; else allowed=no; fi
    if [ "$allowed" = "$reach" ]; then verdict="${C_GRN}as designed${C_RST}"
    elif [ "$allowed" = no ]; then verdict="${C_RED}NOT ISOLATED${C_RST} (rules off? run: ./bin/phase2 isolate on  on the backend Mac)"; bad=1
    else verdict="${C_RED}EDGE BLOCKED${C_RST} (allow-list wrong or backend down)"; bad=1; fi
    printf '  Backend %s %s:%-5s  direct connect: %-3s   allowed to: %-3s   -> %s\n' "$id" "$host" "$port" "$reach" "$allowed" "$verdict"
  done
  echo "  Through the edge (the intended path): $(chk_app && echo "${C_GRN}works${C_RST}" || echo "${C_RED}FAILS${C_RST}")   $(sample_backends 4)"
  why "firewall rules filter on the SOURCE IP: the edge is on the list, every other client is dropped before it reaches the app."
  return $bad
}

# -------------------------------------------- Extension D: HA failover ------
p2_demo_failover() {
  local dead="${1:-a}" live letter_dead letter_live owner_script t
  case "$dead" in a|A) letter_dead=A; letter_live=B; owner_script="./macs/mac3-vaibhav/stop.sh";; b|B) letter_dead=B; letter_live=A; owner_script="./macs/mac4-akshat/stop.sh";; *) die "usage: phase2 failover [a|b]";; esac
  live="$letter_live"
  p2_only_live() { local o; o="$(sample_backends 4)"; [[ "$o" == *"$live"* && "$o" != *"$letter_dead"* && "$o" != *\?* ]]; }
  p2_both_up()   { local o; o="$(sample_backends 8)"; [[ "$o" == *A* && "$o" == *B* ]]; }
  detect_trust
  banner "EXTENSION D - HIGH-AVAILABILITY FAILOVER (stop Backend $letter_dead)"
  step "1. Healthy: both backends share the load"
  echo "    responses: $(sample_backends 8)"
  p2_both_up || { fail "both backends must be up first: ./bin/status"; return 1; }
  step "2. STOP Backend $letter_dead"
  if { [ "$letter_dead" = A ] && p2_is_a; } || { [ "$letter_dead" = B ] && p2_is_b; }; then
    local role; [ "$letter_dead" = A ] && role=vaibhav || role=akshat
    info "this Mac runs Backend $letter_dead - stopping it"; "$REPO_ROOT/scripts/role.sh" "$role" stop >/dev/null
  else
    info "On the Backend $letter_dead Mac run:  ${owner_script}"
  fi
  p2_wait 180 "Backend $letter_dead to go down and nginx to route around it" p2_only_live || return 1
  step "3. Service continues on Backend $letter_live only"
  echo "    responses: $(sample_backends 10)"
  for t in 1 2 3; do app_curl -o /dev/null -w "    GET /api/status -> HTTP %{http_code}\n" "$APP_URL/api/status"; done
  why "nginx marks the failed upstream (max_fails=$UPSTREAM_MAX_FAILS, fail_timeout=$UPSTREAM_FAIL_TIMEOUT) and proxy_next_upstream retries the other one within the same request."
  step "4. START Backend $letter_dead again"
  if { [ "$letter_dead" = A ] && p2_is_a; } || { [ "$letter_dead" = B ] && p2_is_b; }; then
    info "this Mac runs Backend $letter_dead - starting it"
    "$REPO_ROOT/scripts/role.sh" "$([ "$letter_dead" = A ] && echo vaibhav || echo akshat)" start >/dev/null
  else
    info "On the Backend $letter_dead Mac run:  ${owner_script%stop.sh}start.sh"
  fi
  p2_wait 180 "load balancing to resume across both" p2_both_up || return 1
  echo "    responses: $(sample_backends 8)"
  ok "PASS: failover and recovery observed"
  step "5. What is STILL a single point of failure?"
  echo "    The edge nginx (Mac 2): if it dies every client fails even though both backends are healthy."
  echo "    Phase 2 reduces the damage with a standby edge + DNS cutover (Extension E, recovery time ~ DNS TTL)."
  echo "    To REMOVE it you need automatic takeover: a floating/virtual IP (VRRP/keepalived) shared by two edges,"
  echo "    or DNS health checks that switch the record on their own (e.g. Route 53 health-checked failover)."
}

# ------------------------------------ Extension E: standby + DNS cutover -----
p2_standby_start() {
  if [ ! -f "$TLS_CERT" ] || [ ! -f "$TLS_KEY" ]; then warn "no edge certificate here yet (see ./bin/phase2 setup)"; return 1; fi
  edge_start
}

p2_bundle_export() {
  p2_need edge
  [ -f "$TLS_CERT" ] && [ -f "$TLS_KEY" ] || die "No server certificate yet: run ./macs/mac2-hardik/setup.sh first."
  local out="${1:-$P2_BUNDLE_DEFAULT}" pass
  pass="$(openssl rand -hex 10)"
  # -md sha256 (not -pbkdf2): works identically on macOS LibreSSL and Homebrew OpenSSL; the passphrase is 80 random bits.
  tar -czf - -C "$CN_TLS_DIR" server.crt server.key | CN_P="$pass" openssl enc -aes-256-cbc -md sha256 -salt -pass env:CN_P -out "$out" 2>/dev/null
  chmod 600 "$out"
  banner "STANDBY EDGE BUNDLE READY"
  echo "  File      : $out   (encrypted; contains the edge cert + key, NOT the CA key)"
  echo "  Passphrase: $pass"
  echo "  Send the file to the standby Mac (AirDrop) and tell its operator the passphrase separately."
  echo "  On the standby Mac:  ./bin/phase2 setup     (finds it in ~/Downloads; asks for the passphrase)"
}

p2_bundle_import() {
  local f="$1" pass="${CN_BUNDLE_PASS:-}" tmp; tmp="$(mktemp -d)"
  [ -f "$CN_CA_CERT_REPO" ] || die "pki/ca.crt missing: git pull first."
  if [ -z "$pass" ]; then read -r -s -p "Passphrase for $(basename "$f"): " pass; echo; fi
  if ! CN_P="$pass" openssl enc -d -aes-256-cbc -md sha256 -pass env:CN_P -in "$f" 2>/dev/null | tar -xzf - -C "$tmp" 2>/dev/null; then
    rm -rf "$tmp"; warn "could not decrypt $f (wrong passphrase?)"; return 1
  fi
  # never install anything we have not verified: signed by OUR CA, right names, key matches cert
  openssl verify -CAfile "$CN_CA_CERT_REPO" "$tmp/server.crt" >/dev/null 2>&1 || { rm -rf "$tmp"; warn "certificate is not signed by pki/ca.crt (git pull?)"; return 1; }
  openssl x509 -noout -text -in "$tmp/server.crt" | grep -q "DNS:${APP_DOMAIN}" || { rm -rf "$tmp"; warn "certificate lacks SAN ${APP_DOMAIN}"; return 1; }
  [ "$(openssl x509 -in "$tmp/server.crt" -noout -pubkey | openssl sha256)" = "$(openssl pkey -in "$tmp/server.key" -pubout | openssl sha256)" ] || { rm -rf "$tmp"; warn "key does not match certificate"; return 1; }
  ensure_dirs; backup_file "$TLS_CERT"; backup_file "$TLS_KEY"
  install -m 644 "$tmp/server.crt" "$TLS_CERT"; install -m 600 "$tmp/server.key" "$TLS_KEY"; rm -rf "$tmp"
  ok "Edge certificate installed from bundle (verified against pki/ca.crt)"
}

p2_point() {   # p2_point primary|standby : repoint the DNS records on THIS Mac's dnsmasq
  case "$1" in primary|standby) ;; *) die "usage: phase2 point primary|standby";; esac
  { p2_is_dns1 || p2_is_dns2; } || die "Run on a DNS Mac (primary $DNS_IP or backup $DNS2_IP)."
  save_config_var ACTIVE_EDGE "$1"; load_config
  [ "$1" = primary ] || [ -n "$STANDBY_EDGE_IP" ] || die "STANDBY_EDGE_IP not set"
  if p2_is_dns1; then dns_start >/dev/null; else DNS_IP="$DNS2_IP" dns_start >/dev/null; fi
  flush_dns_cache; ok "DNS now points $APP_DOMAIN -> ${DNS_RECORD_IP:-$EDGE_IP} ($1 edge)"
}

p2_watch_line() { printf '  %-7s server(dig)=%-15s client(OS)=%-15s answered-by=%s\n' "$1" "$(dig_at "$DNS_IP")" "$(resolve_via_system)" "$(edge_now)"; }
p2_watch() { local s=$SECONDS; echo "Ctrl-C to stop. Shows which IP this Mac resolves and which edge answered."; while true; do p2_watch_line "t+$((SECONDS - s))s"; sleep 2; done; }

p2_restore_cutover() { [ "${P2_DONE:-1}" = 1 ] && return; P2_DONE=1; [ "${P2_STAY:-0}" = 1 ] && return; echo; info "Switching back to the primary edge"; p2_point primary >/dev/null 2>&1; flush_dns_cache; }
p2_demo_cutover() {
  p2_need dns1
  [ -n "$STANDBY_EDGE_IP" ] || die "Run ./bin/phase2 setup first."
  local ttl="$DEMO_TTL" t0; P2_STAY=0; [ "${1:-}" = "--stay" ] && P2_STAY=1
  P2_DONE=0; p2_guard p2_restore_cutover
  detect_trust
  banner "EXTENSION E - CONTROLLED EDGE MIGRATION (DNS-BASED CUTOVER)"
  step "0. Pre-check: both edges serve the same site"
  chk_edge_primary || { fail "primary edge $EDGE_IP is not healthy"; return 1; }
  chk_edge_standby || { fail "standby edge $STANDBY_EDGE_IP is not healthy: on that Mac run ./bin/phase2 setup"; return 1; }
  echo "    primary  $EDGE_IP         -> X-Edge: $(edge_label_at "$EDGE_IP")"
  echo "    standby  $STANDBY_EDGE_IP -> X-Edge: $(edge_label_at "$STANDBY_EDGE_IP")"
  [ "$(edge_label_at "$EDGE_IP")" != "$(edge_label_at "$STANDBY_EDGE_IP")" ] || warn "both edges report the same X-Edge label; set EDGE_LABEL to tell them apart"
  step "1. Short TTL (${ttl}s) and a warm client cache pointing at the PRIMARY edge"
  DNS_RECORD_IP="$EDGE_IP" DNS_TTL="$ttl" dns_start >/dev/null; flush_dns_cache
  p2_watch_line "before"
  step "2. CUTOVER: DNS record -> standby edge $STANDBY_EDGE_IP   (watch the client)"
  DNS_RECORD_IP="$STANDBY_EDGE_IP" DNS_TTL="$ttl" dns_start >/dev/null; t0=$SECONDS
  while [ $((SECONDS - t0)) -lt $((ttl + 12)) ]; do p2_watch_line "t+$((SECONDS - t0))s"; sleep 3; done
  [ "$(edge_now)" = "$(edge_label_at "$STANDBY_EDGE_IP")" ] && ok "PASS: traffic moved to the standby edge" || warn "client still answered by the old edge"
  why "clients holding a cached answer keep using the OLD edge until the TTL expires; new lookups go to the standby at once. That is the traffic-cutover window."
  why "Backup DNS holds the OLD record: after a cutover also run  ./bin/phase2 point standby  on the backup DNS Mac so both servers agree."
  if [ "$P2_STAY" = 0 ]; then p2_restore_cutover; p2_unguard; p2_watch_line "restored"; fi
}

# ------------------------------------------ Extension F: troubleshooting -----
# Rehearsal: inject ONE random, reversible fault that THIS Mac can cause, hide which, practise ./bin/doctor.
p2_drill_menu() {
  p2_is_dns1  && echo "dns-record dns-down"
  p2_is_edge  && echo "edge-down"
  p2_is_backend && echo "backend-down firewall-blocks-edge"
}
p2_drill_inject() {
  case "$1" in
    dns-record) DNS_RECORD_IP=192.0.2.99 dns_start >/dev/null; flush_dns_cache;;
    dns-down) dns_stop; flush_dns_cache;;
    edge-down) edge_stop;;
    backend-down) "$REPO_ROOT/scripts/role.sh" "$(p2_is_a && echo vaibhav || echo akshat)" stop >/dev/null;;
    firewall-blocks-edge) P2_ISO_ALLOW=192.0.2.1 p2_iso_render; P2_ISO_ALLOW=192.0.2.1 p2_iso_on >/dev/null;;
  esac
}
p2_drill_fix() {
  case "$1" in
    dns-record|dns-down) dns_start >/dev/null; flush_dns_cache;;
    edge-down) edge_start >/dev/null;;
    backend-down) "$REPO_ROOT/scripts/role.sh" "$(p2_is_a && echo vaibhav || echo akshat)" start >/dev/null;;
    firewall-blocks-edge) p2_iso_off >/dev/null;;
  esac
}
p2_drill() {
  case "${1:-start}" in
    start)
      [ ! -f "$P2_DRILL" ] || die "A drill fault is already active. Fix it first: ./bin/phase2 drill fix"
      local menu f; local -a faults
      menu="$(p2_drill_menu)"; [ -n "$menu" ] || die "This Mac has nothing to break (it is a client only)."
      read -r -a faults <<<"$menu"; f="${faults[$((RANDOM % ${#faults[@]}))]}"
      sudo -v; p2_drill_inject "$f"; echo "$f" > "$P2_DRILL"
      banner "DRILL: ONE FAULT HAS BEEN INJECTED ON THIS MAC"
      echo "  Diagnose it like the examiner will want: name resolution -> TCP -> TLS -> application."
      echo "  Start:   ./bin/doctor          (first failing layer + the commands to investigate)"
      echo "  Peek:    ./bin/phase2 drill reveal        Repair:  ./bin/phase2 drill fix";;
    reveal) [ -f "$P2_DRILL" ] && echo "Injected fault: $(cat "$P2_DRILL")" || echo "No active drill.";;
    fix) [ -f "$P2_DRILL" ] || { echo "No active drill."; return 0; }
      local f; f="$(cat "$P2_DRILL")"; sudo -v; p2_drill_fix "$f"; rm -f "$P2_DRILL"; ok "fault '$f' repaired"; echo "  verify: ./bin/test-all";;
    *) die "usage: phase2 drill [start|reveal|fix]";;
  esac
}

# --------------------------------------------------------------- status -----
p2_status() {
  banner "PHASE 2 - THIS MAC ($(my_ip))   active edge: ${ACTIVE_EDGE:-primary}"
  p2_is_dns2    && row "Backup DNS ($DNS2_IP) running"          "$(mark dns_running)"
  p2_is_standby && row "Standby nginx running"                   "$(mark edge_running)"
  p2_is_backend && row "Backend firewall isolation"              "$(p2_iso_active && echo "${C_GRN}ON${C_RST}" || echo "off (armed; ./bin/phase2 isolate on)")"
  [ -f "$RESOLVER_FILE_DIR/$TEST_ZONE" ] && row "Resolver lists primary + backup"  "$(mark resolver_has_backup)"
  [ -f "$P2_DRILL" ] && row "DRILL fault active" "${C_YEL}yes (./bin/phase2 drill reveal)${C_RST}"
  echo; echo "  System view (from this Mac)"
  row "Primary DNS  $DNS_IP"   "$(mark chk_dns_server)"
  [ -n "$DNS2_IP" ]         && row "Backup DNS   $DNS2_IP"        "$(mark chk_dns2)"
  row "Primary edge $EDGE_IP"  "$(mark chk_edge_primary)"
  [ -n "$STANDBY_EDGE_IP" ] && row "Standby edge $STANDBY_EDGE_IP" "$(mark chk_edge_standby)"
  row "DNS record points to"   "$(dig_at "$DNS_IP")"
  return 0
}

# ----------------------------------------------------------------- undo -----
p2_rollback() {
  banner "PHASE 2 ROLLBACK (this Mac)"
  p2_iso_off || true
  [ -f "$P2_DRILL" ] && p2_drill fix
  p2_is_dns2 && { dns_stop; ok "backup DNS stopped"; }
  p2_is_standby && { edge_stop; ok "standby nginx stopped"; }
  save_config_var ACTIVE_EDGE primary; save_config_var PHASE2 0; load_config
  p2_is_dns1 && dns_start >/dev/null
  if [ -f "$RESOLVER_FILE_DIR/$TEST_ZONE" ]; then if p2_is_dns1; then resolver_install 127.0.0.1 ""; else resolver_install "$DNS_IP" ""; fi; fi
  ok "Phase 2 is off; Phase 1 behaviour restored. (Re-enable: ./bin/phase2 setup)"
}
