# Deterministic regression checks

CI compiles both Xcode test bundles and runs a named simulator selection, runs the listed Deno suites without network permission, and runs `python3 supabase/tests/ci/run_sql.py` for SQL.

The SQL runner starts a fresh, uniquely named Supabase PostgreSQL container, applies every application migration, and executes the selected rollback-based suites, including family invitation acceptance and member removal. It publishes no ports, disables Docker networking and cron execution, and removes only its own container and disposable volumes on exit. It does not accept a database URL or use a hosted Supabase project. Logs remain in `artifacts/ci-sql/`.

The pinned PostgreSQL image initializes legacy Auth tables/helpers and a Storage namespace. The fixture supplies the Auth email confirmation timestamp, minimal identities/session tables and refresh-token cascade used by account notification tests, current JWT helper behavior, a limited Storage table/helper subset, and signup seed/trigger prerequisites omitted from the public-only baseline. These fixtures are test setup, not application migrations. They verify SQL behavior against simulated platform prerequisites; they do not verify the Supabase Auth or Storage HTTP APIs.

The sign-in UI suite uses `--auth-ui-test` with an in-memory signed-out state and controlled rejection. The separate `AuthBackendIntegrationTests` probe is skipped unless `MINDFRIEND_RUN_LIVE_AUTH_TESTS=1`, `MINDFRIEND_LIVE_AUTH_URL`, and `MINDFRIEND_LIVE_AUTH_ANON_KEY` are explicitly supplied. CI supplies none of them. Device, live-service, and App Store checks are outside this workflow.
