#!/usr/bin/env bash
# status for role: pratyush  (implementation: scripts/role.sh)
set -euo pipefail
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/role.sh" pratyush status "$@"
