#!/usr/bin/env bash
# Static integrity checks for supabase/migrations/.
#
# Catches the failure modes we hit on 2026-04-27:
#   1. Two .sql files squatting on the same timestamp prefix.
#   2. A local .sql file whose timestamp is already claimed in the remote
#      schema_migrations ledger by a differently-named migration.
#
# Exits non-zero on any failure so it can run as a pre-commit hook or CI step.
# Check (1) is pure-static. Check (2) requires a linked Supabase project and
# is skipped unless CHECK_REMOTE_MIGRATIONS=1 is set.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIGRATIONS_DIR="${REPO_ROOT}/supabase/migrations"

if [ ! -d "$MIGRATIONS_DIR" ]; then
    echo "✗ ${MIGRATIONS_DIR} not found"
    exit 1
fi

failed=0

# -----------------------------------------------------------------------------
# Check 1: Timestamp prefix collisions among .sql files.
# -----------------------------------------------------------------------------
collisions=$(
    cd "$MIGRATIONS_DIR" && \
    ls *.sql 2>/dev/null | \
    sed -E 's/^([0-9]{14})_.*/\1/' | \
    sort | uniq -d || true
)

if [ -n "$collisions" ]; then
    echo "✗ Timestamp prefix collisions detected:"
    while read -r ts; do
        [ -z "$ts" ] && continue
        echo "  Timestamp ${ts} is shared by:"
        ls "${MIGRATIONS_DIR}/${ts}"_*.sql 2>/dev/null | sed 's|^|    |'
    done <<< "$collisions"
    echo
    echo "  Resolve by renaming one of each pair to a fresh timestamp, or by"
    echo "  marking the orphaned one as '.sql.disabled' if it should not run."
    failed=1
else
    echo "✓ No timestamp prefix collisions among .sql files"
fi

# -----------------------------------------------------------------------------
# Check 2: Remote-ledger consistency. Skipped unless explicitly requested,
# since it requires a linked Supabase project and a few seconds of network IO.
# -----------------------------------------------------------------------------
if [ "${CHECK_REMOTE_MIGRATIONS:-}" = "1" ]; then
    if ! command -v supabase >/dev/null 2>&1; then
        echo "✗ Remote ledger check requested, but the Supabase CLI is unavailable" >&2
        exit 1
    fi
    echo "→ Querying remote ledger for name/version drift…"
    if ! remote_json=$(supabase db query --linked --output json \
        "SELECT version, name FROM supabase_migrations.schema_migrations ORDER BY version;"); then
        echo "✗ Remote ledger query failed; migration consistency is unverified" >&2
        exit 1
    fi

    if ! REMOTE_MIGRATION_JSON="$remote_json" python3 - "$MIGRATIONS_DIR" <<'PYTHON'
import json
import os
from pathlib import Path
import re
import sys

try:
    payload = json.loads(os.environ["REMOTE_MIGRATION_JSON"])
    rows = payload.get("rows") if isinstance(payload, dict) else payload
    if not isinstance(rows, list):
        raise ValueError("expected a JSON row array or an object containing rows")
    remote = {}
    for row in rows:
        if not isinstance(row, dict):
            raise ValueError("invalid ledger row")
        version, name = row.get("version"), row.get("name")
        if not isinstance(version, str) or not re.fullmatch(r"[0-9]{14}", version):
            raise ValueError("invalid ledger version")
        if not isinstance(name, str) or not name or version in remote:
            raise ValueError("missing name or duplicate ledger version")
        remote[version] = name
except (ValueError, KeyError) as error:
    print(f"✗ Remote ledger response is invalid: {error}", file=sys.stderr)
    sys.exit(1)

shared = 0
drift = False
for path in Path(sys.argv[1]).glob("*.sql"):
    match = re.fullmatch(r"([0-9]{14})_(.+)\.sql", path.name)
    if not match:
        print(f"✗ Invalid local migration filename: {path.name}", file=sys.stderr)
        drift = True
        continue
    version, local_name = match.groups()
    if version in remote:
        shared += 1
        if remote[version] != local_name:
            print(f"✗ Drift at {version}: local={local_name!r} remote={remote[version]!r}")
            drift = True
if drift:
    sys.exit(1)
print(f"✓ No name drift among {shared} shared versions ({len(remote)} remote rows checked)")
PYTHON
    then
        failed=1
    fi
else
    echo "↷ Remote ledger check skipped (set CHECK_REMOTE_MIGRATIONS=1 and link a project to enable)"
fi

if [ "$failed" -ne 0 ]; then
    exit 1
fi
echo
echo "All requested migration checks passed."
