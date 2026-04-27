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
if command -v supabase >/dev/null 2>&1 && [ -n "${CHECK_REMOTE_MIGRATIONS:-}" ]; then
    echo "→ Querying remote ledger for name/version drift…"
    # Build local map: version -> name (without timestamp prefix and .sql suffix)
    local_pairs=$(
        cd "$MIGRATIONS_DIR" && \
        ls *.sql 2>/dev/null | \
        sed -E 's/^([0-9]{14})_(.*)\.sql$/\1 \2/'
    )

    # Pull remote ledger as JSON via supabase db query --linked
    remote_json=$(supabase db query --linked \
        "SELECT version, name FROM supabase_migrations.schema_migrations ORDER BY version;" 2>/dev/null || echo "")

    drift=0
    while read -r version local_name; do
        [ -z "$version" ] && continue
        # Look up remote name for this version (best-effort grep, no jq dependency)
        remote_name=$(echo "$remote_json" | grep -A1 "\"version\": \"${version}\"" | grep '"name"' | head -1 | sed -E 's/.*"name": "([^"]+)".*/\1/' || echo "")
        if [ -n "$remote_name" ] && [ "$remote_name" != "$local_name" ]; then
            echo "✗ Drift at ${version}: local='${local_name}' remote='${remote_name}'"
            drift=1
        fi
    done <<< "$local_pairs"

    if [ "$drift" -eq 0 ]; then
        echo "✓ Local migration names match remote ledger"
    else
        failed=1
    fi
else
    echo "↷ Remote ledger check skipped (set CHECK_REMOTE_MIGRATIONS=1 and link a project to enable)"
fi

if [ "$failed" -ne 0 ]; then
    exit 1
fi
echo
echo "All migration checks passed."
