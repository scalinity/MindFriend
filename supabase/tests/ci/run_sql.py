#!/usr/bin/env python3
"""Run application SQL regressions in a disposable, network-isolated platform fixture."""
import subprocess
import time
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
IMAGE = "public.ecr.aws/supabase/postgres:17.11.0.006"
DATABASE = "restoration_synthetic"
SUITES = (
    "monthly_ai_budget.test.sql",
    "provider_accounting.sql",
    "notification_categories.sql",
    "core_completion_repairs.sql",
    "companion_canonical_integration.sql",
    "content_report_authorization.sql",
    "recipient_entitlement.sql",
    "sponsored_entitlement.sql",
    "family_member_removal.sql",
    "family_invitation_acceptance.sql",
    "apple_account_notifications.sql",
    "mentorship_messages.sql",
    "drift_reconciliation.sql",
    "current_premium_access.sql",
    "pending_celebrations.sql",
)


def main():
    name = "mindfriend-ci-sql-" + uuid.uuid4().hex[:12]
    output = ROOT / "artifacts" / "ci-sql" / name
    output.mkdir(parents=True)
    created = False

    def run(arguments, *, label, timeout=120):
        result = subprocess.run(arguments, capture_output=True, text=True, timeout=timeout)
        (output / (label + ".log")).write_text(result.stdout + result.stderr)
        if result.returncode:
            raise RuntimeError(f"{label} failed ({result.returncode}); see {output / (label + '.log')}")
        return result.stdout.strip()

    def sql(path, *, service_claim=False):
        args = ["docker", "exec", name, "psql", "-X", "-U", "supabase_admin", "-d", DATABASE,
                "-v", "ON_ERROR_STOP=1"]
        if path.parent.name == "migrations":
            args.append("--single-transaction")
        if service_claim:
            args += ["-c", "SELECT set_config('request.jwt.claims','{\"role\":\"service_role\"}',false);"]
        run(args + ["-f", "/repo/" + str(path.relative_to(ROOT))], label=path.name)
        print("PASS:", path.relative_to(ROOT), flush=True)

    try:
        run(["docker", "create", "--name", name, "--network", "none",
             "--env", "POSTGRES_PASSWORD=synthetic-ci-only", "--env", "POSTGRES_USER=supabase_admin",
             "--env", f"POSTGRES_DB={DATABASE}",
             "--mount", f"type=bind,src={ROOT / 'supabase'},dst=/repo/supabase,readonly",
             IMAGE, "postgres", "-D", "/etc/postgresql",
             "-c", f"cron.database_name={DATABASE}", "-c", "cron.launch_active_jobs=off",
             "-c", "shared_preload_libraries=pg_stat_statements,pg_cron,pg_net",
             "-c", "wal_level=logical"], label="create-container")
        created = True
        run(["docker", "start", name], label="start")
        deadline = time.monotonic() + 120
        while True:
            # The entrypoint starts a temporary server during initialization.
            # Its postmaster PID differs from the final server running as container PID 1.
            process = subprocess.run(["docker", "exec", name, "head", "-n", "1",
                                      "/var/lib/postgresql/data/postmaster.pid"],
                                     capture_output=True, text=True, timeout=15)
            if process.returncode != 0 or process.stdout.strip() != "1":
                if time.monotonic() >= deadline:
                    raise RuntimeError("Synthetic database initialization did not finish")
                time.sleep(1)
                continue
            ready = subprocess.run(["docker", "exec", name, "psql", "-X", "-U", "supabase_admin",
                "-d", DATABASE, "-At", "-c",
                "SELECT current_setting('shared_preload_libraries') LIKE '%pg_net%' "
                "AND EXISTS(SELECT 1 FROM pg_roles WHERE rolname='service_role');"],
                capture_output=True, text=True, timeout=15)
            if ready.returncode == 0 and ready.stdout.strip() == "t":
                break
            if time.monotonic() >= deadline:
                raise RuntimeError("Synthetic database did not finish platform initialization")
            time.sleep(1)
        for filename in ("platform-bootstrap.sql", "platform-auth-fixture.sql", "platform-storage-fixture.sql"):
            sql(ROOT / "supabase/tests/ci" / filename)
        migrations = sorted((ROOT / "supabase/migrations").glob("*.sql"))
        if not migrations:
            raise RuntimeError("No application migrations found")
        for migration in migrations:
            sql(migration)
        sql(ROOT / "supabase/tests/ci/test-prerequisites.sql")
        for suite in SUITES:
            sql(ROOT / "supabase/tests" / suite, service_claim=suite == "provider_accounting.sql")
        state = run(["docker", "exec", name, "psql", "-X", "-U", "supabase_admin", "-d", DATABASE,
            "-At", "-v", "ON_ERROR_STOP=1", "-c", "SELECT (SELECT count(*) FROM auth.users), "
            "(SELECT count(*) FROM public.profiles), (SELECT count(*) FROM cron.job_run_details);"], label="final-state")
        if state != "0|0|0":
            raise RuntimeError("Synthetic test data or scheduled jobs escaped rollback: " + state)
        print(f"PASS: {len(SUITES)} SQL suites; no users, profiles, or executed cron jobs. Logs: {output}")
    finally:
        if created:
            try:
                logs = subprocess.run(["docker", "logs", name], capture_output=True, text=True, timeout=30)
                (output / "container.log").write_text(logs.stdout + logs.stderr)
            finally:
                subprocess.run(["docker", "rm", "--force", "--volumes", name], check=True, timeout=30)


if __name__ == "__main__":
    main()
