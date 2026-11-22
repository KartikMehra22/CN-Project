#!/usr/bin/env bash
# Phase 2 checks, Extensions A-F. Non-destructive: it only reads and probes.
. "$(dirname "$0")/../scripts/testlib.sh"
. "$(dirname "$0")/../scripts/roles.sh"
. "$(dirname "$0")/../scripts/phase2.sh"
echo "[PHASE 2]"
if [ "${PHASE2:-0}" != 1 ]; then t_fail "Phase 2 is armed on this Mac" "run ./bin/phase2 setup"; t_finish; exit; fi
detect_trust

t_check "A  primary DNS $DNS_IP answers $APP_DOMAIN" "dnsmasq on Mac 1 is down or the record is wrong" chk_dns_server
t_check "A  BACKUP DNS $DNS2_IP answers the same record" "backup dnsmasq is not running: on that Mac run ./bin/phase2 start" chk_dns2
if [ -f "$RESOLVER_FILE_DIR/$TEST_ZONE" ]; then
  t_check "A  this Mac's resolver lists primary AND backup" "re-run ./bin/phase2 setup on this Mac" resolver_has_backup
fi

ttl="$("$DIG" +noall +answer -p "$DNS_PORT" "@$DNS_IP" "$APP_DOMAIN" 2>/dev/null | awk 'NR==1{print $2}')"
t_check "B  record carries a TTL (${ttl:-none}s; ./bin/phase2 ttl demos it at ${DEMO_TTL}s)" "dnsmasq local-ttl missing" test -n "$ttl"

out="$(p2_iso_test 2>&1)"; rc=$?
sed 's/^/        /' <<<"$out"
if [ $rc -eq 0 ]; then t_pass "C  direct access to 3001/3002 matches the allow-list"
else t_warn "C  not isolated right now (expected until a backend Mac runs: ./bin/phase2 isolate on)"; fi

seq_out="$(sample_backends 8)"; t_info "responses: $seq_out"
[[ "$seq_out" == *A* && "$seq_out" == *B* && "$seq_out" != *\?* ]] && t_pass "D  both backends serve, no failed requests (stop one: ./bin/phase2 failover)" \
  || t_fail "D  both backends serve" "a backend is down or unreachable"

t_check "E  primary edge $EDGE_IP healthy" "nginx on Mac 2 is down" chk_edge_primary
if [ -n "$STANDBY_EDGE_IP" ]; then
  t_check "E  STANDBY edge $STANDBY_EDGE_IP healthy (same site, same certificate)" "on that Mac: ./bin/phase2 setup (needs the edge bundle)" chk_edge_standby
  a="$(edge_label_at "$EDGE_IP")"; b="$(edge_label_at "$STANDBY_EDGE_IP")"
  [ -n "$a" ] && [ -n "$b" ] && [ "$a" != "$b" ] && t_pass "E  the two edges are distinguishable (X-Edge: $a / $b)" || t_warn "E  X-Edge labels: '$a' / '$b' (cutover demo needs them to differ)"
fi

t_check "F  ./bin/doctor finds every layer healthy" "run ./bin/doctor for the first failing layer" "$REPO_ROOT/bin/doctor"
t_finish
